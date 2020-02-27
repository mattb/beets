local beats = {}

local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local specs = {}
specs.FILTER_FREQ = ControlSpec.new(1000, 20000, "exp", 0, 20000, "Hz")
specs.FILTER_RESONANCE = ControlSpec.new(0, 1, "lin", 0, 0, "")
specs.PERCENTAGE = ControlSpec.new(0, 1, "lin", 0.01, 0, "%")

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

beats.advance_step = function(in_beatstep)
  beatstep = in_beatstep
  crow.output[1]()
  if beatstep == 1 then
    crow.output[2]()
  end
  message = ""
  if(math.random(100) < stutter_probability) then
    message = "STUTTER"
    stutter_amount = math.random(4)
    softcut.loop_start(1, index * (duration / 8.0))
    softcut.loop_end(1, index * (duration / 8.0) + (duration / (64.0 / stutter_amount)))
  else
    softcut.loop_start(1,0)
    softcut.loop_end(1,duration)
  end
  softcut.position(1, index * (duration / 8.0))

  if(math.random(100) < reverse_probability) then
    message = message .. " REVERSE"
    softcut.rate(1, 0-rate)
  else
    softcut.rate(1, rate)
  end

  index = (index + 1) % 8

  if(math.random(100) < jump_probability) then
    message = message .. "JUMP"
    index = (index + 1) % 8
  end

  if(math.random(100) < jump_back_probability) then
    message = message .. "JUMP BACK"
    index = (index - 1) % 8
  end

  if(beatstep == 0) then
    message = message .. "RESET"
    index = 0
  end
  beats.redraw()
end

local function redraw()
  screen.clear()
  screen.level(15)
  screen.move(10 + 10 * beatstep, 20)
  screen.text("|")
  screen.move(10 + 10 * index, 30)
  screen.text("|")
  screen.move(10, 40)
  screen.text(message)
  screen.update()
end

beats.init = function(file)
  local ch, samples, samplerate = audio.file_info(file)
  frames = samples
  rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
  duration = samples / 48000.0
  print("Frames: " .. frames .. " Rate: " .. rate .. " Duration: " .. duration)

  softcut.buffer_read_mono(file,0,0,-1,1,1)
  
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
end

return beats
