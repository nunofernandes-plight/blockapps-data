{-# LANGUAGE EmptyDataDecls             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}

module Blockchain.DBM (
  DBs(..),
  DBM,
  DBsLite(..),
  DBMLite,
  HasSQLDB(..),
  HasBlockDB(..),
  HasDetailsDB(..),
  HasStateDB(..),
  HasHashDB(..),
  HasCodeDB(..),
  --setStateRoot,
  getStateRoot,
  openDBs,
  openDBsLite,
  DetailsDB,
  BlockDB,
  CodeDB,
  HashDB,
  SQLDB
  ) where


import qualified Database.LevelDB as DB

import Control.Monad.IO.Class
import Control.Monad.State
import Control.Monad.Trans.Resource
import qualified Data.ByteString as B
import System.Directory
import System.FilePath
--import Text.PrettyPrint.ANSI.Leijen hiding ((<$>), (</>))

import           Control.Monad.Logger    (runStderrLoggingT,runNoLoggingT)
import qualified Database.Persist            as P
import qualified Database.Persist.Postgresql as SQL
import           Database.Persist.TH
import           Database.Persist.Types

import Blockchain.Constants
import Blockchain.Database.MerklePatricia
import Blockchain.Data.Transaction
import Blockchain.Data.DataDefs
import Blockchain.Data.Code

--import Debug.Trace

type BlockDB = DB.DB
type CodeDB = DB.DB
type DetailsDB = DB.DB
type HashDB = DB.DB
type SQLDB = SQL.ConnectionPool
  

data DBs =
  DBs {
    blockDB'::BlockDB,
    detailsDB'::DetailsDB,
    stateDB'::MPDB,
    codeDB'::CodeDB,
    hashDB'::HashDB,
    sqlDB'::SQLDB
    }

data DBsLite =
  DBsLite {
     sqlDBLite :: SQLDB
     }

class MonadResource m=>HasBlockDB m where
  getBlockDB::Monad m=>m BlockDB

class MonadResource m=>HasDetailsDB m where
  getDetailsDB::Monad m=>m DetailsDB

class MonadResource m=>HasStateDB m where
  getStateDB::Monad m=>m MPDB
  setStateDBStateRoot::Monad m=>SHAPtr->m ()

class MonadResource m=>HasHashDB m where
  getHashDB::Monad m=>m HashDB

class MonadResource m=>HasCodeDB m where
  getCodeDB::Monad m=>m CodeDB

class Monad m=>HasSQLDB m where
  getSQLDB::Monad m=>m SQLDB

type DBM = StateT DBs (ResourceT IO)
type DBMLite = StateT DBsLite (ResourceT IO)

connStr = "host=localhost dbname=eth user=postgres password=api port=5432"

{-
setStateRoot::HasStateDB m=>SHAPtr->m ()
setStateRoot stateRoot' = do
  ctx <- getStateDB
  put ctx{stateDB=(stateDB ctx){stateRoot=stateRoot'}}
-}

getStateRoot::HasStateDB m=>m SHAPtr
getStateRoot = do
  db <- getStateDB
  return $ stateRoot db


options::DB.Options
options = DB.defaultOptions {
  DB.createIfMissing=True, DB.cacheSize=1024}

openDBs::String->ResourceT IO DBs
openDBs theType = do
  homeDir <- liftIO getHomeDirectory                     
  liftIO $ createDirectoryIfMissing False $ homeDir </> dbDir theType
  bdb <- DB.open (homeDir </> dbDir theType ++ blockDBPath) options
  ddb <- DB.open (homeDir </> dbDir theType ++ detailsDBPath) options
  sdb <- DB.open (homeDir </> dbDir theType ++ stateDBPath) options
  sqldb <-   runNoLoggingT  $ SQL.createPostgresqlPool connStr 20
  SQL.runSqlPool (SQL.runMigration migrateAll) sqldb
  return $ DBs
      bdb
      ddb
      MPDB{ ldb=sdb, stateRoot=error "no stateRoot defined"}
      sdb
      sdb
      sqldb

openDBsLite :: SQL.ConnectionString -> ResourceT IO DBsLite
openDBsLite connectionString = do
  sqldb <- runNoLoggingT  $ SQL.createPostgresqlPool connectionString 20
  SQL.runSqlPool (SQL.runMigration migrateAll) sqldb
  return $ DBsLite sqldb
