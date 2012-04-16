{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}

{- |
   Module      : Data.GraphViz.State
   Description : Printing and parsing state.
   Copyright   : (c) Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

   When printing and parsing Dot code, some items depend on values
   that are set earlier.
-}
module Data.GraphViz.State
       ( GraphvizStateM(..)
       , GraphvizState(..)
       , AttributeType(..)
       , setAttributeType
       , getAttributeType
       , initialState
       , setDirectedness
       , getDirectedness
       , setLayerSep
       , getLayerSep
       , setColorScheme
       , getColorScheme
       ) where

import Data.GraphViz.Attributes.ColorScheme

import Control.Monad.Trans.State(State, modify, gets)
import Text.ParserCombinators.Poly.StateText(Parser, stUpdate, stQuery)

-- -----------------------------------------------------------------------------

class (Monad m) => GraphvizStateM m where
  modifyGS :: (GraphvizState -> GraphvizState) -> m ()

  getsGS :: (GraphvizState -> a) -> m a

instance GraphvizStateM (State GraphvizState) where
  modifyGS = modify

  getsGS = gets

instance GraphvizStateM (Parser GraphvizState) where
  modifyGS = stUpdate

  getsGS = stQuery

data AttributeType = GraphAttribute
                   | SubGraphAttribute
                   | ClusterAttribute
                   | NodeAttribute
                   | EdgeAttribute
                     deriving (Eq, Ord, Show, Read)

-- | Several aspects of Dot code are either global or mutable state.
data GraphvizState = GS { directedEdges :: !Bool
                        , layerSep      :: [Char]
                        , attributeType :: !AttributeType
                        , graphColor    :: !ColorScheme
                        , clusterColor  :: !ColorScheme
                        , nodeColor     :: !ColorScheme
                        , edgeColor     :: !ColorScheme
                        }
                   deriving (Eq, Ord, Show, Read)

initialState :: GraphvizState
initialState = GS { directedEdges = True
                  , layerSep      = defLayerSep
                  , attributeType = GraphAttribute
                  , graphColor    = X11
                  , clusterColor  = X11
                  , nodeColor     = X11
                  , edgeColor     = X11
                  }

setDirectedness   :: (GraphvizStateM m) => Bool -> m ()
setDirectedness d = modifyGS (\ gs -> gs { directedEdges = d } )

getDirectedness :: (GraphvizStateM m) => m Bool
getDirectedness = getsGS directedEdges

setAttributeType    :: (GraphvizStateM m) => AttributeType -> m ()
setAttributeType tp = modifyGS $ \ gs -> gs { attributeType = tp }

getAttributeType :: (GraphvizStateM m) => m AttributeType
getAttributeType = getsGS attributeType

setLayerSep     :: (GraphvizStateM m) => [Char] -> m ()
setLayerSep sep = modifyGS (\ gs -> gs { layerSep = sep } )

getLayerSep :: (GraphvizStateM m) => m [Char]
getLayerSep = getsGS layerSep

setColorScheme    :: (GraphvizStateM m) => ColorScheme -> m ()
setColorScheme cs = do tp <- getsGS attributeType
                       modifyGS $ \gs -> case tp of
                                           GraphAttribute    -> gs { graphColor   = cs }
                                            -- subgraphs don't have specified scheme
                                           SubGraphAttribute -> gs { graphColor   = cs }
                                           ClusterAttribute  -> gs { clusterColor = cs }
                                           NodeAttribute     -> gs { nodeColor    = cs }
                                           EdgeAttribute     -> gs { edgeColor    = cs }

getColorScheme :: (GraphvizStateM m) => m ColorScheme
getColorScheme = do tp <- getsGS attributeType
                    getsGS $ case tp of
                               GraphAttribute    -> graphColor
                                -- subgraphs don't have specified scheme
                               SubGraphAttribute -> graphColor
                               ClusterAttribute  -> clusterColor
                               NodeAttribute     -> nodeColor
                               EdgeAttribute     -> edgeColor

-- | The default separators for 'LayerSep'.
defLayerSep :: [Char]
defLayerSep = [' ', ':', '\t']
