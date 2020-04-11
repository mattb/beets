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

local Passthrough = include('lib/passthrough')

local beat_clock
local beets = Beets.new {softcut_voice_id = 1}
local beets2 = Beets.new {softcut_voice_id = 2}

local editing = false
local g = grid.connect()

local kick = 1
local snare = 1

function init_arc()
  local a = arc.connect()
  local ametro = metro.init()
  ametro.time = 1 / 60
  ametro.event = function()
    if kick > 0 then
      kick = kick - 0.05
    end
    if snare > 0 then
      snare = snare - 0.05
    end
    local levels = {kick, snare}
    for i, l in ipairs(levels) do
      l = util.clamp(l, 0, 1)
      for n = 1, 64 do
        a:led(i + 2, n, math.floor(l * 15))
      end
    end
    local beatstep = beat_clock.steps_per_beat * beat_clock.beat + beat_clock.step
    for i = 1, 64 do
      local v = 4
      if math.floor(1 + i / 8) == math.floor(1 + beatstep / 2) then
        v = 15
      end
      a:led(1, i, v)

      v = 4
      if math.floor(i / 8) == beets.played_index then
        v = 15
      end
      a:led(2, i, v)
    end
    a:refresh()
  end
  return ametro
end

g.key = function(x, y, z)
  if params:get('orientation') == 1 then -- horizontal
    if x < 9 then
      beets:grid_key(x, y, z)
    else
      beets2:grid_key(x - 8, y, z)
    end
  else
    if y < 9 then
      beets:grid_key(x, y, z)
    else
      beets2:grid_key(x, y - 8, z)
    end
  end
end

local function init_crow()
  crow.output[1].action = 'pulse(0.001, 5, 1)'
  crow.output[2].action = 'pulse(0.001, 5, 1)'
  crow.output[3].action = 'pulse(0.001, 5, 1)'
  crow.output[4].action = 'pulse(0.001, 5, 1)'
  crow.ii.pullup(true)
end

local function init_beatclock(bpm)
  beat_clock = BeatClock.new()
  beat_clock.ticks_per_step = 6
  beat_clock.steps_per_beat = 4
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
    beets2:advance_step(beatstep, beat_clock.bpm)
    redraw()
    beets:drawGridUI(g, 1, 1)
    if params:get('orientation') == 1 then -- horizontal
      beets2:drawGridUI(g, 9, 1)
    else
      beets2:drawGridUI(g, 1, 9)
    end
    g:refresh()
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
  Passthrough.init()

  audio.level_cut_rev(0)

  beets.on_beat = function()
    crow.output[1]()
  end
  beets.on_beat_one = function()
    crow.output[2]()
  end
  beets.on_kick = function()
    kick = 1
    crow.output[3]()
  end
  beets.on_snare = function()
    snare = 1
    crow.output[4]()
  end
  beets.change_bpm = function(bpm)
    beat_clock:bpm_change(bpm)
  end

  beets2.change_bpm = function(bpm)
    beat_clock:bpm_change(bpm)
  end

  params:add {
    type = 'option',
    id = 'orientation',
    name = 'Grid orientation',
    options = {'horizontal', 'vertical'},
    action = function(val)
      if val == 1 then
        g:rotation(0)
      else
        g:rotation(3)
      end
    end
  }

  beets:add_params()
  params:add_separator()
  beets2:add_params()
  params:add_separator()

  local bpm = 130

  init_beatclock(bpm)
  init_crow()
  beets:start(bpm)
  beets2:start(bpm)
  local ametro = init_arc()
  ametro:start()
end
