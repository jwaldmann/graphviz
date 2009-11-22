{- |
   Module      : Data.GraphViz.Testing.Properties
   Description : Properties for testing.
   Copyright   : (c) Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   Various properties that should hold true for the graphviz library.
-}
module Data.GraphViz.Testing.Properties where

import Data.GraphViz(prettyPrint')
import Data.GraphViz.Types(DotGraph, printDotGraph)
import Data.GraphViz.Types.Printing(PrintDot(..), printIt)
import Data.GraphViz.Types.Parsing(ParseDot(..), parseIt, preProcess)

import Test.QuickCheck

import Data.Maybe(isJust)
import Data.List(nub)
import Control.Monad(liftM, liftM2, liftM3, liftM4, guard)
import Data.Word(Word8)

-- -----------------------------------------------------------------------------
-- The properties to test for

-- | Checking that @parse . print == id@; that is, graphviz can parse
--   its own output.
prop_printParseID   :: (ParseDot a, PrintDot a, Eq a) => a -> Bool
prop_printParseID a = fst (tryParse a) == a

-- | A version of 'prop_printParse' specifically for lists; it ensures
--   that the list is not empty (as most list-based parsers fail on
--   empty lists).
prop_printParseListID    :: (ParseDot a, PrintDot a, Eq a) => [a] -> Property
prop_printParseListID as =  not (null as) ==> prop_printParseID as

-- | Pre-processing shouldn't change the output of printed Dot code.
--   This should work for all 'PrintDot' instances, but is more
--   specific to 'DotGraph' values.
prop_preProcessingID    :: (PrintDot a) => DotGraph a -> Bool
prop_preProcessingID dg = preProcess dotCode == dotCode
  where
    dotCode = printDotGraph dg

-- | This is a version of 'prop_printParseID' that tries to parse the
-- | pretty-printed output of 'prettyPrint'' rather than just 'printIt'.
prop_parsePrettyID    :: (PrintDot a) => DotGraph a -> Bool
prop_parsePrettyID dg = (fst . parseIt . prettyPrint') dg == dg

-- -----------------------------------------------------------------------------
-- Helper utility functions

-- | A utility function to use for debugging purposes for trying to
--   find how graphviz /is/ parsing something.  This is easier than
--   using @'parseIt' . 'printIt'@ directly, since it avoids having to
--   enter and explicit type signature.
tryParse :: (ParseDot a, PrintDot a) => a -> (a, String)
tryParse = parseIt . printIt
