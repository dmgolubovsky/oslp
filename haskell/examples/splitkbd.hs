module Main where

import PluginGraph
import PluginBase

import Data.Maybe


twosplit_k = PlugInst (plugByUri "http://gareus.org/oss/lv2/midifilter#keysplit") "twosplit_k"

twosplit_m = PlugInst (plugByUri "http://kxstudio.sf.net/carla/plugins/midisplit") "twosplit_m"

[out1, out2] = take 2 $ breakOut twosplit_m $ \i (pp, pi) -> case pp of
  MidiOutputPort _ -> i == pi
  MidiInputPort _ -> True
  _ -> False

hw = emptyHWPortGroup {
  hwmOutputPorts = [MidiOutputPort "a2j:A-PRO (capture): A-PRO 1"],
  hwaInputPorts = [AudioOutputPort "system:playback_1", AudioOutputPort "system:playback_2"]
}

helm = PlugInst (plugByUri "http://tytel.org/helm") "split_helm"

zyn = PlugInst (plugByUri "http://zynaddsubfx.sourceforge.net") "split_zyn"

splt = hw `ser` twosplit_k `ser` twosplit_m

track1 = out1 `ser` helm `ser` hw

track2 = out2 `ser` zyn `ser` hw

main = do
  putStrLn $ genJSONMerge [splt, track1, track2] "xxxx"

