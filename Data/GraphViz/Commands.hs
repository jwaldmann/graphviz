{- |
   Module      : Data.GraphViz.Commands
   Description : Functions to run GraphViz commands.
   Copyright   : (c) Matthew Sackman, Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   This module defines functions to call the various GraphViz
   commands.  It is based upon code originally written for version 0.5
   of /Graphalyze/:
     <http://hackage.haskell.org/cgi-bin/hackage-scripts/package/Graphalyze-0.5>

   Whilst various output formats are supported (see 'GraphvizOutput'
   for a complete list), it is not yet possible to choose a desired
   renderer and formatter.
-}

module Data.GraphViz.Commands
    ( GraphvizCommand(..)
    , dirCommand
    , undirCommand
    , commandFor
    , GraphvizOutput(..)
    , runGraphviz
    , runGraphvizCommand
    , addExtension
    , graphvizWithHandle
    )
    where

import Data.GraphViz.Types
import Data.GraphViz.Types.Printing
-- This is here just for Haddock linking purposes.
import Data.GraphViz.Attributes(Attribute(Z))

import Data.Maybe(isJust)
import System.IO( Handle, IOMode(WriteMode), hClose, hPutStrLn
                , hGetContents, hPutStr, stderr, openFile)
import System.Exit(ExitCode(ExitSuccess))
import System.Process(runInteractiveCommand, waitForProcess)
import Data.Array.IO(newArray_, hGetArray, hPutArray)
import Control.Concurrent(forkIO)
import Control.Exception.Extensible(SomeException(..), tryJust)
import Control.Monad(liftM,unless)
import System.FilePath(FilePath, (<.>))

-- | The available GraphViz commands.  The following directions are
--   based upon those in the GraphViz man page (available online at
--   <http://graphviz.org/pdf/dot.1.pdf>, or if installed on your
--   system @man graphviz@).  Note that any command can be used on
--   both directed and undirected graphs.
data GraphvizCommand = Dot   -- ^ For hierachical graphs (ideal for
                             --   directed graphs).
                     | Neato -- ^ For symmetric layouts of graphs
                             --   (ideal for undirected graphs).
                     | TwoPi -- ^ For radial layout of graphs.
                     | Circo -- ^ For circular layout of graphs.
                     | Fdp   -- ^ For symmetric layout of graphs.
                       deriving (Eq, Ord, Show, Read)

showCmd        :: GraphvizCommand -> String
showCmd Dot    = "dot"
showCmd Neato  = "neato"
showCmd TwoPi  = "twopi"
showCmd Circo  = "circo"
showCmd Fdp    = "fdp"

-- | The default command for directed graphs.
dirCommand :: GraphvizCommand
dirCommand = Dot

-- | The default command for undirected graphs.
undirCommand :: GraphvizCommand
undirCommand = Neato

-- | The appropriate (default) GraphViz command for the given graph.
commandFor    :: DotGraph a -> GraphvizCommand
commandFor dg = if directedGraph dg
                then dirCommand
                else undirCommand

-- | The possible GraphViz output formats.  Note that which formats
--   are available on your system depend on how it was built (e.g. if
--   it wasn't built with PNG support, then using 'Png' will probably
--   result in an error.  To determine which formats your install of
--   GraphViz supports, run @dot -T?@.  For more information, see:
--     <http://graphviz.org/doc/info/output.html>
--
--   Note that for 'Gtk' and 'Xlib', these immediately draw the result
--   onto the appropriate canvas (i.e. creates a window with the
--   image) and as such produce no files.  To be able to use these
--   output types with the conversion functions here, you may wish to
--   use a temporary file or \/dev\/null to store the \"output\" of
--   the 'GraphvizCommand'.
data GraphvizOutput = Bmp       -- ^ Windows Bitmap Format.
                    | Canon     -- ^ Pretty-printed Dot output with no
                                --   layout performed.
                    | DotOutput -- ^ Reproduces the input along with
                                --   layout information.
                    | XDot      -- ^ As with 'DotOutput', but provides
                                --   even more information on how the
                                --   graph is drawn.
                    | Eps       -- ^ Encapsulated PostScript.
                    | Fig       -- ^ FIG graphics language.
                    | Gd        -- ^ Internal GD library format.
                    | Gd2       -- ^ Compressed version of 'Gd'.
                    | Gif       -- ^ Graphics Interchange Format.
                    | Gtk       -- ^ GTK canvas.
                    | Ico       -- ^ Icon image file format.
                    | Imap      -- ^ Server-side imagemap.
                    | Cmapx     -- ^ Client-side imagemap.
                    | ImapNP    -- ^ As for 'Imap', except only
                                --   rectangles are used as active
                                --   areas.
                    | CmapxNP   -- ^ As for 'Cmapx', except only
                                --   rectangles are used as active
                                --   areas.
                    | Jpeg      -- ^ The JPEG image format.
                    | Pdf       -- ^ Portable Document Format.
                    | Plain     -- ^ Simple text format.
                    | PlainExt  -- ^ As for 'Plain', but provides port
                                --   names on head and tail nodes when
                                --   applicable.
                    | Png       -- ^ Portable Network Graphvics format.
                    | Ps        -- ^ PostScript.
                    | Ps2       -- ^ PostScript for PDF.
                    | Svg       -- ^ Scalable Vector Graphics format.
                    | SvgZ      -- ^ Compressed SVG format.
                    | Tiff      -- ^ Tagged Image File Format.
                    | Vml       -- ^ Vector Markup Language; 'Svg' is
                                --   usually preferred.
                    | VmlZ      -- ^ Compressed VML format; 'SvgZ' is
                                --   usually preferred.
                    | Vrml      -- ^ Virtual Reality Modeling Language
                                --   format; requires nodes to have a
                                --   'Z' attribute.
                    | WBmp      -- ^ Wireless BitMap format;
                                --   monochrome format usually used
                                --   for mobile computing devices.
                    | Xlib      -- ^ Xlib canvas.
                      deriving (Eq, Ord, Show, Read)

-- | The format GraphViz expects the 'GraphvizOutput' value to be
--   printed as when used with the @-T@ argument.
outputCall           :: GraphvizOutput -> String
outputCall Bmp       = "bmp"
outputCall Canon     = "canon"
outputCall DotOutput = "dot"
outputCall XDot      = "xdot"
outputCall Eps       = "eps"
outputCall Fig       = "fig"
outputCall Gd        = "gd"
outputCall Gd2       = "gd2"
outputCall Gif       = "gif"
outputCall Gtk       = "gtk_canvas"
outputCall Ico       = "ico"
outputCall Imap      = "imap"
outputCall Cmapx     = "cmapx"
outputCall ImapNP    = "imap_np"
outputCall CmapxNP   = "cmapx_np"
outputCall Jpeg      = "jpeg"
outputCall Pdf       = "pdf"
outputCall Plain     = "plain"
outputCall PlainExt  = "plain-ext"
outputCall Png       = "png"
outputCall Ps        = "ps"
outputCall Ps2       = "ps2"
outputCall Svg       = "svg"
outputCall SvgZ      = "svgz"
outputCall Tiff      = "tiff"
outputCall Vml       = "vml"
outputCall VmlZ      = "vmlz"
outputCall Vrml      = "vrml"
outputCall WBmp      = "wbmp"
outputCall Xlib      = "xlib"

-- | A default file extension for each 'GraphvizOutput'.  Note that
--   for cases such as 'Gtk' where there is no actual file produced,
--   the value returned isn't necessarily sensible.
defaultExtension           :: GraphvizOutput -> String
defaultExtension Bmp       = "bmp"
defaultExtension Canon     = "dot"
defaultExtension DotOutput = "dot"
defaultExtension XDot      = "dot"
defaultExtension Eps       = "eps"
defaultExtension Fig       = "fig"
defaultExtension Gd        = "gd"
defaultExtension Gd2       = "gd2"
defaultExtension Gif       = "gif"
defaultExtension Gtk       = "gtk_canvas"
defaultExtension Ico       = "ico"
defaultExtension Imap      = "map"
defaultExtension Cmapx     = "map"
defaultExtension ImapNP    = "map"
defaultExtension CmapxNP   = "map"
defaultExtension Jpeg      = "jpg"
defaultExtension Pdf       = "pdf"
defaultExtension Plain     = "txt"
defaultExtension PlainExt  = "txt"
defaultExtension Png       = "png"
defaultExtension Ps        = "ps"
defaultExtension Ps2       = "ps"
defaultExtension Svg       = "svg"
defaultExtension SvgZ      = "svgz"
defaultExtension Tiff      = "tif"
defaultExtension Vml       = "vml"
defaultExtension VmlZ      = "vmlz"
defaultExtension Vrml      = "vrml"
defaultExtension WBmp      = "wbmp"
defaultExtension Xlib      = "xlib_canvas"

-- | Run the recommended Graphviz command on this graph, saving the result
--   to the file provided (note: file extensions are /not/ checked).
--   Returns @True@ if successful, @False@ otherwise.
runGraphviz    :: (PrintDot n) => DotGraph n -> GraphvizOutput -> FilePath
                  -> IO Bool
runGraphviz gr = runGraphvizCommand (commandFor gr) gr

-- | Run the chosen Graphviz command on this graph, saving the result
--   to the file provided (note: file extensions are /not/ checked).
--   Returns @True@ if successful, @False@ otherwise.
runGraphvizCommand :: (PrintDot n) => GraphvizCommand -> DotGraph n
                      -> GraphvizOutput -> FilePath -> IO Bool
runGraphvizCommand cmd gr t fp
    = do pipe <- tryJust (\(SomeException _) -> return ())
                 $ openFile fp WriteMode
         case pipe of
           (Left _)  -> return False
           (Right f) -> liftM isJust $ graphvizWithHandle cmd gr t (toFile f)
    where
      toFile f h = do squirt h f
                      hClose h
                      hClose f

-- | Append the default extension for the provided 'GraphvizOutput' to
--   the provided 'FilePath' for the output file.  Note that for
--   'GraphvizOutput' values like 'Gtk' and 'Xlib', this is probably a
--   useless function since those don't actually produce any files...
addExtension          :: (GraphvizOutput -> FilePath -> IO a)
                         -> GraphvizOutput -> FilePath -> IO a
addExtension cmd t fp = cmd t fp'
    where
      fp' = fp <.> defaultExtension t

-- graphvizWithHandle sometimes throws an error about handles not
-- being closed properly: investigate (now on the official TODO).

-- | Run the chosen Graphviz command on this graph, but send the
--   result to the given handle rather than to a file.  The @'Handle'
--   -> 'IO' a@ function should close the 'Handle' once it is
--   finished.
--
--   The result is wrapped in 'Maybe' rather than throwing an error.
graphvizWithHandle :: (PrintDot n, Show a) => GraphvizCommand -> DotGraph n
                      -> GraphvizOutput -> (Handle -> IO a) -> IO (Maybe a)
graphvizWithHandle cmd gr t f
    = do (inp, outp, errp, prc) <- runInteractiveCommand command
         forkIO $ hPutStrLn inp (printDotGraph gr) >> hClose inp
         forkIO $ hGetContents errp >>= hPutStr stderr >> hClose errp
         a <- f outp
         exitCode <- waitForProcess prc
         case exitCode of
           ExitSuccess -> return (Just a)
           _           -> return Nothing
    where
      command = showCmd cmd ++ " -T" ++ outputCall t

{- |
   This function is based upon code taken from the /mohws/ project,
   available under a 3-Clause BSD license.  The actual function is
   taken from: <http://code.haskell.org/mohws/src/Util.hs> It provides
   an efficient way of transferring data from one 'Handle' to another.
 -}
squirt :: Handle -> Handle -> IO ()
squirt rd wr = do
  arr <- newArray_ (0, bufsize-1)
  let loop = do
        r <- hGetArray rd arr bufsize
        unless (r == 0)
             $ if r < bufsize
                then hPutArray wr arr r
                else hPutArray wr arr bufsize >> loop
  loop
    where
      -- This was originally separate
      bufsize :: Int
      bufsize = 4 * 1024

