module PluginGraph where

import PluginBase

import qualified Data.Map as M

import Data.Maybe

-- Lookup a plugin

plugByName :: String -> Maybe PluginDef

plugByName s = M.lookup s plugNameMap

plugByUri :: String -> Maybe PluginDef

plugByUri s = M.lookup s plugUriMap

-- Instantiate a named plugin client

data PlugInst = PlugInst (Maybe PluginDef) String deriving (Eq)

-- Client port representing both instance and its port. Can be used for both plugin and hardware ports.
-- In the latter case plugin instance is Nothing

data ClientPort = ClientPort (Maybe PlugInst) PluginPort
  deriving (Eq)


-- A class to provide client port. For hardware ports port itself is returned.
-- For plugin ports the head of the respective port list is returned, or Nothing.
-- Autos, Requires, and Connections are necessary to build a JSON proper.

class ClientPortProvider c where
  getClientPort :: c -> (String -> PluginPort) -> Maybe ClientPort
  getClientPort _ _ = Nothing
  getAutos :: c -> [(String, String)]
  getAutos _ = []
  getRequires :: c -> [String]
  getRequires _ = []
  getConnections :: c -> [(String, String)]
  getConnections _ = []
  getAudioPair :: c -> (String -> PluginPort) -> Maybe (ClientPort, ClientPort)
  getAudioPair _ _ = Nothing

-- A ClientPort returns just itself if the tag matches its type

instance ClientPortProvider ClientPort where
  getClientPort cp@(ClientPort mbp cpp) tag =
    if tag (portName cpp) == cpp
      then Just cp
      else Nothing

-- A Plugin instance tries to find a port suitable for the requested tag.
-- It returns its own mapping of name vs URI as autos.
-- getAudioPair returns the first two audio ports available, or one port twice.

instance ClientPortProvider PlugInst where
  getClientPort (PlugInst Nothing _) _ = Nothing
  getClientPort pi@(PlugInst (Just pd) _) tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> midiInputPorts pd
      MidiOutputPort "" -> midiOutputPorts pd
      AudioInputPort "" -> audioInputPorts pd
      AudioOutputPort "" -> audioOutputPorts pd
    k [] = Nothing
    k (p:ps) = Just $ ClientPort (Just pi) p
  getAutos (PlugInst Nothing _) = []
  getAutos (PlugInst (Just pd) inst) = [(inst, plugUri pd)]
  getRequires (PlugInst Nothing _) = []
  getRequires (PlugInst (Just pd) inst) = ["synth@" ++ inst]
  getAudioPair (PlugInst Nothing _) _ = Nothing
  getAudioPair pi@(PlugInst (Just pd) _) tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> []
      MidiOutputPort "" -> []
      AudioInputPort "" -> take 2 $ audioInputPorts pd
      AudioOutputPort "" -> take 2 $ audioOutputPorts pd
    k [] = Nothing
    k [p1] = Just $ (ClientPort (Just pi) p1, ClientPort (Just pi) p1)
    k [p1, p2] = Just $ (ClientPort (Just pi) p1, ClientPort (Just pi) p2)

-- Plugin group: a composition of multiple plugins, usually built piece by piece
-- It features MIDI input/output ports, and audio input/output pairs, whatever available.

data PluginGroup = PluginGroup {
  pgAutos :: [(String, String)],
  pgRequires :: [String],
  pgConnections :: [(String, String)],
  pgMidiInput :: Maybe ClientPort,
  pgMidiOutput :: Maybe ClientPort,
  pgInputAudioPair :: Maybe (ClientPort, ClientPort),
  pgOutputAudioPair :: Maybe (ClientPort, ClientPort)
} deriving (Eq)

instance ClientPortProvider PluginGroup where
  getClientPort pg tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> maybeToList $ pgMidiInput pg
      MidiOutputPort "" -> maybeToList $ pgMidiOutput pg
      AudioInputPort "" -> map fst $ maybeToList $ pgInputAudioPair pg
      AudioOutputPort "" -> map fst $ maybeToList $ pgOutputAudioPair pg
    k [] = Nothing
    k (p:ps) = Just p
  getAutos = pgAutos
  getRequires = pgRequires
  getConnections = pgConnections
  getAudioPair pg tag = pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> Nothing
      MidiOutputPort "" -> Nothing
      AudioInputPort "" -> pgInputAudioPair pg
      AudioOutputPort "" -> pgOutputAudioPair pg

