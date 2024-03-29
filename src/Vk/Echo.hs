{- |
Copyright:  (c) 2021 o-pascal
Maintainer: o-pascal <rtrn.0@ya.ru>

Vk implementation of 'Echo' effect.
-}

module Vk.Echo
    ( -- * Vk echo
      -- ** Run
      runPureEcho
    ) where

import           Control.Monad.Freer (Eff, interpret)

import           Control.Monad       (void)
import           Data.Foldable       (asum)

import           Eff.Echo            (Echo (..))
import           Eff.Log             (logWarning, (<+>))

import           Vk.Data             (Update)
import           Vk.Methods
import           Vk.Parser

-- | Run 'Echo'for Telegram purely.
runPureEcho
    :: Method r
    => Eff (Echo Update : r) a
    -> Eff r a
runPureEcho = interpret $ \case
    Listen -> checkLps
    Reply u -> case updateToAction u of
        Just act -> act
        Nothing  -> logWarning $ "No matching Action for this Update: " <+> u

-- | Choose proper Vk API method for a given 'Update'.
-- This makes use of Alternative instance for 'Parser'.
updateToAction
    :: Method r
    => Update
    -> Maybe (Eff r ())
updateToAction = runParser . asum $ fmap (fmap void)
    [ startCommand <$ command "start" <*> updateUserId
    , answerRepeatPayload <$> updateUserId <*> payload
    , repeatCommand <$ command "repeat" <*> updateUserId
    , sendAudioMessage <$> updateUserId <*> audioMessage
    , sendSticker <$> updateUserId <*> sticker
    , sendTextWithAttachments <$> updateUserId <*> text <*> attachments
    ]
