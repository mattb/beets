-- TODO:
--
-- load multiple breaks - lay them out on the softcut tape at fixed intervals (e.g. 10 seconds) to make the position calculation easy
-- switch between breaks explicitly
-- random probability of switching between breaks (RESET resets to explicit choice)
-- highpass filter - requires intelligently switching the wet/dry mix of HP and LP based on which one is in use, or having a priority override

local beats = {}

local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local frames
local duration
local rate
local index = 0
local message = "..."
local beatstep = 0

local stutter_probability = 0
local reverse_probability = 0
local jump_probability = 0
local jump_back_probability = 0
local beat_start = 0
local beat_end = 7
local beat_count = 8

local muted = false
local initial_bpm = 0
local current_bpm = 0
local kickbeats = {}
local break_index = 1
local break_offset = 5
local break_count = 0

local specs = {}
specs.FILTER_FREQ = ControlSpec.new(0, 20000, "exp", 0, 20000, "Hz")
specs.FILTER_RESONANCE = ControlSpec.new(0.05, 1, "lin", 0, 0.25, "")
specs.PERCENTAGE = ControlSpec.new(0, 1, "lin", 0.01, 0, "%")
specs.BEAT_START = ControlSpec.new(0, beat_count - 1, "lin", 1, 0, "")
specs.BEAT_END = ControlSpec.new(0, beat_count - 1, "lin", 1, beat_count - 1, "")

beats.advance_step = function(in_beatstep, in_bpm)
  message = ""
  beatstep = in_beatstep
  current_bpm = in_bpm

  beats.play_slice(index)
  index = beats.calculate_next_slice(index)
  redraw()
end

beats.instant_mute = function(in_muted)
  beats.mute(in_muted)
  if muted then
    softcut.level(1,0)
  else
    softcut.level(1,1)
  end
end

beats.mute = function(in_muted)
  if in_muted then
    muted = true
  else
    muted = false
  end
end

beats.toggle_mute = function()
  beats.mute(not muted)
end

beats.play_slice = function(slice_index) 
  crow.output[1]()
  if beatstep == 0 then
    crow.output[2]()
  end

  if kickbeats[break_index][slice_index] == 1 then
    crow.output[3]()
    message = message .. " KICK"
  end

  if(math.random(100) < stutter_probability) then
    message = message .. " STUTTER"
    stutter_amount = math.random(4)
    softcut.loop_start(1, break_index * break_offset + (slice_index * (duration / beat_count)))
    softcut.loop_end(1, break_index * break_offset + (slice_index * (duration / beat_count) + (duration / (64.0 / stutter_amount))))
  else
    softcut.loop_start(1, break_index * break_offset)
    softcut.loop_end(1, break_index * break_offset + duration)
  end

  local current_rate = rate * (current_bpm / initial_bpm)
  if(math.random(100) < reverse_probability) then
    message = message .. " REVERSE"
    softcut.rate(1, 0-current_rate)
  else
    softcut.rate(1, current_rate)
  end

  if muted then
    softcut.level(1,0)
  else
    softcut.level(1,1)
  end

  softcut.position(1, break_index * break_offset + (slice_index * (duration / beat_count)))
end

beats.calculate_next_slice = function(current_index) 
  local new_index = current_index + 1
  if new_index > beat_end then
    message = message .. " LOOP"
    new_index = beat_start
  end

  if(math.random(100) < jump_probability) then
    message = message .. " JUMP"
    new_index = (new_index + 1) % beat_count
  end

  if(math.random(100) < jump_back_probability) then
    message = message .. " JUMP BACK"
    new_index = (new_index - 1) % beat_count
  end

  if(beatstep == beat_count - 1) then
    message = message .. " RESET"
    new_index = beat_start
  end
  return new_index
end

beats.init = function(breaks, in_bpm)
  kickbeats = {}

  initial_bpm = in_bpm
  local first_file = breaks[1].file
  local ch, samples, samplerate = audio.file_info(first_file) -- take all the settings from the first file for now
  frames = samples
  rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
  duration = samples / 48000.0
  print("Frames: " .. frames .. " Rate: " .. rate .. " Duration: " .. duration)

  for i, brk in ipairs(breaks) do
    softcut.buffer_read_mono(brk.file, 0, i * break_offset, -1, 1, 1)
    kickbeats[i] = {}
    for _, beat in ipairs(brk.kicks) do
      kickbeats[i][beat] = 1
    end
    break_count = i
  end
  
  softcut.enable(1,1)
  softcut.buffer(1,1)
  softcut.level(1,1)
  softcut.level_slew_time(1, 0.2)
  softcut.loop(1,1)
  softcut.loop_start(1, break_index * break_offset)
  softcut.loop_end(1, break_index * break_offset + duration)
  softcut.position(1, break_index * break_offset)
  softcut.rate(1,rate)
  softcut.play(1,1)
  softcut.fade_time(1, 0.005)

  softcut.post_filter_dry(1,0.0)
  softcut.post_filter_lp(1,1.0)
  softcut.post_filter_rq(1,0.3)
  softcut.post_filter_fc(1,44100)

  crow.output[1].action = "pulse(0.001, 5, 1)"
  crow.output[2].action = "pulse(0.001, 5, 1)"
  crow.output[3].action = "pulse(0.001, 5, 1)"
end

beats.add_params = function()
  params:add{type = "control", 
    id = "break_index",
    name="Sample",
    controlspec = ControlSpec.new(1, break_count, "lin", 1, 1, ""),
    action = function(value)
      break_index = value
    end}

  params:add{type = "control", 
    id = "jump_back_probability",
    name="Jump Back Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      jump_back_probability = value * 100
    end}

  params:add{type = "control", 
    id = "jump_probability",
    name="Jump Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      jump_probability = value * 100
    end}

  params:add{type = "control", 
    id = "reverse_probability",
    name="Reverse Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      reverse_probability = value * 100
    end}

  params:add{type = "control", 
    id = "stutter_probability",
    name="Stutter Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      stutter_probability = value * 100
    end}

  params:add{type = "control", 
    id = "filter_freq",
    name="Filter Cutoff",
    controlspec = specs.FILTER_FREQ,
    formatter = Formatters.format_freq,
    action = function(value)
      -- TODO: seems to be crashing the audio engine right now
      -- softcut.post_filter_fc(1, value) 
    end}

  params:add{type = "control", 
    id = "filter_res",
    name="Filter Resonance",
    controlspec = specs.FILTER_RESONANCE,
    action = function(value)
      softcut.post_filter_rq(1, value)
    end}

  params:add{type = "control", 
    id = "beat_start",
    name = "Beat Start",
    controlspec = specs.BEAT_START,
    action = function(value)
      beat_start = value
    end}

  params:add{type = "control", 
    id = "beat_end",
    name = "Beat End",
    controlspec = specs.BEAT_END,
    action = function(value)
      beat_end = value
    end}
end

function beats:redraw()
  screen.clear()
  screen.level(15)
  screen.move(10 + 10 * beatstep, 20)
  screen.text("|")
  screen.move(10 + 10 * index, 20)
  screen.text("-")
  screen.move(10, 40)
  screen.text(message)
  screen.update()
end

return beats
