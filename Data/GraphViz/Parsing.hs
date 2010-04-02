{- |
   Module      : Data.GraphViz.Parsing
   Description : Helper functions for Parsing.
   Copyright   : (c) Matthew Sackman, Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   This module defines simple helper functions for use with
   "Text.ParserCombinators.Poly.Lazy".

   Note that the 'ParseDot' instances for 'Bool', etc. match those
   specified for use with Graphviz (e.g. non-zero integers are
   equivalent to 'True').

   You should not be using this module; rather, it is here for
   informative/documentative reasons.  If you want to parse a
   @'Data.GraphViz.Types.DotRepr'@, you should use
   @'Data.GraphViz.Types.parseDotGraph'@ rather than its 'ParseDot'
   instance.
-}
module Data.GraphViz.Parsing
    ( -- * Re-exporting pertinent parts of Polyparse.
      module Text.ParserCombinators.Poly.Lazy
      -- * The ParseDot class.
    , Parse
    , ParseDot(..)
    , parseIt
    , parseIt'
    , runParser'
      -- * Convenience parsing combinators.
    , bracket
    , onlyBool
    , quotelessString
    , stringBlock
    , numString
    , isNumString
    , isIntString
    , quotedString
    , parseEscaped
    , parseAndSpace
    , string
    , strings
    , hasString
    , character
    , parseStrictFloat
    , noneOf
    , whitespace
    , whitespace'
    , allWhitespace
    , allWhitespace'
    , wrapWhitespace
    , optionalQuotedString
    , optionalQuoted
    , quotedParse
    , orQuote
    , quoteChar
    , newline
    , newline'
    , parseComma
    , tryParseList
    , tryParseList'
    , consumeLine
    , parseField
    , parseFields
    , parseFieldBool
    , parseFieldsBool
    , parseFieldDef
    , parseFieldsDef
    , commaSep
    , commaSepUnqt
    , commaSep'
    , stringRep
    , stringReps
    , parseAngled
    , parseBraced
    ) where

import Data.GraphViz.Util

import Text.ParserCombinators.Poly.Lazy hiding (bracket)
import Data.Char( digitToInt
                , isDigit
                , isSpace
                , toLower
                )
import Data.Maybe(isJust, fromMaybe, isNothing)
import Data.Ratio((%))
import qualified Data.Set as Set
import Data.Word(Word8, Word16)
import Control.Monad(liftM, when)

-- -----------------------------------------------------------------------------
-- Based off code from Text.Parse in the polyparse library

-- | A @ReadS@-like type alias.
type Parse a = Parser Char a

-- | A variant of 'runParser' where it is assumed that the provided
--   parsing function consumes all of the 'String' input (with the
--   exception of whitespace at the end).
runParser'   :: Parse a -> String -> a
runParser' p = fst . runParser p'
  where
    p' = p `discard` (allWhitespace' >> eof)

class ParseDot a where
    parseUnqt :: Parse a

    parse :: Parse a
    parse = optionalQuoted parseUnqt

    parseUnqtList :: Parse [a]
    parseUnqtList = bracketSep (parseAndSpace $ character '[')
                               (parseAndSpace $ parseComma)
                               (parseAndSpace $ character ']')
                               (parseAndSpace parse)

    parseList :: Parse [a]
    parseList = quotedParse parseUnqtList

-- | Parse the required value, returning also the rest of the input
--   'String' that hasn't been parsed (for debugging purposes).
parseIt :: (ParseDot a) => String -> (a, String)
parseIt = runParser parse

-- | Parse the required value with the assumption that it will parse
--   all of the input 'String'.
parseIt' :: (ParseDot a) => String -> a
parseIt' = runParser' parse

instance ParseDot Int where
    parseUnqt = parseInt'

instance ParseDot Word8 where
    parseUnqt = parseInt

instance ParseDot Word16 where
    parseUnqt = parseInt

instance ParseDot Double where
    parseUnqt = parseFloat'

    parseUnqtList = sepBy1 parseUnqt (character ':')

instance ParseDot Bool where
    parseUnqt = onlyBool
                `onFail`
                liftM (zero /=) parseInt'
        where
          zero :: Int
          zero = 0

-- | Use this when you do not want numbers to be treated as 'Bool' values.
onlyBool :: Parse Bool
onlyBool = oneOf [ stringRep True "true"
                 , stringRep False "false"
                 ]

instance ParseDot Char where
    -- Can't be a quote character.
    parseUnqt = satisfy ((/=) quoteChar)

    parse = satisfy restIDString
            `onFail`
            quotedParse parseUnqt

    -- Too many problems with using this within other parsers where
    -- using numString or stringBlock will cause a parse failure.  As
    -- such, this will successfully parse all un-quoted Strings.
    parseUnqtList = quotedString

    parseList = quotelessString
                `onFail`
                -- This will also take care of quoted versions of
                -- above.
                quotedParse quotedString

instance (ParseDot a) => ParseDot [a] where
    parseUnqt = parseUnqtList

    parse = parseList

-- | Parse a 'String' that doesn't need to be quoted.
quotelessString :: Parse String
quotelessString = numString `onFail` stringBlock

numString :: Parse String
numString = liftM show parseStrictFloat
            `onFail`
            liftM show parseInt'

stringBlock :: Parse String
stringBlock = do frst <- satisfy frstIDString
                 rest <- many (satisfy restIDString)
                 return $ frst : rest

-- | Used when quotes are explicitly required;
quotedString :: Parse String
quotedString = parseEscaped True []

parseSigned :: Real a => Parse a -> Parse a
parseSigned p = (character '-' >> liftM negate p)
                `onFail`
                p

parseInt :: (Integral a) => Parse a
parseInt = do cs <- many1 (satisfy isDigit)
              return (foldl1 (\n d-> n*radix+d)
                                   (map (fromIntegral . digitToInt) cs))
           `adjustErr` (++ "\nexpected one or more digits")
    where
      radix = 10

parseInt' :: Parse Int
parseInt' = parseSigned parseInt

-- | Parse a floating point number that actually contains decimals.
parseStrictFloat :: Parse Double
parseStrictFloat = parseSigned parseFloat

parseFloat :: (RealFrac a) => Parse a
parseFloat = do ds   <- many (satisfy isDigit)
                frac <- optional
                        $ do character '.'
                             many1 (satisfy isDigit)
                               `adjustErr` (++ "\nexpected digit after .")
                when (isNothing frac && null ds)
                  (fail "No actual digits in floating point number!")
                expn  <- optional parseExp
                when (isNothing frac && isNothing expn)
                  (fail "This is an integer, not a floating point number!")
                let frac' = fromMaybe "" frac
                    expn' = fromMaybe 0 expn
                ( return . fromRational . (* (10^^(expn' - length frac')))
                  . (%1) . runParser' parseInt) (ds++frac')
             `onFail`
             fail "Expected a floating point number"
    where parseExp = do character 'e'
                        ((character '+' >> parseInt)
                         `onFail`
                         parseInt')

parseFloat' :: Parse Double
parseFloat' = parseSigned ( parseFloat
                            `onFail`
                            liftM fI parseInt
                          )
    where
      fI :: Integer -> Double
      fI = fromIntegral

-- -----------------------------------------------------------------------------

-- | Parse a bracketed item, discarding the brackets.
--
--   The definition of @bracket@ defined in Polyparse uses
--   'adjustErrBad' and thus doesn't allow backtracking and trying the
--   next possible parser.  This is a version of @bracket@ that does.
bracket               :: PolyParse p => p bra -> p ket -> p a -> p a
bracket open close pa = open >> pa `discard` close

parseAndSpace   :: Parse a -> Parse a
parseAndSpace p = p `discard` whitespace'

string :: String -> Parse String
string = mapM character

stringRep   :: a -> String -> Parse a
stringRep v = stringReps v . return

stringReps      :: a -> [String] -> Parse a
stringReps v ss = oneOf (map string ss) >> return v

strings :: [String] -> Parse String
strings = oneOf . map string

hasString :: String -> Parse Bool
hasString = liftM isJust . optional . string

character   :: Char -> Parse Char
character c = satisfy parseC
              `adjustErr`
              (++ "\nnot the expected char: " ++ [c])
  where
    parseC c' = c' == c || toLower c == c'

noneOf :: (Eq a) => [a] -> Parser a a
noneOf t = satisfy (\x -> all (/= x) t)

whitespace :: Parse String
whitespace = many1 (satisfy isSpace)

whitespace' :: Parse String
whitespace' = many (satisfy isSpace)

allWhitespace :: Parse ()
allWhitespace = (whitespace `onFail` newline) >> allWhitespace'

allWhitespace' :: Parse ()
allWhitespace' = newline' `discard` whitespace'

-- | Parse and discard optional whitespace.
wrapWhitespace :: Parse a -> Parse a
wrapWhitespace = bracket allWhitespace' allWhitespace'

optionalQuotedString :: String -> Parse String
optionalQuotedString = optionalQuoted . string

optionalQuoted   :: Parse a -> Parse a
optionalQuoted p = quotedParse p
                   `onFail`
                   p

quotedParse :: Parse a -> Parse a
quotedParse = bracket parseQuote parseQuote

parseQuote :: Parse Char
parseQuote = character quoteChar

orQuote   :: Parse Char -> Parse Char
orQuote p = stringRep quoteChar "\\\""
            `onFail`
            p

quoteChar :: Char
quoteChar = '"'

-- | Parse a 'String' where the provided 'Char's (as well as @"@) are
--   escaped.  Note: does not parse surrounding quotes, and assumes
--   that @\\@ is not an escaped character.  The 'Bool' value
--   indicates whether empty 'String's are allowed or not.
parseEscaped         :: Bool -> [Char] -> Parse String
parseEscaped empt cs = lots $ qPrs `onFail` oth
  where
    lots = if empt then many else many1
    cs' = quoteChar : cs
    csSet = Set.fromList cs'
    slash = '\\'
    -- Have to allow standard slashes
    qPrs = do character slash
              mE <- optional $ oneOf (map character cs')
              return $ fromMaybe slash mE
    oth = satisfy (`Set.notMember` csSet)

newline :: Parse String
newline = oneOf $ map string ["\r\n", "\n", "\r"]

-- | Consume all whitespace and newlines until a line with
--   non-whitespace is reached.  The whitespace on that line is
--   not consumed.
newline' :: Parse ()
newline' = many (whitespace' >> newline) >> return ()

-- | Parses and returns all characters up till the end of the line,
--   but does not touch the newline characters.
consumeLine :: Parse String
consumeLine = many (noneOf ['\n','\r'])

parseField     :: (ParseDot a) => String -> Parse a
parseField fld = do string fld
                    whitespace'
                    character '='
                    whitespace'
                    parse

parseFields :: (ParseDot a) => [String] -> Parse a
parseFields = oneOf . map parseField

parseFieldBool :: String -> Parse Bool
parseFieldBool = parseFieldDef True

parseFieldsBool :: [String] -> Parse Bool
parseFieldsBool = oneOf . map parseFieldBool

-- | For 'Bool'-like data structures where the presence of the field
--   name without a value implies a default value.
parseFieldDef       :: (ParseDot a) => a -> String -> Parse a
parseFieldDef d fld = parseField fld
                      `onFail`
                      stringRep d fld

parseFieldsDef   :: (ParseDot a) => a -> [String] -> Parse a
parseFieldsDef d = oneOf . map (parseFieldDef d)

commaSep :: (ParseDot a, ParseDot b) => Parse (a, b)
commaSep = commaSep' parse parse

commaSepUnqt :: (ParseDot a, ParseDot b) => Parse (a, b)
commaSepUnqt = commaSep' parseUnqt parseUnqt

commaSep'       :: Parse a -> Parse b -> Parse (a,b)
commaSep' pa pb = do a <- pa
                     whitespace'
                     parseComma
                     whitespace'
                     b <- pb
                     return (a,b)

parseComma :: Parse Char
parseComma = character ','

tryParseList :: (ParseDot a) => Parse [a]
tryParseList = tryParseList' parse

tryParseList' :: Parse [a] -> Parse [a]
tryParseList' = liftM (fromMaybe []) . optional

parseAngled :: Parse a -> Parse a
parseAngled = bracket (character '<') (character '>')

parseBraced :: Parse a -> Parse a
parseBraced = bracket (character '{') (character '}')
