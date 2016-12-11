{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Types
import           CommandLine
import           EndpointParsers

import           Control.Concurrent                 ( threadDelay )
import           Control.Monad                      ( forever, when )
import           Control.Distributed.Process
import           Control.Distributed.Process.Node
import           Network.Transport.TCP              ( createTransport, defaultTCPParameters )
import           System.IO                          ( hPutStrLn, stderr )
import qualified System.Exit                        as SE
import           Options.Applicative
import           Data.Attoparsec.Text               ( parseOnly )
import qualified Data.Text.IO                       as TIO

main :: IO ()
main = execParser options >>= \Parameters{..} ->
    parseOnly parseEndpoints <$> TIO.readFile nodesConfig >>= \case
        Left problem -> report CannotParseNodesEndpoints problem
        Right nodesEndPoints -> do
            when (sendPeriod <= 0)     $ SE.die "Sending period must be positive number."
            when (gracePeriod <= 0)    $ SE.die "Grace period must be positive number."
            when (null nodesEndPoints) $ SE.die "No nodes found, please check your config file."
            mapM_ (runNode sendPeriod gracePeriod seed) nodesEndPoints

-- | Creates transport point and new node, after that runs one process on it.
runNode :: Seconds
        -> Seconds
        -> Maybe Int
        -> NodeEndpoint
        -> IO ()
runNode sendPeriod
        gracePeriod
        seed
        (NodeEndpoint ip port) =
    createTransport ip (show port) defaultTCPParameters >>=
        either (report CannotCreateTransport)
               (\transport -> newLocalNode transport initRemoteTable >>=
                                  flip runProcess (doWork sendPeriod gracePeriod seed))

-- | Reports about some problem.
report :: Show a => WhatHappened -> a -> IO ()
report what problem = hPutStrLn stderr $ show what ++ show problem

doWork :: Seconds
       -> Seconds
       -> Maybe Int
       -> Process ()
doWork _ _ _ = do
    -- Spawn another worker on the local node
    echoPid <- spawnLocal $ forever $ do
      -- Test our matches in order against each message in the queue
      receiveWait [match logMessage, match replyBack]

    -- The `say` function sends a message to a process registered as "logger".
    -- By default, this process simply loops through its mailbox and sends
    -- any received log message strings it finds to stderr.

    say "send some messages!"
    send echoPid "hello"
    self <- getSelfPid
    send echoPid (self, "hello")

    -- `expectTimeout` waits for a message or times out after "delay"
    m <- expectTimeout 1000000
    case m of
      -- Die immediately - throws a ProcessExitException with the given reason.
      Nothing  -> die "nothing came back!"
      Just s -> say $ "got " ++ s ++ " back!"
      
    -- Without the following delay, the process sometimes exits before the messages are exchanged.
    liftIO $ threadDelay 2000000

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

