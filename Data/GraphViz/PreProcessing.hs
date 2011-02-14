{- |
   Module      : Data.GraphViz.PreProcessing
   Description : Pre-process imported Dot code.
   Copyright   : (c) Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   "Real life" Dot code contains various items that are not directly
   parseable by this library.  This module defines the 'preProcess'
   function to remove these components, which include:

     * Comments (both @\/* ... *\/@ style and @\/\/ ... @ style);

     * Pre-processor lines (lines starting with a @#@);

     * Split lines (by inserting a @\\@ the rest of that \"line\" is
       continued on the next line).

     * 'String's concatenated together using @\"...\" + \"...\"@;
       these are concatenated into one big 'String'.
-}
module Data.GraphViz.PreProcessing(preProcess) where

import Data.GraphViz.Parsing

import qualified Data.Text.Lazy as T
import Data.Text.Lazy(Text)
import qualified Data.Text.Lazy.Builder as B
import Data.Text.Lazy.Builder(Builder)
import Data.Monoid(Monoid(..), mconcat)
import Control.Monad(liftM)

-- -----------------------------------------------------------------------------
-- Filtering out unwanted Dot items such as comments

-- | Remove unparseable features of Dot, such as comments and
--   multi-line strings (which are converted to single-line strings).
preProcess :: Text -> Text
preProcess t = case fst $ runParser parseOutUnwanted t of
                 (Right r) -> B.toLazyText r
                 (Left l)  -> error $ show l
             -- snd should be null

-- | Parse out comments and make quoted strings spread over multiple
--   lines only over a single line.  Should parse the /entire/ input
--   'Text'.
parseOutUnwanted :: Parse Builder
parseOutUnwanted = liftM mconcat (many getNext)
    where
      getNext = parseOK
                `onFail`
                parseConcatStrings
                `onFail`
                parseHTML
                `onFail`
                parseUnwanted
                `onFail`
                liftM B.singleton next
      parseOK = liftM B.fromLazyText
                $ many1Satisfy (`notElem` ['\n', '\r', '\\', '/', '"'])

-- | Parses an unwanted part of the Dot code (comments and
--   pre-processor lines; also un-splits lines).
parseUnwanted :: (Monoid m) => Parse m
parseUnwanted = oneOf [ parseLineComment
                      , parseMultiLineComment
                      , parsePreProcessor
                      , parseSplitLine
                      ]

-- | Remove pre-processor lines (that is, those that start with a
--   @#@).  Will consume the newline from the beginning of the
--   previous line, but will leave the one from the pre-processor line
--   there (so in the end it just removes the line).
parsePreProcessor :: (Monoid m) => Parse m
parsePreProcessor = do newline
                       character '#'
                       consumeLine
                       return mempty

-- | Parse @//@-style comments.
parseLineComment :: (Monoid m) => Parse m
parseLineComment = do string "//"
                      -- Note: do /not/ consume the newlines, as they're
                      -- needed in case the next line is a pre-processor
                      -- line.
                      consumeLine
                      return mempty

-- | Parse @/* ... */@-style comments.
parseMultiLineComment :: (Monoid m) => Parse m
parseMultiLineComment = bracket start end (many inner)
                        >> return mempty
    where
      start = string "/*"
      end = string "*/"
      inner = (many1 (satisfy ('*' /=)) >> return ())
              `onFail`
              do character '*'
                 satisfy ('/' /=)
                 inner

parseConcatStrings :: Parse Builder
parseConcatStrings = liftM (wrapQuotes . mconcat)
                     $ sepBy1 parseString parseConcat
  where
    qParse = bracket (character '"') (commit $ character '"')
    parseString = qParse (liftM mconcat $ many parseInner)
    parseInner = (string "\\\"" >> return (B.fromLazyText $ T.pack "\\\""))
                 `onFail`
                 parseSplitLine -- in case there's a split mid-quote
                 `onFail`
                 liftM B.singleton (satisfy (quoteChar /=))
    parseConcat = parseSep >> character '+' >> parseSep
    parseSep = many $ allWhitespace `onFail` parseUnwanted
    wrapQuotes str = qc `mappend` str `mappend` qc
    qc = B.singleton '"'

-- | Lines can be split with a @\\@ at the end of the line.
parseSplitLine :: (Monoid m) => Parse m
parseSplitLine = character '\\' >> newline >> return mempty

parseHTML :: Parse Builder
parseHTML = liftM (addAngled . mconcat)
            . parseAngled $ many inner
  where
    inner = parseHTML
            `onFail`
            (liftM B.fromLazyText $ many1Satisfy (\c -> c /= open && c /= close))
    addAngled str = B.singleton open `mappend` str `mappend` B.singleton close
    open = '<'
    close = '>'
