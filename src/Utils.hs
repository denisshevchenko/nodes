module Utils where

import           Types

import           Data.Time.Clock.POSIX              ( getPOSIXTime )
import           Control.Concurrent                 ( threadDelay )
import           Control.Monad.IO.Class             ( MonadIO ) 
import           Control.Distributed.Process        ( Process
                                                    , NodeId
                                                    , liftIO
                                                    , nsendRemote
                                                    )
import qualified Control.Distributed.Backend.P2P    as P2P
import           System.IO                          ( hPutStrLn, stderr )
import           System.Random                      ( randomR
                                                    , randomRIO
                                                    , mkStdGen
                                                    )

-- | Return current UTC time as Double-value of seconds with milliseconds.
getTimeStamp :: IO SendingTime
getTimeStamp = getPOSIXTime >>= return . fromRational . toRational

-- | Generates random number with or without seed.
generateRandomNumber :: Maybe Int -> IO Double
generateRandomNumber maybeSeed = case maybeSeed of
    Just s  -> return $ let (n, _) = randomR range $ mkStdGen s in n
    Nothing -> randomRIO range
  where
    range = (0.00000000000000001, 1.0)  -- Yes, I know that it's not the lowest possible value. ;-)

delayForDispatcher :: Int
delayForDispatcher = 1

-- | We send this message to all nodes when sending period is over.
stopMessage :: NumberMessage
stopMessage = (0.0, -1.0)

-- | Forms NodeId from raw endpoint address (from nodes config file).
makeNodeIdFrom :: NodeEndpoint -> NodeId
makeNodeIdFrom (NodeEndpoint ip port) = P2P.makeNodeId $ ip ++ ":" ++ show port

-- | Stops current thread for N seconds.
waitForSeconds :: MonadIO m => Int -> m ()
waitForSeconds s = liftIO . threadDelay $ s * 1000000

-- | Stops current thread for N milliseconds.
waitForMilliSeconds :: MonadIO m => Int -> m ()
waitForMilliSeconds s = liftIO . threadDelay $ s * 1000

-- | Reports about some problem.
report :: Show a => WhatHappened -> a -> IO ()
report what problem = hPutStrLn stderr $ show what ++ show problem

-- | Sends message to all receivers on all nodes.
sendToAllReceivers :: [NodeEndpoint] -> NumberMessage -> Process ()
sendToAllReceivers nodesEndpoints message =
    mapM_ (\ep -> nsendRemote (makeNodeIdFrom ep) receiverLabel message) nodesEndpoints

receiverLabel :: String
receiverLabel = "receiver"
