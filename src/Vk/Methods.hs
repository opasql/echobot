{- |
Copyright:  (c) 2021 o-pascal
Maintainer: o-pascal <rtrn.0@ya.ru>

Vk API methods.
-}
module Vk.Methods
    ( -- * Available methods
      Method
      -- ** Long Poll Server
    , getLps
    , checkLps
      -- ** Send messages
    , sendTextWithAttachments
    , sendSticker
    , sendAudioMessage
      -- Answer commands
    , repeatCommand
    , answerRepeatPayload
    , startCommand
    ) where

import           AppState
import           Control.Monad
import           Control.Monad.Freer
import           Control.Monad.Freer.State
import           Data.ByteString           (ByteString)
import           Data.Maybe
import           Data.Text                 (Text, splitOn, unpack)
import           Web.HttpApiData           (toUrlPiece)

import           Eff.Error
import           Eff.Https                 hiding (get)
import           Eff.Log                   hiding (Config)
import           Eff.Random

import           Vk.Config
import           Vk.Data
import           Vk.Parser
import           Vk.Requests

-- | Simple shortcut for methods constraints
type Method r = Members
    [ Https
    , Log
    , State Config
    , State VkState
    , Error AppError
    , Random
    ] r

type MethodWithCallStack r = (Method r, HasCallStack)

-- | Add group_id, token and api_version to parameters.
completeParams
    :: Members [State Config, State VkState] r
    => FormUrlEncodedParam
    -> Eff r ReqBodyUrlEnc
completeParams params = do
    Config {..} <- get
    pure . url $ params
        <>  "group_id" =: groupId
        <> "access_token" =: token
        <> "v" =: (5.122 :: Float)

-- | Get Long Poll Server.
getLps :: MethodWithCallStack r => Eff r GetLpsResponse
getLps = do
    params <- completeParams mempty
    logInfo "Requesting Long Poll Server"
    result <- post (https "api.vk.com"
                     /: "method"
                     /: "groups.getLongPollServer"
                     )
                 params
    tryExtract result

-- | Check Long Poll Server for 'Update's.
-- This method also adds new 'Session's for new users.
checkLps :: MethodWithCallStack r => Eff r [Update]
checkLps = do
    logInfo "Waiting for updates..."
    params <- mkParams
    server <- gets (fromJust . checkLpsServer)
    resp <- post server params
    case checkLpsResp'failed resp of
        Just e -> do
            logError $ "CheckLps failed: " <+> e
            throwError . OtherError $ showT resp
        Nothing -> do
            let ups = checkLpsResp'updates resp
            logDebug $ "Received response: " <+> resp
            logInfo $ "Updates received: " <+> length ups
            putNewTs resp
            sessions <- putNewSessions ups
            logDebug $ "Current sessions: " <+> sessions
            pure ups

  where
    mkParams :: Members [State Config, State VkState] r => Eff r ReqBodyUrlEnc
    mkParams = do
        ts <- (gets @VkState) st'offset
        Config {..} <- get
        pure . url $
               "act" =: ACheck
            <> "key" =: checkLpsKey
            <> "wait" =: (25 :: Int)
            <> "ts" =: ts

    putNewTs :: Members [Log, State VkState] r => CheckLpsResponse -> Eff r ()
    putNewTs resp = case checkLpsResp'ts resp of
        Just ts -> modify (\st -> st { st'offset = ts })
        Nothing -> logWarning "No new Ts. Proceeding with an old one."

    putNewSessions :: Members [State VkState, State Config] r => [Update] -> Eff r SesMap
    putNewSessions [] = (gets @VkState) st'sessions
    putNewSessions (u:us) = do
        n <- gets initialRepNum
        case u <?> updateUserId of
            Just uid -> (modify @VkState) (newSession uid n) >> putNewSessions us
            _        -> putNewSessions us

-- | Vk API messages.send method.
sendMessage :: MethodWithCallStack r
            => Int -- ^ User id
            -> Maybe Int -- ^ Repetition number
            -> FormUrlEncodedParam
            -> Text -- ^ Hint
            -> Eff r Int
sendMessage userId mRepNum params hint = do
    repNum <- maybe (gets @VkState $ getRepNum userId) pure mRepNum
    logInfo $ "Sending " <> hint <> " to user " <+> userId
        <> " (repeat: " <+> repNum <> ")"
    result <- fmap head . replicateM repNum $ do
        rand <- (`mod` 10000000) <$> random
        logDebug $ "random_id: " <+> rand
        fullParams <- completeParams $ params
            <> "user_id" =: userId
            <> "random_id" =: rand
        post (https "api.vk.com"
                 /: "method"
                 /: "messages.send"
             )
             fullParams
    tryExtract result

-- | Send text and list of 'Attachment's
sendTextWithAttachments :: MethodWithCallStack r
            => Int -- ^ User id
            -> Text
            -> [Attachment]
            -> Eff r Int
sendTextWithAttachments userId t atts = do
    let params = "message" =: t
              <> "attachment" =: atts
    sendMessage userId Nothing params "text with attachments"

-- | Send stickers.
sendSticker :: MethodWithCallStack r
            => Int -- ^ User id
            -> Int -- ^ Sticker id
            -> Eff r Int
sendSticker userId s = do
    let params = "sticker_id" =: s
    sendMessage userId Nothing params "sticker"

sendAudioMessage :: MethodWithCallStack r
                 => Int -- ^ User id
                 -> Url -- ^ Link to download audio message
                 -> Eff r Int
sendAudioMessage userId link = do
    logDebug "Downloading audio message"
    let filePath = unpack . last . splitOn "/" $ renderUrl link
    ogg <- getBS link
    server <- getMsgUploadServ'upload_url
        <$> getMessagesUploadServer userId AudioMessage
    file <- uploadFileResp'file
        <$> uploadFile server filePath ogg
    audio <- saveFile file
    sendTextWithAttachments
        userId
        ""
        [audio]

-- | Returns the server address for document upload.
getMessagesUploadServer :: MethodWithCallStack r
                        => Int -- ^ UserId
                        -> AttachmentType
                        -> Eff r GetMessagesUploadServerResponse
getMessagesUploadServer userId atType = do
    logDebug $ "Getting upload server for " <+> atType
    params <- completeParams $ "type" =: atType <> "peer_id" =: userId
    result <- post (https "api.vk.com"
                       /: "method"
                       /: "docs.getMessagesUploadServer"
                   ) params
    tryExtract result

-- | Upload a file to server. Get server via 'getMessagesUploadServer'.
uploadFile :: MethodWithCallStack r
           => Url -- ^ Server
           -> FilePath
           -> ByteString -- ^ File
           -> Eff r UploadFileResponse
uploadFile server filePath file = do
    logDebug "Uploading audio message"
    postMultipart server "file" filePath file

-- | Save media after uploading it viq 'uploadFile'.
saveFile :: MethodWithCallStack r
         => Text -- ^ File
         -> Eff r Attachment
saveFile file = do
    logDebug "Saving file"
    params <- completeParams $ "file" =: file
    result <- post (https "api.vk.com"
                       /: "method"
                       /: "docs.save"
                   ) params
    tryExtract result

-- | Answer to user on \/repeat command.
repeatCommand :: MethodWithCallStack r
              => Int -- ^ User id
              -> Eff r Int
repeatCommand userId = do
    logInfo "Received /repeat command"
    let params = "message" =: greeting
              <> "keyboard" =: keyboard
    logDebug $ "Params: " <> toUrlPiece keyboard
    sendMessage userId (Just 1) params "inline keyboard"
  where
    keyboard = Keyboard
        { keyboard'one_time = Just True
        , keyboard'inline = False
        , keyboard'buttons = buttons
        }

    buttons = let but n = Button
                    { button'action = ButtonAction
                        { btnAct'type = Text
                        , btnAct'label =  showT n
                        , btnAct'payload = showT n
                        }
                    , button'color = Primary
                    }
              in [[but n | n <- [1..3 :: Int]], [but n | n <- [4, 5 :: Int]]]
    greeting :: Text
    greeting = "Choose how many times you want me to repeat your message."

-- | Answer to user after he/she pressed button
-- of inline keyboard sent after \/repeat command.
answerRepeatPayload :: MethodWithCallStack r
                    => Int -- ^ User id
                    -> Text -- ^ Payload
                    -> Eff r Int
answerRepeatPayload userId pl = do
    logInfo $ "Received payload: " <+> pl
    logInfo $ "Changing repetition number for " <+> userId <> " to " <> pl
    let n = read $ unpack pl
        params = "message" =: (confirmationText . read $ unpack pl)
    modify @VkState (changeRepNum userId n)
    sendMessage userId (Just 1) params "repeat confirmation"
  where
    confirmationText :: Int -> Text
    confirmationText n = "I will repeat your messages " <+> n <> " time"
        <> if n > 1 then "s." else "."

-- | Send to user helpful information on \/start command.
startCommand :: MethodWithCallStack r
             => Int -- User id
             -> Eff r Int
startCommand userId = do
    logInfo "Received /start command"
    t <- gets @Config startMessage
    let params = "message" =: t
    sendMessage userId Nothing params "start message"


