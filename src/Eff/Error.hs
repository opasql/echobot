module Eff.Error
    ( AppError (..)
    , module M
    ) where

import           Control.Exception         as M
import           Control.Monad.Freer.Error as M
import           Data.Text                 (Text)
import           Network.HTTP.Req          as M (HttpException)

data AppError
    = FileProviderError
        IOException
    | ConfiguratorError
        { path        :: FilePath
        , description :: String
        }
    | HttpsError
        HttpException
    | OtherError
        Text
    deriving Show