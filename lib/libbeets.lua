-- TODO:
--
-- highpass filter - requires intelligently switching the wet/dry mix of HP and LP based on which one is in use, or having a priority override
-- grids UI
local Beets = {}
Beets.__index = Beets

local BREAK_OFFSET = 5
local json = include("lib/json")

function Beets.new(softcut_voice_id)
  local i = {
    -- descriptive global state
    id = softcut_voice_id,
    rate = 0,
    beat_count = 8,
    initial_bpm = 0,
    loops_by_filename = {},
    loop_index_to_filename = {},
    break_count = 0,
    editing = false,

    -- state that changes on the beat
    beatstep = 0,
    index = 0,
    played_index = 0,
    message = '',
    status = '',
    muted = false,
    current_bpm = 0,
    beat_start = 0,
    beat_end = 7,
    break_index = 1,

    -- probability values
    probability = {break_index_jump = 0, stutter = 0, reverse = 0, jump = 0, jump_back = 0},
  }

  setmetatable(i, Beets)

  return i
end

function Beets:advance_step(in_beatstep, in_bpm)
  self.message = ''
  self.status = ''
  self.beatstep = in_beatstep
  self.current_bpm = in_bpm

  self.played_index = self.index

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
  return math.random(100) <= self.probability[thing]
end

function Beets:play_slice(slice_index)
  crow.output[1]()
  if self.beatstep == 0 then
    crow.output[2]()
  end

  local loop = self.loops_by_filename[self.loop_index_to_filename[self.break_index]]

  if (self:should('stutter')) then
    self.message = self.message .. 'STUTTER '
    local stutter_amount = math.random(4)
    softcut.loop_start(self.id, loop.start
                         + (slice_index * (loop.duration / self.beat_count)))
    softcut.loop_end(self.id,
                     loop.start
                       + (slice_index * (loop.duration / self.beat_count)
                         + (loop.duration / (64.0 / stutter_amount))))
  else
    softcut.loop_start(self.id, loop.start)
    softcut.loop_end(self.id, loop.start + loop.duration)
  end

  local current_rate = loop.rate * (self.current_bpm / self.initial_bpm)
  if (self:should('reverse')) then
    self.message = self.message .. 'REVERSE '
    softcut.rate(self.id, 0 - current_rate)
  else
    softcut.rate(self.id, current_rate)
  end

  if self.muted then
    softcut.level(self.id, 0)
  else
    softcut.level(self.id, 1)
  end

  local played_break_index
  if (self:should('break_index_jump')) then
    played_break_index = math.random(8) - 1
    self.message = self.message .. 'BREAK '
  else
    played_break_index = self.break_index
  end
  softcut.position(self.id, loop.start
                     + (slice_index * (loop.duration / self.beat_count)))
  if self.muted then
    self.status = self.status .. 'MUTED '
  end
  self.status = self.status .. 'Sample: ' .. played_break_index

  self:notify_beat(loop.beat_types[slice_index+1])
end

function Beets:notify_beat(beat_type)
  if beat_type == 'K' then
    crow.output[3]()
    self.message = self.message .. 'KICK '
  end
  if beat_type == 'S' then
    self.message = self.message .. 'SNARE '
  end
  if beat_type == 'H' then
    self.message = self.message .. 'HAT '
  end
end

function Beets:calculate_next_slice()
  local new_index = self.index + 1
  if new_index > self.beat_end then
    -- self.message = self.message .. "LOOP "
    new_index = self.beat_start
  end

  if (self:should('jump')) then
    self.message = self.message .. '> '
    new_index = (new_index + 1) % self.beat_count
  end

  if (self:should('jump_back')) then
    self.message = self.message .. '< '
    new_index = (new_index - 1) % self.beat_count
  end

  if (self.beatstep == self.beat_count - 1) then
    -- message = message .. "RESET "
    new_index = self.beat_start
  end
  self.index = new_index
end


function Beets:load_loop(index, filename, kicks)
  local loop_info = {}

  local ch, samples, samplerate = audio.file_info(filename)
  loop_info.frames = samples
  loop_info.rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
  loop_info.duration = samples / 48000.0
  loop_info.beat_types = { "-", "-", "-", "-", "-", "-", "-", "-" }
  loop_info.filename = filename
  loop_info.start = index * BREAK_OFFSET
  loop_info.index = index

  softcut.buffer_read_mono(filename, 0, loop_info.start, -1, 1, 1)

  for _, beat in ipairs(kicks) do
    loop_info.beat_types[beat + 1] = "K"
  end

  self.loop_index_to_filename[index] = filename
  self.loops_by_filename[filename] = loop_info
  self.break_count = index

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

function Beets:crow_init()
  crow.output[1].action = 'pulse(0.001, 5, 1)'
  crow.output[2].action = 'pulse(0.001, 5, 1)'
  crow.output[3].action = 'pulse(0.001, 5, 1)'
  crow.ii.pullup(true)
end

function Beets:init(breaks, in_bpm)
  self.initial_bpm = in_bpm
end

function Beets:start()
  self:softcut_init()
  self:crow_init()
end

function Beets:add_params()
  local ControlSpec = require 'controlspec'
  local Formatters = require 'formatters'

  local specs = {}
  specs.FILTER_FREQ = ControlSpec.new(20, 20000, 'exp', 0, 20000, 'Hz')
  specs.FILTER_RESONANCE = ControlSpec.new(0.05, 1, 'lin', 0, 0.25, '')
  specs.PERCENTAGE = ControlSpec.new(0, 1, 'lin', 0.01, 0, '%')
  specs.BEAT_START = ControlSpec.new(0, self.beat_count - 1, 'lin', 1, 0, '')
  specs.BEAT_END =
    ControlSpec.new(0, self.beat_count - 1, 'lin', 1, self.beat_count - 1, '')

  params:add{
    type = 'control',
    id = 'break_index',
    name = 'Sample',
    controlspec = ControlSpec.new(1, self.break_count, 'lin', 1, 1, ''),
    action = function(value)
      self.break_index = value
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
    id = 'break_index_jump_probability',
    name = 'Break Index Jump Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.break_index_jump = value * 100
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
  local horiz_spacing = 10
  local vert_spacing = 10
  local left_margin = 10
  screen.clear()
  screen.level(15)
  for i = 0, 7 do
    screen.rect(left_margin + horiz_spacing * i, 17, horiz_spacing, vert_spacing)
    if self.beatstep == i then
      screen.level(4)
      screen.fill()
    end
    screen.level(2)
    screen.stroke()

    screen.level(15)
    if i == self.beat_start or i == self.beat_end then
      screen.move(left_margin + horiz_spacing * i, 26)
      screen.text('^')
    end
  end
  screen.move(left_margin + horiz_spacing * self.played_index, 20)
  screen.text('+')

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
