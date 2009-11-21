{- |
   Module      : Data.GraphViz.Types.Internal
   Description : Internal functions
   Copyright   : (c) Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   This module defines internal functions.
-}
module Data.GraphViz.Types.Internal where

import Data.Char( isAsciiUpper
                , isAsciiLower
                , isDigit
                , toLower
                )

import qualified Data.Set as Set
import Data.Set(Set)
import Control.Monad(liftM2)

isIDString        :: String -> Bool
isIDString []     = True
isIDString (f:os) = frstIDString f
                    && all restIDString os

-- | First character of a non-quoted 'String' must match this.
frstIDString   :: Char -> Bool
frstIDString c = any ($c) [ isAsciiUpper
                          , isAsciiLower
                          , (==) '_'
                          , liftM2 (&&) (>= '\200') (<= '\377')
                          ]

-- | The rest of a non-quoted 'String' must match this.
restIDString   :: Char -> Bool
restIDString c = frstIDString c || isDigit c

-- | Determine if this String represents a number.
isNumString     :: String -> Bool
isNumString ""  = False
isNumString "-" = False
isNumString str = case str of
                    ('-':str') -> go str'
                    _          -> go str
    where
      go [] = False
      go cs = case dropWhile isDigit cs of
                []       -> True
                ('.':ds) -> not (null ds) && all isDigit ds
                _        -> False

-- | Determine if this String represents an integer.
isIntString     :: String -> Maybe Int
isIntString str = if isNum
                  then Just (read str)
                  else Nothing
  where
    isNum = case str of
              ['-']     -> False
              ('-':num) -> isNum' num
              _         -> isNum' str
    isNum' = all isDigit

-- | Graphviz requires double quotes to be explicitly escaped.
escapeQuotes           :: String -> String
escapeQuotes []        = []
escapeQuotes ('"':str) = '\\':'"': escapeQuotes str
escapeQuotes (c:str)   = c : escapeQuotes str

-- | Remove explicit escaping of double quotes.
descapeQuotes                :: String -> String
descapeQuotes []             = []
descapeQuotes ('\\':'"':str) = '"' : descapeQuotes str
descapeQuotes (c:str)        = c : descapeQuotes str

isKeyword :: String -> Bool
isKeyword = flip Set.member keywords . map toLower

-- | The following are Dot keywords and are not valid as labels, etc. unquoted.
keywords :: Set String
keywords = Set.fromList [ "node"
                        , "edge"
                        , "graph"
                        , "digraph"
                        , "subgraph"
                        , "strict"
                        ]

-- | Fold over 'Bool's.
bool       :: a -> a -> Bool -> a
bool t f b = if b
             then t
             else f
