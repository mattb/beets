-- passthrough
--
-- library for passing midi
-- from device to an interface
-- + clocking from interface
--
-- for how to use see example
--
-- built with keystep in mind
-- PRs welcome

local Passthrough = {}

local MusicUtil = require "musicutil"
local devices = {}
local midi_device
local midi_interface
local clock_device
local quantize_midi
local scale_names = {}
local current_scale = {}
local midi_notes = {}

function Passthrough.device_event(data)
    local msg = midi.to_msg(data)
    local dev_channel_param = params:get("device_channel")
    local int_channel_param = params:get("interface_channel")

    local int_chan = (int_channel_param == 1 and 1) or int_channel_param - 1

    if dev_channel_param == 1 or (dev_channel_param > 1 and msg.ch == dev_channel_param - 1) then
        local note = msg.note
        if msg.note ~= nil then
            if quantize_midi == true then
                note = MusicUtil.snap_note_to_array(note, current_scale)
            end
        end

        if msg.type == "note_off" then
            midi_interface:note_off(note, 0, int_chan)
        elseif msg.type == "note_on" then
            midi_interface:note_on(note, msg.vel, int_chan)
        elseif msg.type == "key_pressure" then
            midi_interface:key_pressure(note, msg.val, int_chan)
        elseif msg.type == "channel_pressure" then
            midi_interface:channel_pressure(msg.val, int_chan)
        elseif msg.type == "pitchbend" then
            midi_interface:pitchbend(msg.val, int_chan)
        elseif msg.type == "program_change" then
            midi_interface:program_change(msg.val, int_chan)
        elseif msg.type == "cc" then
            midi_interface:cc(msg.cc, msg.val, int_chan)
        end
    end
end

function Passthrough.interface_event(data)
    if clock_device == false then
        return
    else
        local msg = midi.to_msg(data)
        if msg.type == "clock" then
            midi_device:clock()
        elseif msg.type == "start" then
            midi_device:start()
        elseif msg.type == "stop" then
            midi_device:stop()
        elseif msg.type == "continue" then
            midi_device:continue()
        end
    end
end

function Passthrough.build_scale()
    current_scale = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 128)
end

function Passthrough.init()
    for i = 1, #MusicUtil.SCALES do
        table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
    end

    midi_device = midi.connect(1)
    midi_device.event = device_event
    midi_interface = midi.connect(2)
    midi_interface.event = interface_event
    clock_device = false
    quantize_midi = false

    for id, device in pairs(midi.vports) do
        devices[id] = device.name
    end

    params:add_group("PASSTHROUGH", 8)
    params:add {
        type = "option",
        id = "midi_device",
        name = "Device",
        options = devices,
        action = function(value)
            midi_device.event = nil
            midi_device = midi.connect(value)
            midi_device.event = Passthrough.device_event
        end
    }

    params:add {
        type = "option",
        id = "midi_interface",
        name = "Interface",
        options = devices,
        action = function(value)
            midi_interface.event = nil
            midi_interface = midi.connect(value)
            midi_interface.event = Passthrough.interface_event
        end
    }

    local channels = {"all"}
    for i = 1, 16 do
        table.insert(channels, i)
    end
    params:add {type = "option", id = "device_channel", name = "Device channel", options = channels}

    params:add {type = "option", id = "interface_channel", name = "Interface channel", options = channels}

    params:add {
        type = "option",
        id = "clock_device",
        name = "Clock device",
        options = {"no", "yes"},
        action = function(value)
            clock_device = value == 2
            if value == 1 then
                midi_device:stop()
            end
        end
    }

    params:add {
        type = "option",
        id = "quantize_midi",
        name = "Quantize",
        options = {"no", "yes"},
        action = function(value)
            quantize_midi = value == 2
            Passthrough.build_scale()
        end
    }

    params:add {
        type = "option",
        id = "scale_mode",
        name = "Scale",
        options = scale_names,
        default = 5,
        action = function()
            Passthrough.build_scale()
        end
    }

    params:add {
        type = "number",
        id = "root_note",
        name = "Root",
        min = 0,
        max = 11,
        default = 0,
        formatter = function(param)
            return MusicUtil.note_num_to_name(param:get())
        end,
        action = function()
            Passthrough.build_scale()
        end
    }
end

return Passthrough
