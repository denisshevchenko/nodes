{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Types
import           Utils
import           CommandLine
import           EndpointParsers

import           Control.Monad                      ( forever, when )
import           Control.Distributed.Process
import           Control.Distributed.Process.Node
import           Network.Transport.TCP              ( createTransport, defaultTCPParameters )
import qualified System.Exit                        as SE
import           Options.Applicative                ( execParser )
import           Data.Attoparsec.Text               ( parseOnly )
import qualified Data.Text.IO                       as TIO
import           Data.List                          ( sort )

main :: IO ()
main = execParser options >>= \Parameters{..} ->
    parseOnly parseEndpoints <$> TIO.readFile nodesConfig >>= \case
        Left problem -> report CannotParseNodesEndpoints problem
        Right nodesEndpoints -> do
            when (sendPeriod <= 0)     $ SE.die "Sending period must be positive number."
            when (gracePeriod <= 0)    $ SE.die "Grace period must be positive number."
            when (null nodesEndpoints) $ SE.die "No nodes found, please check your config file."
            mapM_ (runNode seed) nodesEndpoints
            waitForSeconds $ sendPeriod - delayForDispatcher 
            sendStopMessageToAllNodes nodesEndpoints 
            putStrLn "SENT!"
            waitForSeconds 10            

-- | Creates transport point and new node, after that runs one process on it.
runNode :: Maybe Int -> NodeEndpoint -> IO ()
runNode seed (NodeEndpoint ip port) =
    createTransport ip (show port) defaultTCPParameters >>=
        either (report CannotCreateTransport)
               (\transport -> do
                    node <- newLocalNode transport initRemoteTable
                    _ <- forkProcess node $ do
                        senderPId <- spawnLocal $ runMessagesSender seed
                        allReceivedMessages <- runMessagesReceiver senderPId []
                        printOutResult allReceivedMessages
                    return ()
               )

runMessagesReceiver :: ProcessId -> [NumberMessage] -> Process [NumberMessage]
runMessagesReceiver senderPId receivedMessages = do
    -- Each node contains only one receiver, so it will be unique label.
    getSelfPid >>= register "receiver"
    
    message <- expect :: Process NumberMessage
    liftIO $ putStrLn "RECEIVED!"
    if thisWasLast message
        then kill senderPId "Sending period is over." >> return receivedMessages
        else runMessagesReceiver senderPId $ receivedMessages ++ [message]
  where
    -- Normally it's impossible to receive negative number in message 
    -- because of explicit range (0, 1].
    -- So if we receive negative number - it was stop signal, no more sending.
    thisWasLast (_, number) = number < 0

runMessagesSender :: Maybe Int -> Process ()
runMessagesSender seed = forever $ do
    number <- liftIO $ generateRandomNumber seed
    timeStamp <- liftIO $ getTimeStamp
    liftIO $ print $ (timeStamp, number)
    waitForSeconds 1

-- Forms final result and prints it out.
printOutResult :: [NumberMessage] -> Process ()
printOutResult [] = liftIO $ putStrLn "No messages received."
printOutResult allReceivedMessages = liftIO $ print result
  where
    result = prepareResult sortedBySendingTime
                           startIndex
                           initResult
    -- Timestamp is the first element of the pair, so it works.
    sortedBySendingTime = sort allReceivedMessages
    startIndex = 1
    initResult = ([], 0.0)

-- | Forms result tuple. Messages list is already sorted by sending time,
-- so we don't need timestamps anymore.
prepareResult :: [NumberMessage]
              -> Index
              -> Result
              -> Result
prepareResult messagesWithTimestamps i (numbers, numbersSum) =
    if i < length messagesWithTimestamps
        then prepareResult messagesWithTimestamps
                           (i + 1)
                           ( numbers ++ [ithNumber]
                           , numbersSum + (ithNumber * (fromIntegral i)) 
                           )
        else (numbers, numbersSum)
  where
    (_, ithNumber) = messagesWithTimestamps !! i

-- | Sending period is over, so we send stop message to all nodes.
sendStopMessageToAllNodes :: [NodeEndpoint] -> IO ()
sendStopMessageToAllNodes nodesEndpoints =
    createTransport "127.0.0.1" "10300" defaultTCPParameters >>=
        either (report CannotCreateTransport)
               (sendStopMessage)
  where
    sendStopMessage transport = do
        node <- newLocalNode transport initRemoteTable
        _ <- runProcess node $ 
            mapM_ (\ep -> nsendRemote (makeNodeIdFrom ep) "receiver" stopMessage) nodesEndpoints
        return ()

