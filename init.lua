local modpath = core.get_modpath("kinetica")

kinetica = {}

kinetica.directions = {
    {x = 1,  y = 0,  z = 0},
    {x = -1, y = 0,  z = 0},
    {x = 0,  y = 1,  z = 0},
    {x = 0,  y = -1, z = 0},
    {x = 0,  y = 0,  z = 1},
    {x = 0,  y = 0,  z = -1},
}

function kinetica.make_axle_overlay(bg_texture, reverse_order)
local axle_tex = "kinetica_shaft_connecting_overlay.png"

local base_strip = "[combine:16x64" ..
":0,0=" .. bg_texture ..
":0,16=" .. bg_texture ..
":0,32=" .. bg_texture ..
":0,48=" .. bg_texture

local final_tex = base_strip .. "^" .. axle_tex

if reverse_order then
    final_tex = "[combine:16x64" ..
    ":0,0=("  .. base_strip .. "\\^[sheet\\:1x4\\:0,0)^(" .. axle_tex .. "\\^[sheet\\:1x4\\:0,0)" ..
    ":0,16=("  .. base_strip .. "\\^[sheet\\:1x4\\:0,0)^(" .. axle_tex .. "\\^[sheet\\:1x4\\:0,3)" ..
    ":0,32=("  .. base_strip .. "\\^[sheet\\:1x4\\:0,0)^(" .. axle_tex .. "\\^[sheet\\:1x4\\:0,2)" ..
    ":0,48=("  .. base_strip .. "\\^[sheet\\:1x4\\:0,0)^(" .. axle_tex .. "\\^[sheet\\:1x4\\:0,1)"
    end

    return {
        name = final_tex,
        animation = {
            type = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length = 0.4,
        },
    }
    end

    dofile(modpath .. "/blocks/shaft.lua")
    dofile(modpath .. "/blocks/steam_generator.lua")
    dofile(modpath .. "/blocks/fluid_pipe.lua")
    dofile(modpath .. "/blocks/water_pump.lua")
    dofile(modpath .. "/blocks/steam_turbine.lua")
    dofile(modpath .. "/blocks/gearbox.lua")
    dofile(modpath .. "/blocks/water_wheel.lua")
    dofile(modpath .. "/blocks/chain_drive.lua")
    dofile(modpath .. "/blocks/mechanical_piston.lua")
    dofile(modpath .. "/blocks/mechanical_saw.lua")
    dofile(modpath .. "/blocks/feeder.lua")
    dofile(modpath .. "/blocks/belt.lua")
    dofile(modpath .. "/blocks/chute.lua")
    dofile(modpath .. "/blocks/encased_fan.lua")
    dofile(modpath .. "/blocks/depot.lua")
    dofile(modpath .. "/blocks/speed_controller.lua")
    dofile(modpath .. "/blocks/glasses.lua")
    dofile(modpath .. "/blocks/mechanical_drill.lua")
    dofile(modpath .. "/blocks/crushing_wheel.lua")
    dofile(modpath .. "/blocks/materials.lua")
    dofile(modpath .. "/blocks/mechanical_press.lua")
    dofile(modpath .. "/blocks/funnel.lua")
    dofile(modpath .. "/blocks/glue.lua")
    dofile(modpath .. "/blocks/portable_interface.lua")
    dofile(modpath .. "/blocks/vault.lua")
