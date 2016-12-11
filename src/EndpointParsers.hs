module EndpointParsers (
    parseEndpoints
) where

import Types

import Data.Attoparsec.Text

-- | Parse list of nodes' endpoints from the config file.
parseEndpoints :: Parser NodesEndpoints
parseEndpoints = many' $ parseEndpoint <* endOfLine

-- | Parse one endpoint. Assumed format IP:PORT, one endpoint per line.
parseEndpoint :: Parser NodeEndpoint
parseEndpoint = do
    ip <- anyChar `manyTill` char ':'
    port <- decimal
    return $ NodeEndpoint ip port
