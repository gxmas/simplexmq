{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

module Simplex.Messaging.Agent.Env.Postgres
  ( AgentConfig (..),
    defaultAgentConfig,
    Env (..),
    newSMPAgentEnv,
  )
where

import Control.Monad.IO.Unlift
import Crypto.Random
import Data.List.NonEmpty (NonEmpty)
import Data.Time.Clock (NominalDiffTime, nominalDay)
import Database.PostgreSQL.Simple (ConnectInfo (..), defaultConnectInfo)
import Network.Socket
import Numeric.Natural
import Simplex.Messaging.Agent.Protocol (SMPServer)
import Simplex.Messaging.Agent.RetryInterval
import Simplex.Messaging.Agent.Store.Postgres
import qualified Simplex.Messaging.Agent.Store.Postgres.Migrations as Migrations
import Simplex.Messaging.Client
import qualified Simplex.Messaging.Crypto as C
import System.Random (StdGen, newStdGen)
import UnliftIO.STM

data AgentConfig = AgentConfig
  { tcpPort :: ServiceName,
    smpServers :: NonEmpty SMPServer,
    cmdSignAlg :: C.SignAlg,
    connIdBytes :: Int,
    tbqSize :: Natural,
    dbConnInfo :: ConnectInfo,
    dbPoolSize :: Int,
    smpCfg :: SMPClientConfig,
    reconnectInterval :: RetryInterval,
    helloTimeout :: NominalDiffTime,
    caCertificateFile :: FilePath,
    privateKeyFile :: FilePath,
    certificateFile :: FilePath
  }

defaultAgentConfig :: AgentConfig
defaultAgentConfig =
  AgentConfig
    { tcpPort = "5224",
      smpServers = undefined, -- TODO move it elsewhere?
      cmdSignAlg = C.SignAlg C.SEd448,
      connIdBytes = 12,
      tbqSize = 16,
      dbConnInfo = defaultConnectInfo {connectDatabase = "agent_poc_1"},
      dbPoolSize = 4,
      smpCfg = smpDefaultConfig,
      reconnectInterval =
        RetryInterval
          { initialInterval = second,
            increaseAfter = 10 * second,
            maxInterval = 10 * second
          },
      helloTimeout = 7 * nominalDay,
      -- CA certificate private key is not needed for initialization
      -- ! we do not generate these
      caCertificateFile = "/etc/opt/simplex-agent/ca.crt",
      privateKeyFile = "/etc/opt/simplex-agent/agent.key",
      certificateFile = "/etc/opt/simplex-agent/agent.crt"
    }
  where
    second = 1_000_000

data Env = Env
  { config :: AgentConfig,
    store :: PostgresStore,
    idsDrg :: TVar ChaChaDRG,
    clientCounter :: TVar Int,
    randomServer :: TVar StdGen
  }

newSMPAgentEnv :: (MonadUnliftIO m, MonadRandom m) => AgentConfig -> m Env
newSMPAgentEnv cfg@AgentConfig {dbConnInfo, dbPoolSize} = do
  idsDrg <- newTVarIO =<< drgNew
  -- store <- liftIO $ createPostgresStore dbConnInfo dbPoolSize Migrations.app
  store <- liftIO $ createPostgresStore dbConnInfo dbPoolSize
  clientCounter <- newTVarIO 0
  randomServer <- newTVarIO =<< liftIO newStdGen
  return Env {config = cfg, store, idsDrg, clientCounter, randomServer}
