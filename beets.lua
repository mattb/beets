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

local function init_crow()
  crow.output[1].action = 'pulse(0.001, 5, 1)'
  crow.output[2].action = 'pulse(0.001, 5, 1)'
  crow.output[3].action = 'pulse(0.001, 5, 1)'
  crow.ii.pullup(true)
end

local function init_beatclock(bpm)
  beat_clock = BeatClock.new()
  beat_clock.ticks_per_step = 6
  beat_clock.steps_per_beat = 4
  beat_clock.on_select_internal = function() beat_clock:start() end
  beat_clock.on_select_external = function() print('external') end
  beat_clock:start()
  beat_clock:bpm_change(bpm)
  beat_clock:add_clock_params()

  local clk_midi = midi.connect(1)
  clk_midi.event = beat_clock.process_mid

  beat_clock.on_step = function()
    local beatstep = beat_clock.steps_per_beat * beat_clock.beat +
                         beat_clock.step
    beets:advance_step(beatstep, beat_clock.bpm)
    redraw()
  end
end

function redraw() beets:drawUI() end

function enc(n, d) if editing then beets:enc(n, d) end end

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
    if n == 2 and z == 0 then beets:toggle_mute() end
    if n == 3 then beets:instant_toggle_mute() end
  end
end

function init()
  audio.level_cut_rev(0)

  beets.on_beat = function() crow.output[1]() end
  beets.on_beat_one = function() crow.output[2]() end
  beets.on_kick = function() crow.output[3]() end
  beets.change_bpm = function(bpm) beat_clock:bpm_change(bpm) end

  beets:add_params()

  local bpm = 130

  init_beatclock(bpm)
  init_crow()
  beets:start(bpm)
end
