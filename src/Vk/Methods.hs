{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE KindSignatures    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds         #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeOperators     #-}
module Vk.Methods where

import           Control.Monad.IO.Class
import           Control.Monad.Reader   (local)
import           Data.Proxy
import           Data.Text              (Text, unpack)
import           Servant.API
import           Servant.Client         hiding (Response)
import           System.Random          (randomIO)

import           Vk.Methods.Request
import           Vk.Types


type RequiredParam = QueryParam' '[Required, Strict]
type OptionalParam = QueryParam' '[Optional, Strict]

type VkMethod (verb :: [*] -> * -> *) (response :: *)
    =  RequiredParam "access_token" Token
    :> RequiredParam "v" Double
    :> verb '[JSON] response

type CheckLps
    =  RequiredParam "act" CheckLpsAction
    :> RequiredParam "key" LpsKey
    :> OptionalParam "wait" Int
    :> RequiredParam "ts" Ts
    :> Post '[JSON] CheckLpsResponse

checkLps :: CheckLpsParams -> ClientM CheckLpsResponse
checkLps CheckLpsParams{..} = do
    burl <- parseBaseUrl (unpack checkLpsServer)
    local (\e -> e { baseUrl = burl }) $
        client
            (Proxy @CheckLps)
            checkLpsAction
            checkLpsKey
            checkLpsWait
            checkLpsTs

getUpdates :: CheckLpsParams -> ClientM [Update]
getUpdates = fmap checkLpsResponseUpdates . checkLps

type SendMessage
    =  "messages.send"
    :> RequiredParam "user_id" UserId
    :> RequiredParam "random_id" Int
    :> RequiredParam "message" Text
    :> VkMethod Post SendMessageResponse

sendMessage :: SendMessageParams -> ClientM SendMessageResponse
sendMessage SendMessageParams{..} = do
    randId <- liftIO randomIO
    client
        (Proxy @SendMessage)
        sendMessageUserId
        (randId :: Int)
        sendMessageMessage
        sendMessageAccessToken
        sendMessageApiVersion

type GetLps
    =  "groups.getLongPollServer"
    :> RequiredParam "group_id" Integer
    :> VkMethod Post GetLpsResult

getLps :: GetLpsParams -> ClientM GetLpsResult
getLps GetLpsParams{..} = client
    (Proxy @GetLps)
    getLpsGroupId
    getLpsToken
    getLpsApiVersion
