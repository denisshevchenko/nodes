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
            when (sendPeriod <= 0)  $ SE.die "Sending period must be positive number."
            when (gracePeriod <= 0) $ SE.die "Grace period must be positive number."
            when (length nodesEndpoints < 3) $ SE.die "Need at least three nodes, please check your config file."
            -- First node is for stop message broadcasting.
            let specialNodeEndpoint = head nodesEndpoints
                workerNodesEndpoints = tail nodesEndpoints
            mapM_ (runNode seed workerNodesEndpoints) $ workerNodesEndpoints
            waitForSeconds $ sendPeriod - delayForDispatcher 
            sendStopMessageToAllNodes specialNodeEndpoint
                                      workerNodesEndpoints
                                      gracePeriod

-- | Creates transport point and new node, after that runs one process on it.
runNode :: Maybe Int
        -> [NodeEndpoint]
        -> NodeEndpoint
        -> IO ()
runNode seed workerNodesEndpoints (NodeEndpoint ip port) =
    createTransport ip (show port) defaultTCPParameters >>=
        either (report CannotCreateTransport)
               (\transport -> do
                    node <- newLocalNode transport initRemoteTable
                    _ <- forkProcess node $ do
                        -- Each node contains only one receiver, so it will be unique label.
                        getSelfPid >>= register receiverLabel
                        senderPId <- spawnLocal $ runMessagesSender seed workerNodesEndpoints
                        allReceivedMessages <- runMessagesReceiver senderPId []
                        printOutResult allReceivedMessages
                    return ()
               )

runMessagesReceiver :: ProcessId -> [NumberMessage] -> Process [NumberMessage]
runMessagesReceiver senderPId receivedMessages = do
    message <- expect :: Process NumberMessage
    if thisWasLast message
        then kill senderPId "Sending period is over." >> return receivedMessages
        else runMessagesReceiver senderPId $ receivedMessages ++ [message]
  where
    -- Normally it's impossible to receive negative number in message 
    -- because of explicit range (0, 1].
    -- So if we receive negative number - it was stop signal, no more sending.
    thisWasLast (_, number) = number < 0

runMessagesSender :: Maybe Int -> [NodeEndpoint] -> Process ()
runMessagesSender seed workerNodesEndpoints = forever $ do
    number <- liftIO $ generateRandomNumber seed
    timeStamp <- liftIO $ getTimeStamp
    sendToAllReceivers workerNodesEndpoints $ (timeStamp, number)
    waitForMilliSeconds 1

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
sendStopMessageToAllNodes :: NodeEndpoint
                          -> [NodeEndpoint]
                          -> Seconds
                          -> IO ()
sendStopMessageToAllNodes (NodeEndpoint ip port)
                          workerNodesEndpoints
                          gracePeriod =
    createTransport ip (show port) defaultTCPParameters >>=
        either (report CannotCreateTransport)
               (sendStopMessage)
  where
    sendStopMessage transport = do
        node <- newLocalNode transport initRemoteTable
        _ <- runProcess node $ do
            sendToAllReceivers workerNodesEndpoints stopMessage
            liftIO $ waitForSeconds gracePeriod
            -- At this point all worker nodes shouldn't exist
            -- (because we expect that they already finished their work and printed result out).
            -- If at least one worker still exists - kill the program.
            mapM_ checkReceiver workerNodesEndpoints
        return ()

    checkReceiver ep = do
        whereisRemoteAsync (makeNodeIdFrom ep) receiverLabel
        WhereIsReply _ maybeProcessId <- expect :: Process WhereIsReply
        case maybeProcessId of
            Nothing -> return () -- It's ok, receiver doesn't exist as we expect.
            _ -> liftIO $ SE.die "Some nodes still works, abort!"
