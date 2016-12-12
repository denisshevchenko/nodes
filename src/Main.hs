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
import           Control.Monad.IO.Class             ( MonadIO ) 
import           Network.Transport.TCP              ( createTransport, defaultTCPParameters )
import           System.IO                          ( hPutStrLn, stderr )
import qualified System.Exit                        as SE
import           System.Random
import           Options.Applicative
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
            waitForSeconds sendPeriod
            -- Ok, now we have to send 'stop' message to all nodes...

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
    message <- expect :: Process NumberMessage
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
    liftIO $ print number

printOutResult :: [NumberMessage] -> Process ()
printOutResult [] = liftIO $ putStrLn "No message received."
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

generateRandomNumber :: Maybe Int -> IO Double
generateRandomNumber maybeSeed = case maybeSeed of
    Just seed -> return $ let (n, _) = randomR range $ mkStdGen seed in n
    Nothing   -> randomRIO range
  where
    range = (0.00000000000000001, 1.0)

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg


-- | Stops current thread for N seconds.
waitForSeconds :: MonadIO m => Int -> m ()
waitForSeconds s = liftIO . threadDelay $ s * 1000000

-- | Stops current thread for N milliseconds.
waitForMilliSeconds :: MonadIO m => Int -> m ()
waitForMilliSeconds s = liftIO . threadDelay $ s * 1000

-- | Reports about some problem.
report :: Show a => WhatHappened -> a -> IO ()
report what problem = hPutStrLn stderr $ show what ++ show problem







{-
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
    -}












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

