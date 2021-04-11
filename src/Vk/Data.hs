{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell            #-}

module Vk.Data where

import           AppState              (AppState (..))
import           Control.Applicative   ((<|>))
import           Data.Aeson            hiding (Object)
import           Data.Aeson.Text       (encodeToLazyText)
import           Data.HashMap.Strict   (fromList)
import           Data.Maybe            (fromMaybe)
import           Data.Text             (Text, intercalate, pack)
import           Data.Text.Lazy        (toStrict)
import           Data.Text.Read        (decimal)
import           Data.Time.Clock.POSIX (POSIXTime)
import           TH                    (deriveFromJSON', deriveToJSON',
                                        snakeFieldModifier)
import           Eff.Log                 (showT)
import           Web.HttpApiData       (ToHttpApiData (..))

type VkState = AppState Ts

defaultVkState :: VkState
defaultVkState = AppState
    { st'offset = Ts 0
    , st'sessions = fromList []
    }

newtype Ts = Ts Integer
    deriving (Show, Eq, Num)

instance ToJSON Ts where
    toJSON (Ts ts) = toJSON $ show ts

instance FromJSON Ts where
    parseJSON = withText "Ts" readTs
      where
        readTs = pure . either error (Ts . fst) . decimal

instance ToHttpApiData Ts where
    toUrlPiece (Ts ts) = toUrlPiece ts

data Update = Update
    { upd'type   :: UpdateType
    , upd'object :: Object
    } deriving (Show)

data UpdateType
    = MessageNew
    | MessageReply
    | MessageEdit
    | MessageAllow
    | MessageDeny
    | MessageTypingState
    | MessageEvent
    deriving (Show)

newtype Object = Object
    { obj'message    :: Maybe Message
    } deriving (Show)

data Message = Message
    { msg'id            :: Maybe Int
    , msg'date          :: POSIXTime
    , msg'peer_id       :: Maybe Int
    , msg'from_id       :: Maybe Int
    , msg'text          :: Text
    , msg'attachments   :: [Attachment]
    , msg'payload       :: Maybe Text
    , msg'fwd_messages  :: Maybe [Message]
    , msg'reply_message :: Maybe Message
    } deriving (Show)

data Attachment = Attachment
    { attachment'type  :: AttachmentType
    , attachment'media :: Media
    } deriving (Show)

instance FromJSON Attachment where
    parseJSON = withObject "attachment" $ \o -> do
        attachment'type <- o .: "type"
        attachment'media <- o .: "photo"
            <|> o .: "video"
            <|> o .: "audio"
            <|> o .: "audio_message"
            <|> o .: "sticker"
            <|> o .: "doc"
            <|> o .: "link"
            <|> o .: "market"
            <|> o .: "wall"
        pure Attachment{..}

instance ToHttpApiData Attachment where
    toUrlPiece (Attachment atType Media{..}) =
        toUrlPiece atType <> case atType of
            Link    -> mempty
            Sticker -> mempty
            Wall    -> maybe "" showT media'from_id
                <> "_"
                <> maybe "" showT media'id
                <> "_"
                <> fromMaybe "" media'access_key
            _       -> maybe "" showT media'owner_id
                <> "_"
                <> maybe "" showT media'id
                <> "_"
                <> fromMaybe "" media'access_key

instance ToHttpApiData [Attachment] where
    toUrlPiece xs = intercalate "," $ toUrlPiece <$> xs

data AttachmentType
    = Photo
    | Video
    | Audio
    | AudioMessage
    | Doc
    | Link
    | Market
    | Wall
    | Sticker
    deriving (Show)

instance ToHttpApiData AttachmentType where
    toUrlPiece = pack . snakeFieldModifier "" . show

data Media = Media
    { media'id          :: Maybe Int
    , media'from_id     :: Maybe Int
    , media'owner_id    :: Maybe Int
    , media'access_key  :: Maybe Text
    , media'attachments :: Maybe [Attachment]
    , media'sticker_id  :: Maybe Int
    , media'url         :: Maybe Text
    , media'title       :: Maybe Text
    , media'caption     :: Maybe Text
    , media'description :: Maybe Text
    } deriving (Show)


data Keyboard = Keyboard
    { keyboard'one_time :: Maybe Bool
    , keyboard'buttons  :: [[Button]]
    , keyboard'inline   :: Bool
    } deriving (Show)

instance ToHttpApiData Keyboard where
    toUrlPiece = toStrict . encodeToLazyText

data Button = Button
    { button'action :: ButtonAction
    , button'color  :: ButtonColor
    } deriving (Show)

instance ToHttpApiData Button where
    toUrlPiece = toStrict . encodeToLazyText

data ButtonColor
    = Primary
    | Secondary
    | Negative
    | Positive
    deriving (Show)

instance ToHttpApiData ButtonColor where
    toUrlPiece = toStrict . encodeToLazyText

data ButtonAction = ButtonAction
    { btnAct'type    :: ButtonActionType
    , btnAct'label   :: Text
    , btnAct'payload :: Text
    } deriving (Show)

instance ToHttpApiData ButtonAction where
    toUrlPiece = toStrict . encodeToLazyText

data ButtonActionType
    = Text
    deriving (Show)

instance ToHttpApiData ButtonActionType where
    toUrlPiece = toStrict . encodeToLazyText

instance ToJSON ButtonActionType where
    toJSON Text = "text"

deriveToJSON' ''ButtonAction
deriveToJSON' ''ButtonColor
deriveToJSON' ''Button
deriveToJSON' ''Keyboard

deriveFromJSON' ''Media
deriveFromJSON' ''AttachmentType
deriveFromJSON' ''Message
deriveFromJSON' ''Object
deriveFromJSON' ''UpdateType
deriveFromJSON' ''Update