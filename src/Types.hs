module Types where

type Seconds = Int

-- | Parameters extracted from the command line.
data Parameters = Parameters
    { sendPeriod  :: Seconds
    , gracePeriod :: Seconds
    , seed        :: Maybe Int
    , nodesConfig :: FilePath
    }

type IP   = String
type Port = Int

-- | Represents endpoint for one node.
data NodeEndpoint = NodeEndpoint IP Port
                  deriving Show

type NodesEndpoints = [NodeEndpoint]

data WhatHappened = CannotCreateTransport
                  | CannotParseNodesEndpoints
                  deriving Show

-- Types for messages.
type Number         = Double
type NumbersSum     = Double
type Index          = Int
type SendingTime    = Double
type NumberMessage  = (SendingTime, Number)
type Result         = ([Number], NumbersSum)
