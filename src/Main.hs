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
import qualified Control.Distributed.Backend.P2P    as P2P
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
        Right nodesEndPoints -> do
            when (sendPeriod <= 0)     $ SE.die "Sending period must be positive number."
            when (gracePeriod <= 0)    $ SE.die "Grace period must be positive number."
            when (null nodesEndPoints) $ SE.die "No nodes found, please check your config file."
            mapM_ (runNode seed) nodesEndPoints
            waitForSeconds $ sendPeriod - delayForDispatcher 
            sendStopMessageToAllNodes nodesEndPoints 
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
    nodeIAmRunningOn <- getSelfNode
    -- "IAMHERE: nid://127.0.0.1:10200:0"
    -- Each node contains only one receiver, so it will be unique label.
    getSelfPid >>= register (show nodeIAmRunningOn)
    
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

sendStopMessageToAllNodes :: [NodeEndpoint] -> IO ()
sendStopMessageToAllNodes nodesEndPoints =
    P2P.bootstrap "127.0.0.1"
                  "10210"
                  nodesIds
                  initRemoteTable $ do
        waitForSeconds delayForDispatcher -- We give dispatcher a second to discover other nodes
        P2P.nsendPeers "nid://127.0.0.1:10201:0" stopMessage
  where
      nodesIds = [makeNodeIdFrom node | node <- nodesEndPoints]

{-
нужно:

    зарегистрироватьпроцесс

\2. сформировать NodeId
\3. вызывать whereIsRemoteAsynyc label
вообще где-то это уже было сделано, т.к. вопрос частый
distributed-process-p2p вроде
но я смотрю и не до конца уверен






в целом решение наверное такое:
в общем 2 варианта, №1. регистрируешь броад-каст процесс на ноде, который:

(sendChan, recvChan) <- mkChan
fix $ \loop st -> do
receiveTimeout
   [ match $ \(Register pid) -> monitor pid >> send pid recvChan >> loop (Set.insert pid st) 
   , match $ \(Unregister pid) -> unmonitor pid >> loop (Set.delete pid st)
   , match $ \(ProcessMonitorNotification _ _ _) -> loop (Set.delete pid st)
   , matchAny $ \msg -> for_ st (\p -> uforward p msg) >> loop st 
   ]

что-то такое
Alexander Vershilov
@qnikst
20:46
+-
плюсы - вроде просто
минусы - single point of failure, ноды должны знать где находится канал
вариант №2, примерно как 1, но получше:

    на всех известных нодах контролируем не всех подписантов, а все другие ноды и мониторим их, и всех локальных подписантов
    тогда если приходит сообщение - то делаем resend на все другие ноды но label + на все локальные процессы
    добавление новых нод или через агента, или руками

общий смысл примерно тот же
вообще от задачи зависит
Denis Shevchenko
@denisshevchenko
20:48

а нет ли чего-нибудь такого?

justSendThisDamnedMessageToAllFolks message

:smiley: Шучу.
Alexander Vershilov
@qnikst
20:49
25$ час, и я напишу :]
на самом деле и так могу, но не знаю когда время будет
ну и можно пакеты в платформе посмотреть там многого г-на навалом, может и это есть
но там писал Тим он писал зачастую криво, но как первое приближение пойдет
Denis Shevchenko
@denisshevchenko
20:50
нет, так нечестно, я сам должен разобраться. Это же моё тестовое задание.
Alexander Vershilov
@qnikst
20:50
тут вообще слишком много вопросов, про reliability, про то, как поступать если ноды могут временно дохнуть, как новые добавлять, я даже не знаю как сделать идеальное решение
тебе его оплачивают?

-}

