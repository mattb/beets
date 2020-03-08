-- TODO:
--
-- highpass filter - requires intelligently switching the wet/dry mix of HP and LP based on which one is in use, or having a priority override
-- grids UI
local Beets = {}
Beets.__index = Beets

local ControlSpec = require 'controlspec'
local Formatters = require 'formatters'

local BREAK_OFFSET = 5
local EVENT_ORDER = { "<", ">", "R", "S", "B" }
local json = include("lib/json")

function Beets.new(softcut_voice_id)
  local i = {
    -- descriptive global state
    running = false,
    enable_mutations = true,
    id = softcut_voice_id,
    beat_count = 8,
    initial_bpm = 130,
    loops_by_filename = {},
    loop_index_to_filename = {},
    loop_count = 0,
    editing = false,

    -- state that changes on the beat
    beatstep = 0,
    index = 0,
    played_index = 0,
    played_loop_index = 0,
    message = '',
    status = '',
    events = {},
    muted = false,
    current_bpm = 0,
    beat_start = 0,
    beat_end = 7,
    loop_index = 1,

    on_beat_one = function() end,
    on_beat = function() end,
    on_kick = function() end,
    on_snare = function() end,
    change_bpm = function() end,

    -- probability values
    probability = {loop_index_jump = 0, stutter = 0, reverse = 0, jump = 0, jump_back = 0},
  }

  setmetatable(i, Beets)

  return i
end

function Beets:advance_step(in_beatstep, in_bpm)
  self.events = {}
  self.message = ''
  self.status = ''
  self.beatstep = in_beatstep
  self.current_bpm = in_bpm

  self.played_index = self.index

  if not self.running then
    self.status = 'NOT RUNNING'
    return
  end

  if self.loop_count == 0 then
    self.status = 'NO LOOPS'
    return
  end

  self:play_slice(self.index)
  self:calculate_next_slice()
end

function Beets:instant_toggle_mute()
  self:toggle_mute()
  if self.muted then
    softcut.level(self.id, 0)
  else
    softcut.level(self.id, 1)
  end
end

function Beets:mute(in_muted)
  if in_muted then
    self.muted = true
  else
    self.muted = false
  end
end

function Beets:toggle_mute()
  self:mute(not self.muted)
end

function Beets:should(thing)
  if not self.enable_mutations then
    return false
  end
  return math.random(100) <= self.probability[thing]
end

function Beets:play_slice(slice_index)
  self.on_beat()
  if self.beatstep == 0 then
    self.on_beat_one()
  end

  self.played_loop_index = self.loop_index
  if (self:should('loop_index_jump')) then
    self.played_loop_index = math.random(self.loop_count)
    self.events['B'] = 1
  else
    self.events['B'] = 0
  end

  local loop = self.loops_by_filename[self.loop_index_to_filename[self.played_loop_index]]
  local current_rate = loop.rate * (self.current_bpm / self.initial_bpm)

  if (self:should('stutter')) then
    self.events['S'] = 1
    local stutter_amount = math.random(4)
    softcut.loop_start(self.id, loop.start
                         + (slice_index * (loop.duration / self.beat_count)))
    softcut.loop_end(self.id,
                     loop.start
                       + (slice_index * (loop.duration / self.beat_count)
                         + (loop.duration / (64.0 / stutter_amount))))
  else
    self.events['S'] = 0
    softcut.loop_start(self.id, loop.start)
    softcut.loop_end(self.id, loop.start + loop.duration)
  end

  if (self:should('reverse')) then
    self.events['R'] = 1
    softcut.rate(self.id, 0 - current_rate)
  else
    self.events['R'] = 0
    softcut.rate(self.id, current_rate)
  end

  if self.muted then
    softcut.level(self.id, 0)
  else
    softcut.level(self.id, 1)
  end

  softcut.position(self.id, loop.start
                     + (slice_index * (loop.duration / self.beat_count)))

  if self.muted then
    self.status = 'MUTED'
  end

  self:notify_beat(loop.beat_types[slice_index+1])
end

function Beets:notify_beat(beat_type)
  if beat_type == 'K' then
    self.on_kick()
  end
  if beat_type == 'S' then
    self.on_snare()
  end
end

function Beets:calculate_next_slice()
  local new_index = self.index + 1
  if new_index > self.beat_end then
    new_index = self.beat_start
  end

  if (self:should('jump')) then
    self.events['>'] = 1
    new_index = (new_index + 1) % self.beat_count
  else
    self.events['>'] = 0
  end

  if (self:should('jump_back')) then
    self.events['<'] = 1
    new_index = (new_index - 1) % self.beat_count
  else
    self.events['<'] = 0
  end

  if (self.beatstep == self.beat_count - 1) then
    new_index = self.beat_start
  end
  self.index = new_index
end

function Beets:clear_loops()
  self.loop_index_to_filename = {}
  self.loops_by_filename = {}
  self.loop_count = 0
end

function Beets:load_directory(path, bpm)
  self:clear_loops()
  self.initial_bpm = bpm
  self.change_bpm(bpm)

  f = io.popen('ls ' .. path .. "/*.wav")
  filenames={}
  for name in f:lines() do 
    table.insert(filenames, name)
  end
  table.sort(filenames)

  for i, name in ipairs(filenames) do
    self:load_loop(i,{ file=name })
    i=i+1
  end
end

function Beets:load_loop(index, loop)
  local filename = loop.file
  local kicks = loop.kicks
  local snares = loop.snares
  local loop_info = {}

  local ch, samples, samplerate = audio.file_info(filename)
  loop_info.frames = samples
  loop_info.rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
  loop_info.duration = samples / 48000.0
  loop_info.beat_types = { " ", " ", " ", " ", " ", " ", " ", " " }
  loop_info.filename = filename
  loop_info.start = index * BREAK_OFFSET
  loop_info.index = index

  softcut.buffer_read_mono(filename, 0, loop_info.start, -1, 1, 1)

  if kicks then
    for _, beat in ipairs(kicks) do
      loop_info.beat_types[beat + 1] = "K"
    end
  end

  if snares then
    for _, beat in ipairs(snares) do
      loop_info.beat_types[beat + 1] = "S"
    end
  end

  self.loop_index_to_filename[index] = filename
  self.loops_by_filename[filename] = loop_info
  self.loop_count = index
  self:reset_loop_index_param()

  local f=io.open(filename .. ".json", "w")
  f:write(json.encode(loop_info))
  f:close()
end

function Beets:softcut_init()
  softcut.enable(self.id, 1)
  softcut.buffer(self.id, 1)
  softcut.level(self.id, 1)
  softcut.level_slew_time(self.id, 0.2)
  softcut.loop(self.id, 1)
  softcut.loop_start(self.id, 0)
  softcut.loop_end(self.id, 0)
  softcut.position(self.id, 0)
  softcut.rate(self.id, 0)
  softcut.play(self.id, 1)
  softcut.fade_time(self.id, 0.010)

  softcut.post_filter_dry(self.id, 0.0)
  softcut.post_filter_lp(self.id, 1.0)
  softcut.post_filter_rq(self.id, 0.3)
  softcut.post_filter_fc(self.id, 44100)
end

function Beets:start(in_bpm)
  self.initial_bpm = in_bpm
  self:softcut_init()
  self.running = true
end

function Beets:stop()
  self.running = false
  softcut.play(self.id, 0)
end

function Beets:reset_loop_index_param()
  for _, p in ipairs(params.params) do
    if p.id == 'loop_index' then
      p.controlspec = ControlSpec.new(1, self.loop_count, 'lin', 1, 1, '')
    end
  end
end

function Beets:add_params()
  local specs = {}
  specs.FILTER_FREQ = ControlSpec.new(20, 20000, 'exp', 0, 20000, 'Hz')
  specs.FILTER_RESONANCE = ControlSpec.new(0.05, 1, 'lin', 0, 0.25, '')
  specs.PERCENTAGE = ControlSpec.new(0, 1, 'lin', 0.01, 0, '%')
  specs.BEAT_START = ControlSpec.new(0, self.beat_count - 1, 'lin', 1, 0, '')
  specs.BEAT_END =
    ControlSpec.new(0, self.beat_count - 1, 'lin', 1, self.beat_count - 1, '')

  local files = {}
  local files_count = 0
  local loops_dir = _path.dust .. 'audio/beets/'
  f = io.popen('cd ' .. loops_dir .. "; ls -d *")
  for name in f:lines() do 
    table.insert(files, name)
    files_count = files_count + 1
  end
  table.sort(files)

  if files_count == 0 then
    name = 'Create folders in audio/beets to load'
    self.loops_folder_name = "-"
  else
    name = 'Loops folder'
    self.loops_folder_name = files[1]
  end

  params:add{
    type = 'option',
    id = 'dir_chooser',
    name = name,
    options = files,
    action = function(value)
      self.loops_folder_name = files[value]
    end
  }

  params:add{
    type = 'number',
    id = 'dir_bpm',
    name = 'Loops BPM',
    min = 1,
    max = 300,
    default = self.initial_bpm,
    action = function(value)
      self.initial_bpm = value
    end
  }

  params:add{
    type = 'trigger',
    id = 'load_loops',
    name = 'Load loops',
    action = function(value)
      if value == "-" then
	return
      end
      self:load_directory(_path.dust .. 'audio/beets/' .. self.loops_folder_name, self.initial_bpm)
    end
  }

  params:add_separator()

  params:add{
    type = 'control',
    id = 'loop_index',
    name = 'Sample',
    controlspec = ControlSpec.new(1, self.loop_count, 'lin', 1, 1, ''),
    action = function(value)
      self.loop_index = value
    end,
  }

  params:add{
    type = 'control',
    id = 'jump_back_probability',
    name = 'Jump Back Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.jump_back = value * 100
    end,
  }

  params:add{
    type = 'control',
    id = 'jump_probability',
    name = 'Jump Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.jump = value * 100
    end,
  }

  params:add{
    type = 'control',
    id = 'reverse_probability',
    name = 'Reverse Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.reverse = value * 100
    end,
  }

  params:add{
    type = 'control',
    id = 'stutter_probability',
    name = 'Stutter Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.stutter = value * 100
    end,
  }

  params:add{
    type = 'control',
    id = 'loop_index_jump_probability',
    name = 'Break Index Jump Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.loop_index_jump = value * 100
    end,
  }

  params:add{
    type = 'control',
    id = 'filter_frequency',
    name = 'Filter Cutoff',
    controlspec = specs.FILTER_FREQ,
    formatter = Formatters.format_freq,
    action = function(value)
      softcut.post_filter_fc(self.id, value)
    end,
  }

  params:add{
    type = 'control',
    id = 'filter_reso',
    name = 'Filter Resonance',
    controlspec = specs.FILTER_RESONANCE,
    action = function(value)
      softcut.post_filter_rq(self.id, value)
    end,
  }

  params:add{
    type = 'control',
    id = 'beat_start',
    name = 'Beat Start',
    controlspec = specs.BEAT_START,
    action = function(value)
      self.beat_start = value
    end,
  }

  params:add{
    type = 'control',
    id = 'beat_end',
    name = 'Beat End',
    controlspec = specs.BEAT_END,
    action = function(value)
      self.beat_end = value
    end,
  }
end

function Beets:drawPlaybackUI()
  local horiz_spacing = 9
  local vert_spacing = 9
  local left_margin = 10
  local top_margin = 10
  screen.clear()
  screen.level(15)

  if self.loop_count > 0 then
    local loop = self.loops_by_filename[self.loop_index_to_filename[self.loop_index]]

    for i = 0, 7 do
      screen.rect(left_margin + horiz_spacing * i, top_margin, horiz_spacing, vert_spacing)
      if self.played_index == i then
        screen.level(15)
      elseif self.beatstep == i then
        screen.level(2)
      else
        screen.level(0)
      end
      screen.fill()
      screen.rect(left_margin + horiz_spacing * i, top_margin, horiz_spacing, vert_spacing)

      screen.level(1)
      screen.move(left_margin + horiz_spacing * i + 2, top_margin + 6)
      screen.text(loop.beat_types[i+1])

      screen.level(2)
      screen.stroke()

      screen.level(15)
    end

    screen.level(6)
    screen.move(left_margin + self.beat_start * horiz_spacing, top_margin + vert_spacing + 2)
    screen.line(left_margin + self.beat_start * horiz_spacing, top_margin + vert_spacing + 6)
    screen.line(left_margin + (self.beat_end + 1) * horiz_spacing, top_margin + vert_spacing + 6)
    screen.line(left_margin + (self.beat_end + 1) * horiz_spacing, top_margin + vert_spacing + 2)
    screen.stroke()

    screen.level(15)
    screen.move(left_margin + self.beat_count * horiz_spacing + 30, top_margin)
    screen.text(self.played_loop_index)
    for y, e in ipairs(EVENT_ORDER) do
      screen.move(left_margin + self.beat_count * horiz_spacing + 30, top_margin + vert_spacing * y)
      if self.events[e] == 1 then
        screen.level(15)
      else
        screen.level(1)
      end
      screen.text(e)
    end
  end

  screen.level(15)
  screen.move(left_margin, 40)
  screen.text(self.message)
  screen.move(left_margin, 50)
  screen.text(self.status)
end

function Beets:drawEditingUI()
  screen.move(10, 10)
  screen.text('EDIT MODE')
end

function Beets:drawUI()
  screen.clear()
  screen.level(15)

  if self.editing then
    self:drawEditingUI()
  else
    self:drawPlaybackUI()
  end
  screen.update()
end

function Beets:edit_mode_begin()
  self.editing = true
  redraw()
end

function Beets:edit_mode_end()
  self.editing = false
  redraw()
end

function Beets:enc(n, d)
  print('Enc ' .. n .. ' ' .. d)
end

function Beets:key(n, z)
  print('Key ' .. n .. ' ' .. z)
end

return Beets
