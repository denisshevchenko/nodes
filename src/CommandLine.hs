module CommandLine (
    options
) where

import Types
import Options.Applicative

-- | Info about all supported command line options.
options :: ParserInfo Parameters
options = info ( helper <*> getParameters )
               ( fullDesc <> progDesc "Cloud Haskell nodes" )

-- | Parameters' description.
getParameters :: Parser Parameters
getParameters = Parameters
    <$> ( option auto $
          long "send-for"
       <> metavar "S"
       <> help "Sending period, in seconds" )
    <*> ( option auto $
          long "wait-for"
       <> metavar "S"
       <> help "Grace period, in seconds" )
    <*> ( optional $ option auto $
          long "with-seed"
       <> metavar "NUM"
       <> help "Seed value for RNG" )
    <*> ( strOption $
          long "nodes-conf"
       <> metavar "PATH"
       <> help "Path to config file with nodes' endpoints" )
