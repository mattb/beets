-- Beets
-- 0.1 @mattb
--
-- Probabilistic performance 
-- drum loop resequencer
-- 
-- K2 : Quantized mute toggle
-- K3 : Instant mute while held 
local BeatClock = require 'beatclock'
local Beets = include('lib/libbeets')

local beat_clock
local beets = Beets.new(1)

local editing = false

function init_beatclock(bpm)
  beat_clock = BeatClock.new()
  beat_clock.ticks_per_step = 6
  beat_clock.steps_per_beat = 2
  beat_clock.on_select_internal = function()
    beat_clock:start()
  end
  beat_clock.on_select_external = function()
    print('external')
  end
  beat_clock:start()
  beat_clock:bpm_change(bpm)
  beat_clock:add_clock_params()

  local clk_midi = midi.connect(1)
  clk_midi.event = beat_clock.process_mid

  beat_clock.on_step = function()
    local beatstep = beat_clock.steps_per_beat * beat_clock.beat + beat_clock.step
    beets:advance_step(beatstep, beat_clock.bpm)
    redraw()
  end
end

function redraw()
  beets:drawUI()
end

function enc(n, d)
  if editing then
    beets:enc(n, d)
  end
end

function key(n, z)
  if n == 1 and z == 1 then
    editing = true
    beets:edit_mode_begin()
  end
  if editing then
    if n == 1 and z == 0 then
      editing = false
      beets:edit_mode_end()
    else
      beets:key(n, z)
    end
  else
    if n == 1 and z == 1 then
      editing = true
      beets:show_edit_screen()
    end
    if n == 2 and z == 0 then
      beets:toggle_mute()
    end
    if n == 3 then
      beets:instant_toggle_mute()
    end
  end
end

function init()
  audio.rev_off()
  audio.comp_off()

  local bpm = 120

  different_bpm_breaks = {
    {file = _path.dust .. 'audio/breaks/BBB_110_BPM_PRO_BREAK_1.wav', kicks = {0}},
    {file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_3.wav', kicks = {0}},
    {file = _path.dust .. 'audio/breaks/BBB_80_BPM_PRO_BREAK_10.wav', kicks = {0}}
  }

  unused_breaks = {
    {file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_1.wav', kicks = {0, 1, 5}},
    {file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_3.wav', kicks = {0, 3, 5}},
  }

  breaks = {
    { -- 1
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_2.wav',
      kicks = {0, 3, 7},
    },
    { -- 2
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_6.wav',
      kicks = {0, 4},
    },
    { -- 3
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_7.wav',
      kicks = {0},
    },
    { -- 4
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_9.wav',
      kicks = {0, 3, 5},
    },
    { -- 5
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_5.wav',
      kicks = {0, 5},
    },
    { -- 6
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_4.wav',
      kicks = {0, 3, 5},
    },
    { -- 7
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_8.wav',
      kicks = {0, 5},
    },
    { -- 8
      file = _path.dust .. 'audio/breaks/BBB_120_BPM_PRO_BREAK_10.wav',
      kicks = {0, 3, 5, 7}, -- list of which beets contain kicks, so that a Crow trigger can fire every time they hit
    },
  }

  beets:init(breaks, bpm)
  for i, brk in ipairs(breaks) do
    beets:load_loop(i, brk.file, brk.kicks)
  end

  beets:add_params()

  init_beatclock(bpm)
  beets:start()
end
