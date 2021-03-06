module PluginGraph where

import PluginBase

import System.Process
import System.Exit
import System.IO

import qualified Data.Map as M
import Data.List

import Data.Maybe

-- Lookup a plugin

plugByName :: String -> Maybe PluginDef

plugByName s = M.lookup s plugNameMap

plugByUri :: String -> Maybe PluginDef

plugByUri s = M.lookup s plugUriMap

-- Instantiate a named plugin client

data PlugInst = PlugInst (Maybe PluginDef) String [String] deriving (Show, Eq)

-- Client port representing both instance and its port. Can be used for both plugin and hardware ports.
-- In the latter case plugin instance is Nothing

data ClientPort = ClientPort (Maybe PlugInst) PluginPort
  deriving (Eq, Show)

clientPortName :: ClientPort -> String

clientPortName (ClientPort Nothing pp) = portName pp
clientPortName (ClientPort (Just (PlugInst _ s _)) pp) = s ++ ":" ++ (portName pp)

-- A hardware group of Audio or MIDI ports. Port names are just entered directly.

data HWPortGroup = HWPortGroup {
  hwmInputPorts :: [PluginPort],
  hwmOutputPorts :: [PluginPort],
  hwaInputPorts :: [PluginPort],
  hwaOutputPorts :: [PluginPort]
} deriving (Eq)

emptyHWPortGroup = HWPortGroup {
  hwmInputPorts = [],
  hwmOutputPorts = [],
  hwaInputPorts = [],
  hwaOutputPorts = []
}

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
  getSettings :: c -> [(String, [String])]
  getSettings _ = []

-- A Hardware group of ports only returns its ports but no plugins to instantiate.

instance ClientPortProvider HWPortGroup where
  getClientPort pd tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> hwmInputPorts pd
      MidiOutputPort "" -> hwmOutputPorts pd
      AudioInputPort "" -> hwaInputPorts pd
      AudioOutputPort "" -> hwaOutputPorts pd
    k [] = Nothing
    k (p:ps) = Just $ ClientPort Nothing p
  getAudioPair pd tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> []
      MidiOutputPort "" -> []
      AudioInputPort "" -> take 2 $ hwaInputPorts pd
      AudioOutputPort "" -> take 2 $ hwaOutputPorts pd
    k [] = Nothing
    k [p1] = Just $ (ClientPort Nothing p1, ClientPort Nothing p1)
    k [p1, p2] = Just $ (ClientPort Nothing p1, ClientPort Nothing p2)

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
  getClientPort (PlugInst Nothing _ _) _ = Nothing
  getClientPort pi@(PlugInst (Just pd) _ _) tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> midiInputPorts pd
      MidiOutputPort "" -> midiOutputPorts pd
      AudioInputPort "" -> audioInputPorts pd
      AudioOutputPort "" -> audioOutputPorts pd
    k [] = Nothing
    k (p:ps) = Just $ ClientPort (Just pi) p
  getAutos (PlugInst Nothing _ _) = []
  getAutos (PlugInst (Just pd) inst _) = [(inst, plugUri pd)]
  getRequires (PlugInst Nothing _ _) = []
  getRequires (PlugInst (Just pd) inst _) = ["lv2synth@" ++ inst]
  getAudioPair (PlugInst Nothing _ _) _ = Nothing
  getAudioPair pi@(PlugInst (Just pd) _ _) tag = k pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> []
      MidiOutputPort "" -> []
      AudioInputPort "" -> take 2 $ audioInputPorts pd
      AudioOutputPort "" -> take 2 $ audioOutputPorts pd
    k [] = Nothing
    k [p1] = Just $ (ClientPort (Just pi) p1, ClientPort (Just pi) p1)
    k [p1, p2] = Just $ (ClientPort (Just pi) p1, ClientPort (Just pi) p2)
  getSettings (PlugInst _ inst stgs) = [(inst, stgs)]

-- Plugin group: a composition of multiple plugins, usually built piece by piece
-- It features MIDI input/output ports, and audio input/output pairs, whatever available.

data PluginGroup = PluginGroup {
  pgAutos :: [(String, String)],
  pgRequires :: [String],
  pgConnections :: [(String, String)],
  pgMidiInput :: Maybe ClientPort,
  pgMidiOutput :: Maybe ClientPort,
  pgInputAudioPair :: Maybe (ClientPort, ClientPort),
  pgOutputAudioPair :: Maybe (ClientPort, ClientPort),
  pgSettings :: [(String, [String])]
} deriving (Eq, Show)

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
  getSettings = pgSettings
  getAudioPair pg tag = pdl where
    pdl = case (tag "") of
      MidiInputPort "" -> Nothing
      MidiOutputPort "" -> Nothing
      AudioInputPort "" -> pgInputAudioPair pg
      AudioOutputPort "" -> pgOutputAudioPair pg

-- Serial composition

ser :: (ClientPortProvider a, ClientPortProvider b) => a -> b -> PluginGroup

ser src dst = PluginGroup {
  pgMidiInput = getClientPort src MidiInputPort,
  pgMidiOutput = getClientPort dst MidiOutputPort,
  pgInputAudioPair = getAudioPair src AudioInputPort,
  pgOutputAudioPair = getAudioPair dst AudioOutputPort,
  pgConnections = midicon ++ audiocon ++ getConnections src ++ getConnections dst,
  pgRequires = getRequires src ++ getRequires dst,
  pgAutos = getAutos src ++ getAutos dst,
  pgSettings = nub (getSettings src ++ getSettings dst)
} where
    midicon = k cp1 cp2
    cp1 = getClientPort src MidiOutputPort
    cp2 = getClientPort dst MidiInputPort
    k (Just p1) (Just p2) = [(clientPortName p1, clientPortName p2)]
    k _ _ = []
    audiocon = r ap1 ap2
    ap1 = getAudioPair src AudioOutputPort
    ap2 = getAudioPair dst AudioInputPort
    r (Just (o1, o2)) (Just (i1, i2)) = [(clientPortName o1, clientPortName i1), (clientPortName o2, clientPortName i2)]
    r _ _ = []

-- Generate JSON for a PluginGroup providing a name for systemd service

genJSON :: PluginGroup -> String -> String

genJSON ps = genJSONMerge [ps]

genJSONMerge :: [PluginGroup] -> String -> String

genJSONMerge pg cs = top [descr, autos, requires, clnt, clss, connect, settings] where
  top ss = "{" ++ show cs ++ ": {" ++ intercalate ", " ss ++ "} }"
  pair a b = show a ++ ": " ++ show b
  descr = pair "description" cs
  clnt = pair "client" cs
  clss = pair "class" "syngrp"
  list nl ls = show nl ++ ": [" ++ intercalate ", " (map show ls) ++ "]"
  requires = list "requires" (nub $ concatMap getRequires pg)
  listmap nl lsm = show nl ++ ": {" ++ intercalate ", " (map showmap lsm) ++ "}"
  showmap (k, v) = show k ++ ": " ++ show v
  autos = listmap "auto" $ nub $ concatMap getAutos pg
  connpg = concatMap getConnections pg
  connsw = map (\(a, b) -> (b, a)) connpg
  connect = listmap "connect" $ map mapsh $ nub (connpg ++ connsw)
  mapsh (f, s) = (f, '#':s)
  settings = listmap "settings" $ nub $ concatMap getSettings pg

-- Useful utilities for (un)loading patches from ghci

genJSONMergeM :: [PluginGroup] -> String -> IO String

genJSONMergeM pg cs = return $ genJSONMerge pg cs

-- General processing of JSON generated from a Plugin Group

procJSON :: String -> String -> IO ExitCode

procJSON pgm js = do
  (mb_hstdin, _, _, ph) <- createProcess (proc pgm []) { std_in = CreatePipe }
  case mb_hstdin of
    Nothing -> return $ ExitFailure 1
    Just hstdin -> do
      hPutStrLn hstdin js
      hFlush hstdin
      waitForProcess ph



loadPatch = procJSON "/usr/bin/loadpatch"

unLoadPatch = procJSON "/usr/bin/unloadpatch"



-- Breakout a plugin instance into multiple instances. May be useful with multichannel inputs or outputs.
-- A split instance has a subset of input/output ports as designated by the filter function provided.
-- Split indices start with 1

breakOut :: PlugInst -> (Int -> (PluginPort, Int) -> Bool) -> [PlugInst]

breakOut pi@(PlugInst Nothing _ _) _ = repeat pi

breakOut (PlugInst (Just pd) inst stgs) f = map x [1..] where
  x i = PlugInst (Just pd') inst stgs where
    pd' = pd {
      midiInputPorts = map fst $ filter (f i) (zip (midiInputPorts pd) [1..]),
      midiOutputPorts = map fst $ filter (f i) (zip (midiOutputPorts pd) [1..]),
      audioInputPorts = map fst $ filter (f i) (zip (audioInputPorts pd) [1..]),
      audioOutputPorts = map fst $ filter (f i) (zip (audioOutputPorts pd) [1..])
    }



