local beats = include('softbeats/lib/libbeats.lua')
local BeatClock = require "beatclock"

local beat_clock

function init_beatclock(bpm)
  beat_clock = BeatClock.new()
  beat_clock.ticks_per_step = 6
  beat_clock.steps_per_beat = 2
  beat_clock.on_select_internal = function() beat_clock:start() end
  beat_clock.on_select_external = function() print("external") end
  beat_clock:add_clock_params()
  beat_clock:start()

  beat_clock:bpm_change(bpm)

  local clk_midi = midi.connect(1)
  clk_midi.event = beat_clock.process_mid

  beat_clock.on_step = beats.advance_step
end

function init()
  audio.rev_off()
  audio.comp_off()

  local file = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_10.wav"
  beats.init(file)
  beats.add_params()
  init_beatclock(120)
end
