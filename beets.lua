-- Beets
-- 1.0 @mattb
--
-- Probabilistic performance
-- drum loop re-sequencer
--
-- Put one-bar WAVs in folders
-- in dust/audio/beets
--
-- K1 : Hold for edit mode
-- K2 : Quantized mute toggle
-- K3 : Instant mute while held
--
-- Use a Grid, or map
-- MIDI controller to params

local ENABLE_CROW = false -- not finished, and may stomp over clock Crow controls if enabled

local Beets = include('lib/libbeets')
local beets_audio_dir = _path.audio .. 'beets'

local Passthrough = include('lib/passthrough')

local beets = Beets.new {softcut_voice_id = 1}
local beets2 = Beets.new {softcut_voice_id = 2}

local editing = false
local g = grid.connect()

local arc_kick_counter = 1
local arc_snare_counter = 1

local function update_arc(a, beat)
  if arc_kick_counter > 0 then
    arc_kick_counter = arc_kick_counter - 0.05
  end
  if arc_snare_counter > 0 then
    arc_snare_counter = arc_snare_counter - 0.05
  end
  local levels = {arc_kick_counter, arc_snare_counter}
  for i, l in ipairs(levels) do
    l = util.clamp(l, 0, 1)
    for n = 1, 64 do
      a:led(i + 2, n, math.floor(l * 15))
    end
  end
  for i = 1, 64 do
    local v = 4
    if math.floor(1 + i / 8) == math.floor(1 + beat / 2) then
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

local function init_arc()
  local a = arc.connect()
  clock.run(
    function()
      while true do
        clock.sleep(1 / 60)
        local beatstep = math.floor(clock.get_beats() * 2) % 8
        update_arc(a, beatstep)
      end
    end
  )
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
  crow.output[2].action = 'pulse(0.001, 5, 1)'
  crow.output[3].action = 'pulse(0.001, 5, 1)'
  crow.output[4].action = 'pulse(0.001, 5, 1)'
end

local function beat()
  while true do
    clock.sync(1 / 2)
    local beatstep = math.floor(clock.get_beats() * 2) % 8
    beets:advance_step(beatstep, clock.get_tempo())
    beets2:advance_step(beatstep, clock.get_tempo())
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

function init_beets_dir()
  if util.file_exists(beets_audio_dir) == false then
    util.make_dir(beets_audio_dir)
    local demodir = _path.code .. 'beets/demo-loops'
    if util.file_exists(demodir) then
      for _, dirname in ipairs(util.scandir(demodir)) do
        local from_dir = demodir .. '/' .. dirname
        local to_dir = beets_audio_dir .. '/' .. dirname
        util.make_dir(to_dir)
        util.os_capture('cp ' .. from_dir .. '* ' .. to_dir)
      end
    end
  end
end

function init()
  init_beets_dir()

  params:add_separator('BEETS')

  audio.level_cut_rev(0)

  beets.on_beat = function()
  end
  if ENABLE_CROW then
    beets.on_beat_one = function()
      crow.output[2]()
    end
    beets.on_kick = function()
      arc_kick_counter = 1
      crow.output[3]()
    end
    beets.on_snare = function()
      arc_snare_counter = 1
      crow.output[4]()
    end
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
  beets2:add_params()

  params:add_separator('UTILITIES')
  Passthrough.init()

  clock.run(beat)
  if ENABLE_CROW then
    init_crow()
  end
  init_arc()

  beets:start()
  beets2:start()
end
