local Beets = {}
Beets.__index = Beets

local ControlSpec = require 'controlspec'
local Formatters = require 'formatters'

local BREAK_OFFSET = 5
local VOICE_OFFSET = 100
local EVENT_ORDER = {'<', '>', 'R', 'S', 'B'}
local PROBABILITY_ORDER = {
  'jump_back',
  'jump',
  'reverse',
  'stutter',
  'loop_index_jump'
}
local json = include('lib/json')
local inspect = include('lib/inspect')

function Beets.new(options)
  local softcut_voice_id = options.softcut_voice_id or 1
  local i = {
    -- descriptive global state
    debug = false,
    running = false,
    enable_mutations = true,
    id = softcut_voice_id,
    beat_count = 8,
    loops_by_filename = {},
    loop_index_to_filename = {},
    loop_count = 0,
    editing = false,
    editing_mode = {cursor_location = 0},
    amplitude = 1,
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
    on_beat_one = function()
    end,
    on_beat = function()
    end,
    on_kick = function()
    end,
    on_snare = function()
    end,
    -- probability values
    probability = {
      loop_index_jump = 0,
      stutter = 0,
      reverse = 0,
      jump = 0,
      jump_back = 0
    },
    ui = {slice_buttons_down = {}, mute_button = 0, shift_button = 0}
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

  if not self.running then
    self.status = 'NOT RUNNING'
    return
  end

  if self.loop_count == 0 then
    self.status = 'LOAD LOOPS IN PARAMS'
    return
  end

  if self.muted then
    self.status = 'MUTED'
    softcut.level(self.id, 0)
  else
    softcut.level(self.id, self.amplitude)
  end

  if self.editing then
    -- play the current edit position slice every other beat
    -- so that it's easier to hear what the sound is at the start of the slice
    if self.beatstep % 4 ~= 0 then
      self:play_nothing()
    else
      local edit_index = math.floor(self.editing_mode.cursor_location)
      self:play_slice(edit_index)
    end
    return
  end
  if self.beatstep == 0 then
    self.on_beat_one()
  end
  self:calculate_next_slice()
  self:play_slice(self.index)
  self.played_index = self.index
end

function Beets:instant_toggle_mute()
  self:toggle_mute()
  if self.muted then
    softcut.level(self.id, 0)
  else
    softcut.level(self.id, self.amplitude)
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

function Beets:play_nothing()
  softcut.level(self.id, 0)
end

function Beets:random_loop_index()
  local timeout = self.loop_count
  local l = math.random(self.loop_count)
  while timeout > 0 do
    local loop = self:loop_at_index(l)
    if loop.enabled == 1 then
      return l
    end
    l = l + 1
    if l > self.loop_count then
      l = 1
    end
  end
  return 1
end

function Beets:play_slice(slice_index)
  if (self:should('loop_index_jump')) then
    params:set(self.id .. '_' .. 'loop_index', self:random_loop_index())
    self.events['B'] = 1
  else
    self.events['B'] = 0
  end
  self.played_loop_index = self.loop_index

  local loop = self:loop_at_index(self.played_loop_index)
  local current_rate = loop.rate * (self.current_bpm / loop.bpm)

  if (self:should('stutter')) then
    self.events['S'] = 1
    local stutter_amount = math.random(4)
    softcut.loop_start(self.id, loop.start + (slice_index * (loop.duration / self.beat_count)))
    softcut.loop_end(
      self.id,
      loop.start + (slice_index * (loop.duration / self.beat_count) + (loop.duration / (64.0 / stutter_amount)))
    )
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

  local position = loop.start + (slice_index * (loop.duration / self.beat_count))
  softcut.position(self.id, position)

  if not self.editing then
    self:notify_beat(loop.beat_types[slice_index + 1])
  end
end

function Beets:notify_beat(beat_type)
  if beat_type == 'K' then
    self.on_kick()
  end
  if beat_type == 'S' then
    self.on_snare()
  end
end

function Beets:toggle_loop_enabled(index)
  local loop = self:loop_at_index(index)
  if loop.enabled == 1 then
    loop.enabled = 0
  elseif loop.enabled == 0 then
    loop.enabled = 1
  end
end

function Beets:toggle_slice_enabled(slice_index)
  local loop = self:loop_at_index(self.loop_index)
  if loop.beat_enabled[slice_index + 1] == 1 then
    loop.beat_enabled[slice_index + 1] = 0
  elseif loop.beat_enabled[slice_index + 1] == 0 then
    loop.beat_enabled[slice_index + 1] = 1
  end
end

function Beets:slice_is_enabled(slice_index)
  local loop = self:loop_at_index(self.loop_index)
  return loop.beat_enabled[slice_index + 1] == 1
end

function Beets:next_loop(loop_index, direction)
  local new_index = loop_index
  local timeout = self.loop_count
  while timeout > 0 do
    new_index = new_index + direction

    if new_index == 0 then
      new_index = self.loop_count
    end
    if new_index > self.loop_count then
      new_index = 1
    end

    local loop = self:loop_at_index(new_index)
    if loop.enabled == 1 then
      return new_index
    end
    timeout = timeout - 1
  end
end

function Beets:step_forward(index)
  local timeout = self.beat_count
  local new_index = index
  while timeout > 0 do
    new_index = new_index + 1
    if new_index > self.beat_end then
      new_index = self.beat_start
      if params:get(self.id .. '_' .. 'auto_advance') == 2 then
        self.loop_index = self:next_loop(self.loop_index, 1)
      end
    end
    if self:slice_is_enabled(new_index) then
      return new_index
    end
    timeout = timeout - 1
  end
  return 0
end

function Beets:step_backward(index)
  local timeout = self.beat_count
  local new_index = index
  while timeout > 0 do
    new_index = new_index - 1
    if new_index < self.beat_start then
      new_index = self.beat_end
      if params:get(self.id .. '_' .. 'auto_advance') == 2 then
        self.loop_index = self:next_loop(self.loop_index, -1)
      end
    end
    if self:slice_is_enabled(new_index) then
      return new_index
    end
    timeout = timeout - 1
  end
  return 0
end

function Beets:step_first()
  local new_index = self.beat_start
  if self:slice_is_enabled(new_index) then
    return new_index
  end
  return self:step_forward(new_index)
end

function Beets:calculate_next_slice()
  local new_index = self:step_forward(self.index)

  if (self:should('jump')) then
    self.events['>'] = 1
    new_index = self:step_forward(new_index)
  else
    self.events['>'] = 0
  end

  if (self:should('jump_back')) then
    self.events['<'] = 1
    new_index = self:step_backward(new_index)
  else
    self.events['<'] = 0
  end

  if (self.beatstep == 0) then
    new_index = self:step_first()
  end
  self.index = new_index
end

function Beets:clear_loops()
  self.loop_index_to_filename = {}
  self.loops_by_filename = {}
  self.loop_count = 0
end

function Beets:load_directory(path)
  self:clear_loops()

  local f = io.popen('ls "' .. path .. '"/*.wav')
  local filenames = {}
  for name in f:lines() do
    table.insert(filenames, name)
  end
  table.sort(filenames)

  for i, name in ipairs(filenames) do
    self:load_loop(i, {file = name})
    i = i + 1
  end
end

function Beets:save_loop_info(loop_info)
  local json_filename = loop_info.filename .. '.json'

  local f = io.open(json_filename, 'w')
  f:write(json.encode(loop_info))
  f:close()
end

function Beets:load_loop(index, loop)
  local filename = loop.file
  local kicks = loop.kicks
  local snares = loop.snares
  local loop_info = {}
  local json_filename = filename .. '.json'

  local f = io.open(json_filename)
  if f ~= nil then
    loop_info = json.decode(f:read('*a'))
  else
    local ch, samples, samplerate = audio.file_info(filename)
    loop_info.frames = samples
    loop_info.rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
    loop_info.duration = samples / 48000.0
    loop_info.beat_types = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '}
    loop_info.filename = filename

    if kicks then
      for _, beat in ipairs(kicks) do
        loop_info.beat_types[beat + 1] = 'K'
      end
    end

    if snares then
      for _, beat in ipairs(snares) do
        loop_info.beat_types[beat + 1] = 'S'
      end
    end

    self:save_loop_info(loop_info)
  end

  loop_info.bpm = (4 * 60) / loop_info.duration
  loop_info.start = index * BREAK_OFFSET + self.id * VOICE_OFFSET
  loop_info.index = index
  loop_info.enabled = 1
  loop_info.beat_enabled = {1, 1, 1, 1, 1, 1, 1, 1}

  softcut.buffer_read_mono(filename, 0, loop_info.start, -1, 1, 1)

  self.loop_index_to_filename[index] = filename
  self.loops_by_filename[filename] = loop_info
  self.loop_count = index
  self:reset_loop_index_param()
end

function Beets:softcut_init()
  softcut.enable(self.id, 1)
  softcut.buffer(self.id, 1)
  softcut.level(self.id, self.amplitude)
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

function Beets:start()
  self:softcut_init()
  self.running = true
end

function Beets:stop()
  self.running = false
  softcut.play(self.id, 0)
end

function Beets:reset_loop_index_param()
  for _, p in ipairs(params.params) do
    if p.id == self.id .. '_' .. 'loop_index' then
      p.controlspec = ControlSpec.new(1, self.loop_count, 'lin', 1, 1, '')
    end
  end
end

function Beets:add_params(arcify)
  local specs = {}
  specs.AMP = ControlSpec.new(0, 1, 'lin', 0, 1, '')
  specs.FILTER_FREQ = ControlSpec.new(20, 20000, 'exp', 0, 20000, 'Hz')
  specs.FILTER_RESONANCE = ControlSpec.new(0.05, 1, 'lin', 0, 0.25, '')
  specs.PERCENTAGE = ControlSpec.new(0, 1, 'lin', 0.01, 0, '%')
  specs.BEAT_START = ControlSpec.new(0, self.beat_count - 1, 'lin', 1, 0, '')
  specs.BEAT_END = ControlSpec.new(0, self.beat_count - 1, 'lin', 1, self.beat_count - 1, '')

  local files = {}
  local files_count = 0
  local loops_dir = _path.audio .. 'beets/'
  local f = io.popen('cd ' .. loops_dir .. '; ls -d *')
  for name in f:lines() do
    table.insert(files, name)
    files_count = files_count + 1
  end
  table.sort(files)

  local name
  if files_count == 0 then
    name = 'Create folders in audio/beets to load'
    self.loops_folder_name = '-'
  else
    name = 'Loops folder'
    self.loops_folder_name = files[1]
  end

  params:add_group('Voice ' .. self.id, 16)

  params:add {
    type = 'option',
    id = self.id .. '_' .. 'dir_chooser',
    name = name,
    options = files,
    action = function(value)
      self.loops_folder_name = files[value]
    end
  }

  params:add {
    type = 'trigger',
    id = self.id .. '_' .. 'load_loops',
    name = 'Load loops',
    action = function(value)
      if value == '-' then
        return
      end
      self:load_directory(_path.audio .. 'beets/' .. self.loops_folder_name)
    end
  }

  params:add_separator()

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'amplitude',
    name = 'Amplitude',
    controlspec = specs.AMP,
    default = 1.0,
    action = function(value)
      self.amplitude = value
      softcut.level(self.id, self.amplitude)
    end
  }
  arcify:register(self.id .. '_' .. 'amplitude')

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'pan',
    name = 'Pan',
    controlspec = ControlSpec.PAN,
    formatter = Formatters.bipolar_as_pan_widget,
    default = 0.5,
    action = function(value)
      self.pan = value
      softcut.pan(self.id, self.pan)
    end
  }
  arcify:register(self.id .. '_' .. 'pan')

  params:add {
    type = 'option',
    id = self.id .. '_' .. 'auto_advance',
    name = 'Auto-advance loop',
    options = {'off', 'on'}
  }

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'loop_index',
    name = 'Sample',
    controlspec = ControlSpec.new(1, self.loop_count, 'lin', 1, 1, ''),
    action = function(value)
      self.loop_index = value
      self:loop_at_index(self.loop_index).enabled = 1
    end
  }
  arcify:register(self.id .. '_' .. 'loop_index', 0.05)

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'jump_back_probability',
    name = 'Jump Back Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.jump_back = value * 100
    end
  }
  arcify:register(self.id .. '_' .. 'jump_back_probability')

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'jump_probability',
    name = 'Jump Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.jump = value * 100
    end
  }
  arcify:register(self.id .. '_' .. 'jump_probability')

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'reverse_probability',
    name = 'Reverse Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.reverse = value * 100
    end
  }
  arcify:register(self.id .. '_' .. 'reverse_probability')

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'stutter_probability',
    name = 'Stutter Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.stutter = value * 100
    end
  }
  arcify:register(self.id .. '_' .. 'stutter_probability')

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'loop_index_jump_probability',
    name = 'Loop Jump Probability',
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.probability.loop_index_jump = value * 100
    end
  }
  arcify:register(self.id .. '_' .. 'loop_index_jump_probability')

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'filter_frequency',
    name = 'Filter Cutoff',
    controlspec = specs.FILTER_FREQ,
    formatter = Formatters.format_freq,
    action = function(value)
      softcut.post_filter_fc(self.id, value)
    end
  }
  arcify:register(self.id .. '_' .. 'filter_frequency', 10.0)

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'filter_reso',
    name = 'Filter Resonance',
    controlspec = specs.FILTER_RESONANCE,
    action = function(value)
      softcut.post_filter_rq(self.id, value)
    end
  }
  arcify:register(self.id .. '_' .. 'filter_reso', 0.1)

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'beat_start',
    name = 'Beat Start',
    controlspec = specs.BEAT_START,
    action = function(value)
      self.beat_start = value
    end
  }
  arcify:register(self.id .. '_' .. 'beat_start', 0.05)

  params:add {
    type = 'control',
    id = self.id .. '_' .. 'beat_end',
    name = 'Beat End',
    controlspec = specs.BEAT_END,
    action = function(value)
      self.beat_end = value
    end
  }
  arcify:register(self.id .. '_' .. 'beat_end', 0.05)
end

local layout = {
  horiz_spacing = 9,
  vert_spacing = 9,
  left_margin = 10,
  top_margin = 10
}

function Beets:_drawCurrentLoopGrid(options)
  local played_index = options.played_index or self.played_index
  local beatstep = options.beatstep or self.beatstep
  local loop_index = options.loop_index or self.loop_index

  local loop = self.loops_by_filename[self.loop_index_to_filename[loop_index]]
  for i = 0, 7 do
    screen.rect(
      layout.left_margin + layout.horiz_spacing * i,
      layout.top_margin,
      layout.horiz_spacing,
      layout.vert_spacing
    )
    if played_index == i then
      screen.level(15)
    elseif beatstep == i then
      screen.level(2)
    else
      screen.level(0)
    end
    screen.fill()
    screen.rect(
      layout.left_margin + layout.horiz_spacing * i,
      layout.top_margin,
      layout.horiz_spacing,
      layout.vert_spacing
    )

    screen.level(1)
    screen.move(layout.left_margin + layout.horiz_spacing * i + 2, layout.top_margin + 6)
    screen.text(loop.beat_types[i + 1])

    screen.level(2)
    screen.stroke()

    screen.level(15)
  end
end

function Beets:grid_key(x, y, z)
  if self.loop_count == 0 or self.editing then
    return
  end
  if x == 8 and y == 8 then
    self.ui.mute_button = z
    if z == 0 then
      self:toggle_mute()
    end
    redraw()
  end
  if x == 1 and y == 3 then
    self.ui.shift_button = z
    redraw()
  end
  if z == 1 and x == 8 and y == 3 then -- auto_advance
    local current_auto_advance = params:get(self.id .. '_' .. 'auto_advance')
    if current_auto_advance == 1 then
      params:set(self.id .. '_' .. 'auto_advance', 2)
    else
      params:set(self.id .. '_' .. 'auto_advance', 1)
    end
  end
  if y == 1 and x <= self.beat_count then
    if self.ui.shift_button == 1 then
      if z == 1 then
        self:toggle_slice_enabled(x - 1)
      end
    elseif z == 1 then
      self.ui.slice_buttons_down[x] = 1
      local count = 0
      local first, second
      for button_down in pairs(self.ui.slice_buttons_down) do
        if first == nil then
          first = button_down
        else
          if button_down > first then
            second = button_down
          else
            second = first
            first = button_down
          end
        end
        count = count + 1
      end
      if count == 1 then -- for double-tap single-button-loop handling
        if self.ui.slice_button_saved then
          if self.ui.slice_button_saved == x then
            -- DOUBLE TAP!
            params:set(self.id .. '_' .. 'beat_start', x - 1)
            params:set(self.id .. '_' .. 'beat_end', x - 1)
          end
          self.ui.slice_button_saved = nil
        else
          self.ui.slice_button_saved = x
        end
      else
        self.ui.slice_button_saved = nil
      end
      if count == 2 then
        params:set(self.id .. '_' .. 'beat_start', first - 1)
        params:set(self.id .. '_' .. 'beat_end', second - 1)
      end
    else
      if self.ui.slice_button_saved then
        local count = 0
        for _ in pairs(self.ui.slice_buttons_down) do
          count = count + 1
        end
        if count ~= 1 then
          self.ui.slice_button_saved = nil
        end
      end
      self.ui.slice_buttons_down[x] = nil
    end
  end

  if y == 2 and x <= self.loop_count then
    if self.ui.shift_button == 1 then
      if z == 1 and x ~= self.loop_index then
        self:toggle_loop_enabled(x)
      end
    elseif z == 1 then
      params:set(self.id .. '_' .. 'loop_index', x)
    end
  end

  local c = 0
  for _ in pairs(PROBABILITY_ORDER) do
    c = c + 1
  end
  if x <= c and y > 3 and z == 1 then
    local name = PROBABILITY_ORDER[x]
    local value = (8 - y) / 4
    params:set(self.id .. '_' .. name .. '_probability', value)
  end
end

function Beets:drawGridUI(g, top_x, top_y)
  if self.loop_count == 0 then
    return
  end

  -- auto-advance
  if params:get(self.id .. '_' .. 'auto_advance') == 2 then
    g:led(top_x + 7, top_y + 2, 15)
  else
    g:led(top_x + 7, top_y + 2, 4)
  end

  -- shift
  if self.ui.shift_button == 1 then
    g:led(top_x + 0, top_y + 2, 15)
  else
    g:led(top_x + 0, top_y + 2, 4)
  end

  local mute_brightness = 4
  if self.ui.mute_button == 1 then
    mute_brightness = 15
  else
    if self.muted then
      mute_brightness = 12
    end
  end
  g:led(top_x + 7, top_y + 7, mute_brightness)

  -- beat (0-based)
  for i = 0, self.beat_count - 1 do
    if self:slice_is_enabled(i) then
      if i == self.played_index then
        g:led(top_x + i, top_y, 15)
      elseif i >= self.beat_start and i <= self.beat_end then
        g:led(top_x + i, top_y, 6)
      else
        g:led(top_x + i, top_y, 3)
      end
    else
      g:led(top_x + i, top_y, 1)
    end
  end

  -- loop index (1-based)
  for i = 0, math.min(7, self.loop_count - 1) do
    if i == self.loop_index - 1 then
      g:led(top_x + i, top_y + 1, 15)
    elseif self:loop_at_index(i + 1).enabled == 1 then
      g:led(top_x + i, top_y + 1, 3)
    else
      g:led(top_x + i, top_y + 1, 1)
    end
  end

  local stripe_min = 5
  local inter_stripe_diff = 1
  for x, name in ipairs(PROBABILITY_ORDER) do
    local value = self.probability[name]
    range = 5
    local scaled_value = value / 100 * range
    local stripe_mod = inter_stripe_diff * (x % 2)
    for i = 1, range do
      local y = 8 - i
      local brightness
      if scaled_value > i then
        brightness = 15 - stripe_mod
      elseif scaled_value > i - 1 then
        brightness = (15 - stripe_min - stripe_mod) * (scaled_value - (i - 1)) + stripe_mod + stripe_min
      else
        brightness = stripe_mod + stripe_min
      end
      g:led(top_x + x - 1, top_y + y, math.floor(brightness))
    end
  end
end

function Beets:drawDebugUI()
  screen.clear()
  screen.level(15)
  for i, k in ipairs({'beatstep', 'index'}) do
    screen.move(0, 7 * i)
    screen.text(k .. ': ' .. self[k])
  end
end

function Beets:drawPlaybackUI()
  screen.clear()
  screen.level(15)

  if self.loop_count > 0 then
    self:_drawCurrentLoopGrid {}

    -- draw loop start/end
    screen.level(6)
    screen.move(
      layout.left_margin + self.beat_start * layout.horiz_spacing,
      layout.top_margin + layout.vert_spacing + 2
    )
    screen.line(
      layout.left_margin + self.beat_start * layout.horiz_spacing,
      layout.top_margin + layout.vert_spacing + 6
    )
    screen.line(
      layout.left_margin + (self.beat_end + 1) * layout.horiz_spacing,
      layout.top_margin + layout.vert_spacing + 6
    )
    screen.line(
      layout.left_margin + (self.beat_end + 1) * layout.horiz_spacing,
      layout.top_margin + layout.vert_spacing + 2
    )
    screen.stroke()

    -- draw event indicators
    screen.level(15)
    screen.move(layout.left_margin + self.beat_count * layout.horiz_spacing + 30, layout.top_margin)
    screen.text(self.played_loop_index)
    for y, e in ipairs(EVENT_ORDER) do
      screen.move(
        layout.left_margin + self.beat_count * layout.horiz_spacing + 30,
        layout.top_margin + layout.vert_spacing * y
      )
      if self.events[e] == 1 then
        screen.level(15)
      else
        screen.level(1)
      end
      screen.text(e)
    end
  end

  screen.level(15)
  screen.move(layout.left_margin, 40)
  screen.text(self.message)
  screen.move(layout.left_margin, 50)
  screen.text(self.status)
end

function Beets:drawEditingUI()
  if self.loop_count > 0 then
    self:_drawCurrentLoopGrid {
      played_index = math.floor(self.editing_mode.cursor_location),
      beatstep = math.floor(self.editing_mode.cursor_location)
    }
  end
  screen.move(layout.left_margin, 50)
  screen.text('EDIT MODE')
end

function Beets:drawUI()
  screen.clear()
  screen.level(15)

  if self.debug then
    self:drawDebugUI()
  elseif self.editing then
    self:drawEditingUI()
  else
    self:drawPlaybackUI()
  end

  screen.update()
end

function Beets:edit_mode_begin()
  self.editing = true
  self.enable_mutations = false
  redraw()
end

function Beets:loop_at_index(index)
  return self.loops_by_filename[self.loop_index_to_filename[index]]
end

function Beets:edit_mode_end()
  self.editing = false
  self.enable_mutations = true
  local loop = self:loop_at_index(self.loop_index)
  self:save_loop_info(loop)
  redraw()
end

function Beets:enc(n, d)
  if n == 1 then
    self.editing_mode.cursor_location = (self.editing_mode.cursor_location + (d / 50.0)) % self.beat_count
    redraw()
  else
  end
end

function Beets:key(n, z)
  if n == 2 and z == 0 then
    local beat_types_index = math.floor(self.editing_mode.cursor_location) + 1
    local loop = self:loop_at_index(self.loop_index)
    if loop.beat_types[beat_types_index] == ' ' then
      loop.beat_types[beat_types_index] = 'K'
    elseif loop.beat_types[beat_types_index] == 'K' then
      loop.beat_types[beat_types_index] = 'S'
    elseif loop.beat_types[beat_types_index] == 'S' then
      loop.beat_types[beat_types_index] = ' '
    end
    redraw()
  else
    print('Key ' .. n .. ' ' .. z)
  end
end

return Beets
