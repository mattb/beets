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
local initial_bpm = 0
local kickbeats = {}

local specs = {}
specs.FILTER_FREQ = ControlSpec.new(0, 20000, "exp", 0, 20000, "Hz")
specs.FILTER_RESONANCE = ControlSpec.new(0, 1, "lin", 0, 0.25, "")
specs.PERCENTAGE = ControlSpec.new(0, 1, "lin", 0.01, 0, "%")
specs.BEAT_START = ControlSpec.new(0, beat_count - 1, "lin", 1, 0, "")
specs.BEAT_END = ControlSpec.new(0, beat_count - 1, "lin", 1, beat_count - 1, "")

beats.advance_step = function(in_beatstep, in_bpm)
  message = ""

  local current_rate = rate * (in_bpm / initial_bpm)
  beatstep = in_beatstep
  crow.output[1]()
  if beatstep == 1 then
    crow.output[2]()
  end

  if(math.random(100) < stutter_probability) then
    message = message .. " STUTTER"
    stutter_amount = math.random(4)
    softcut.loop_start(1, index * (duration / beat_count))
    softcut.loop_end(1, index * (duration / beat_count) + (duration / (64.0 / stutter_amount)))
  else
    softcut.loop_start(1,0)
    softcut.loop_end(1,duration)
  end

  if kickbeats[index] == 1 then
    crow.output[3]()
    message = message .. " KICK"
  end

  softcut.position(1, index * (duration / beat_count))

  if(math.random(100) < reverse_probability) then
    message = message .. " REVERSE"
    softcut.rate(1, 0-current_rate)
  else
    softcut.rate(1, current_rate)
  end

  index = index + 1
  if index > beat_end then
    message = message .. " LOOP"
    index = beat_start
  end

  if(math.random(100) < jump_probability) then
    message = message .. " JUMP"
    index = (index + 1) % 8
  end

  if(math.random(100) < jump_back_probability) then
    message = message .. " JUMP BACK"
    index = (index - 1) % 8
  end

  if(beatstep == beat_count - 1) then
    message = message .. " RESET"
    index = beat_start
  end

  redraw()
end

beats.init = function(in_file, in_bpm, in_kickbeats)
  kickbeats = {}
  for i, beat in ipairs(in_kickbeats) do
    kickbeats[beat] = 1
  end

  initial_bpm = in_bpm
  local ch, samples, samplerate = audio.file_info(in_file)
  frames = samples
  rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
  duration = samples / 48000.0
  print("Frames: " .. frames .. " Rate: " .. rate .. " Duration: " .. duration)

  softcut.buffer_read_mono(in_file,0,0,-1,1,1)
  
  softcut.enable(1,1)
  softcut.buffer(1,1)
  softcut.level(1,0.1)
  softcut.loop(1,1)
  softcut.loop_start(1,0)
  softcut.loop_end(1,duration)
  softcut.position(1,0)
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
      softcut.post_filter_fc(1, value)
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
