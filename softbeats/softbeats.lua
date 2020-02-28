local beats = include('lib/libbeats')
local BeatClock = require "beatclock"

local beat_clock

function init_beatclock(bpm)
  beat_clock = BeatClock.new()
  beat_clock.ticks_per_step = 6
  beat_clock.steps_per_beat = 2
  beat_clock.on_select_internal = function() beat_clock:start() end
  beat_clock.on_select_external = function() print("external") end
  beat_clock:start()
  beat_clock:bpm_change(bpm)
  beat_clock:add_clock_params()

  local clk_midi = midi.connect(1)
  clk_midi.event = beat_clock.process_mid

  beat_clock.on_step = function() 
    local beatstep = beat_clock.steps_per_beat * beat_clock.beat + beat_clock.step
    beats.advance_step(beatstep, beat_clock.bpm)
  end
end

function redraw()
  beats:redraw()
end

function init()
  audio.rev_off()
  audio.comp_off()

  local bpm = 120

  breaks = {
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_10.wav",
      kicks = { 0, 3, 5, 7 } -- list of which beats contain kicks, so that a Crow trigger can fire every time they hit
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_1.wav",
      kicks = { 0, 1, 5 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_2.wav",
      kicks = { 0, 3, 7 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_3.wav",
      kicks = { 0 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_4.wav",
      kicks = { 0 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_5.wav",
      kicks = { 0 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_6.wav",
      kicks = { 0 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_7.wav",
      kicks = { 0 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_8.wav",
      kicks = { 0 }
    },
    { 
      file  = _path.dust .. "audio/breaks/BBB_120_BPM_PRO_BREAK_9.wav",
      kicks = { 0 }
    }
  }

  beats.init(breaks, bpm)
  beats.add_params()

  init_beatclock(bpm)
end
