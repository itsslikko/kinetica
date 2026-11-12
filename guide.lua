-- kinetica/guide.lua
kinetica = kinetica or {}
local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- TOP CONFIGURATION SECTION
-- ============================================================================
local CONFIG = {
ENABLE_GUIDE_ITEM = true,
GUIDE_ITEM_NAME   = "kinetica:guide_book",

TEX_GUIDE_BOOK    = "kinetica_guide_book.png", 

UI_COLORS = {
    BG_WINDOW   = "#14171D",
    BG_HEADER   = "#1F242D",
    BG_CARD     = "#1B2028",
    BG_PANEL    = "#171B22",
    TEXT_TITLE  = "#F5B041",
    TEXT_SUB    = "#ABB2B9",
    TEXT_NORM   = "#FFFFFF",
    TEXT_ACCENT = "#00E676",
    SELECT_BG   = "#323741",
}


}

local function file_exists(filename)
if not filename or filename == "" then return false end
local ok, f = pcall(io.open, modpath .. "/textures/" .. filename, "r")
if ok and f then
f:close()
return true
end
return false
end

-- ============================================================================
-- GUIDE CONTENT REGISTRY (EXPANDED DESCRIPTIONS)
-- ============================================================================
local CATEGORIES = {
"Power Generation",
"Logistics & Transfer",
"Processing & Crafting",
"Contraptions & Assembly"
}

local GUIDE_PAGES = {
["Power Generation"] = {
{
id = "kinetica:water_wheel_big",
name = "Big Water Wheel",
desc = "Generates foundational rotational force (Kinetic Units) from flowing water.\n\nHow it works:\nPlace water so it flows against the paddles on the left or right side of the wheel. The direction of the flow determines the spin direction.\n\nTips:\nYou can chain up to 10 water wheels directly next to each other on the same axle to multiply your power generation before needing a shaft!"
},
{
id = "kinetica:steam_generator",
name = "Steam Generator",
desc = "The heart of advanced power generation. Boils water to produce High-Pressure Steam.\n\nHow it works:\n1. Pipe water into the sides or bottom (or manually insert a Water Bucket).\n2. Supply combustible fuel (Coal, Wood, Lava) into the firebox.\n3. High-pressure steam will automatically vent out of the TOP port.\n\nHeat Bonus:\nPlacing a heat source (Lava, Campfire, Magma) directly beneath it gives a 25% chance to save fuel every tick!"
},
{
id = "kinetica:turbine",
name = "Steam Turbine",
desc = "Converts High-Pressure Steam into massive rotational power.\n\nHow it works:\nUse Fluid Pipes to connect the TOP port of a Steam Generator to the RIGHT port of the Turbine. \n\nWarning:\nThe Steam Turbine MUST vent exhaust out of its TOP port. If the top port is blocked by a solid block and not connected to an exhaust pipe, the machine will Choke and stop working."
},
},
["Logistics & Transfer"] = {
{id = "kinetica:shaft", name = "Shaft", desc = "The most basic component. Transfers rotational power in a straight line up to 32 blocks. Cheap and reliable."},
{id = "kinetica:gearbox", name = "Gearbox", desc = "Transfers power at right angles along the horizontal plane (X and Z axis). Reverses rotation direction when turning corners."},
{id = "kinetica:gearbox_vertical", name = "Vertical Gearbox", desc = "Transfers power vertically (Y axis) and horizontally. Essential for moving power between different floors of your factory."},
{id = "kinetica:gearshift", name = "Gearshift", desc = "A redstone-controlled transmission block.\n\nWhen unpowered, power flows through it normally. When a Redstone signal is applied, it reverses the rotation direction of the entire downstream network!"},
{id = "kinetica:variable_gearbox", name = "Variable Gearbox", desc = "An advanced transmission that controls speed and torque.\n\nUsage:\nRight-click to open its interface. You can increase speed (which costs more KU), increase torque (reduces speed), or set it to Neutral to act as a clutch and stop the machine."},
{id = "kinetica:chain_drive", name = "Encased Chain Drive", desc = "Relays power linearly across parallel chain drives. Unlike gearboxes, chain drives placed next to each other will all rotate in the exact SAME direction."},
{id = "kinetica:belt", name = "Mechanical Belt", desc = "Transfers power AND transports items.\n\nSetup:\nPlace two Shafts facing the same direction, then right-click them with the Mechanical Belt item to connect them. Items dropped on the belt will glide along it."},
{id = "kinetica:chute", name = "Chute", desc = "A wide hollow pipe for vertical item logistics.\n\nExtracts any item from containers, Depots, or Belts above it and funnels them straight down. Unfiltered and fast."},
{id = "kinetica:smart_chute", name = "Smart Chute", desc = "An upgraded brass chute with advanced filtering.\n\nFeatures:\n• 3-slot Whitelist/Blacklist filter.\n• Exact batch size control.\n• Instantly locks and pauses when powered by Redstone."},
{id = "kinetica:funnel", name = "Andesite Funnel", desc = "Transfers items horizontally or vertically between belts and inventories.\n\nSneak + Right-Click to manually flip it between Extract (pulling out of chests) and Insert (pushing into chests)."},
{id = "kinetica:smart_funnel", name = "Smart Funnel", desc = "The ultimate logistics sorter.\n\nRight-click to access its UI. You can filter by exact item, or by category (e.g., filtering one 'Log' will match ALL types of wood logs). Extracts up to 64 items at a time."},
{id = "kinetica:steam_pipe", name = "Fluid Pipe", desc = "Transfers liquids and gases. Connects Water Pumps, Steam Generators, and Turbines. Sneak+Right click with an empty hand to flush the pipe."},
},
["Processing & Crafting"] = {
{
id = "kinetica:crushing_wheel",
name = "Crushing Wheel",
desc = "A devastating rotary machine that grinds items into dust, bonus resources, and experience orbs.\n\nSetup:\nMust be placed in PAIRS. Leave a 1-block gap (or a belt) between them, and ensure they are spinning in OPPOSITE directions so they pull items downward into the center seam.\n\nCommon Conversions:\n• Stone / Cobble -> Gravel -> Sand -> Clay\n• Raw Iron/Gold -> 9x Nuggets (Bonus yield)\n• Diamond/Emerald Ore -> 2x Gems + XP\n• Andesite/Diorite/Granite -> Red Sand, Quartz, Flint",
},
{
id = "kinetica:encased_fan",
name = "Encased Fan",
desc = "Creates powerful air currents. Push or pull items, players, and mobs based on rotation.\n\nBulk Processing:\nBlowing air through a catalyst block processes items floating on a Belt or Depot in front of it!\n\nCatalysts:\n• Water (Washing): Gravel -> Iron/Flint. Sand -> Clay.\n• Lava (Blasting): Instantly smelts ores.\n• Fire (Smoking): Cooks food quickly.\n• Soul Fire (Haunting): Converts materials into spooky variants.",
},
{
id = "kinetica:mechanical_press",
name = "Mechanical Press",
desc = "Stamps items with extreme force.\n\nHow it works:\nPlace 1 or 2 blocks above a Depot or Belt. Power it from the side. It will automatically detect valid items below it.\n\nUses:\n• Iron/Gold/Copper Ingots -> Metal Sheets\n• Automatically compacts 2x2 and 3x3 recipes (e.g., 9x Iron Nuggets -> 1x Iron Ingot)."
},
{
id = "kinetica:mechanical_saw",
name = "Mechanical Saw",
desc = "Automated timber processing.\n\nStationary:\nCuts items passing over it on a belt.\n\nContraptions:\nWhen mounted to a moving Piston or bearing, it will fell entire trees at once, chopping every connected wood and leaf block!"
},
{
id = "kinetica:mechanical_drill",
name = "Mechanical Drill",
desc = "Mines blocks directly in front of it.\n\nSpeed scales with RPM and the hardness of the block. Highly effective when glued to a moving Mechanical Piston to create an automated tunnel bore!"
},
{
id = "kinetica:water_pump",
name = "Mechanical Water Pump",
desc = "Extracts water from the world.\n\nPlace directly above a Water Source block. It will pump water up through its top port into Fluid Pipes. Speed scales heavily with RPM."
},
{
id = "kinetica:feeder",
name = "Mechanical Feeder",
desc = "Automates farming and breeding in a 3x3 zone.\n\nFunctions:\n1. Tills dirt if supplied with a Hoe.\n2. Plants crops/saplings from its Seed Bank.\n3. Harvests mature crops into its Profit Bins.\n4. Feeds animals their favorite food to breed them!"
},
},
["Contraptions & Assembly"] = {
{
id = "kinetica:mechanical_piston",
name = "Mechanical Piston",
desc = "Pushes blocks linearly.\n\nPower it from the side. To increase its reach, place Piston Extension Poles directly behind it. The piston will push blocks in front of it based on how many poles it has."
},
{
id = "kinetica:sticky_mechanical_piston",
name = "Sticky Mechanical Piston",
desc = "Pushes AND Pulls blocks. \n\nWhen it retracts, it will pull the block attached to its head. Essential for moving Super Glued contraptions back and forth."
},
{
id = "kinetica:piston_pole",
name = "Piston Extension Pole",
desc = "Attach these directly behind a Mechanical Piston to increase its maximum reach. Can attach up to 32 poles per piston."
},
{
id = "kinetica:super_glue",
name = "Super Glue",
desc = "Binds blocks together to move as a single massive Contraption.\n\nUsage:\nRight-click one block, then right-click another to draw a green bounding box. Any blocks inside this box are now glued! Mount them to a Sticky Piston to move them all at once."
},
{
id = "kinetica:item_vault",
name = "Item Vault",
desc = "A massive multi-block storage solution.\n\nPlace them next to each other to combine their inventories into one giant pool. Unlike normal chests, Item Vaults are 100% safe to move on Piston Contraptions!"
},
{
id = "kinetica:depot",
name = "Depot",
desc = "A staging block that holds items for processing.\n\nPlace an item on it, and machines like the Press, Fan, or Funnel can interact with the item. It acts as a 1-slot open chest."
},
{
id = "kinetica:portable_storage_interface",
name = "Portable Storage Interface",
desc = "Bridges the gap between moving contraptions and your static factory.\n\nHow it works:\nPlace one on your moving contraption (attached to a Vault), and one on a static wall (attached to a Chute). When they face each other, they will dock and transfer items automatically!"
},
}
}

-- ============================================================================
-- DYNAMIC STAT FETCHING
-- ============================================================================
local function get_dynamic_stats(item_id)
local lines = {}
local mdef = kinetica.get_machine_def and kinetica.get_machine_def(item_id)

if mdef then
    if mdef.min_rpm then
        table.insert(lines, "• <b color=#FFFFFF>Minimum Speed:</b> " .. mdef.min_rpm .. " RPM")
    end
    if mdef.get_demand_ku then
        local ok, ku = pcall(mdef.get_demand_ku, 16, nil, {name = item_id, param2 = 0})
        if ok and type(ku) == "number" and ku > 0 then
            table.insert(lines, "• <b color=#FFFFFF>Base Stress:</b> -" .. math.floor(ku) .. " KU (at 16 RPM)")
        end
    end
    if mdef.can_ride_piston ~= nil then
        local safe_col = mdef.can_ride_piston and "#00E676" or "#FF5252"
        table.insert(lines, "• <b color=#FFFFFF>Contraption Safe:</b> <b color="..safe_col..">" .. (mdef.can_ride_piston and "Yes" or "No") .. "</b>")
    end
end

if item_id == "kinetica:water_wheel_big" then
    table.insert(lines, "• <b color=#FFFFFF>Power Generation:</b> +" .. (kinetica.BIG_WHEEL_KU or 256) .. " KU")
    table.insert(lines, "• <b color=#FFFFFF>Base Speed:</b> " .. (kinetica.BIG_WHEEL_RPM or 4) .. " RPM")
elseif item_id == "kinetica:turbine" then
    table.insert(lines, "• <b color=#FFFFFF>Power Generation:</b> +" .. (kinetica.TURBINE_KU or 1024) .. " KU")
    table.insert(lines, "• <b color=#FFFFFF>Base Speed:</b> " .. (kinetica.TURBINE_RPM or 512) .. " RPM")
end

if #lines == 0 then
    table.insert(lines, "• <b color=#95A5A6>Kinetic Network: N/A (Passive/Tool)</b>")
end

return table.concat(lines, "\n")


end

-- ============================================================================
-- UI GENERATION & STATE MANAGEMENT
-- ============================================================================
local player_states = {}

local function get_guide_formspec(pname)
local state = player_states[pname] or { cat_idx = 1, item_idx = 1 }
local U     = CONFIG.UI_COLORS

local cat_name = CATEGORIES[state.cat_idx] or CATEGORIES[1]
local items    = GUIDE_PAGES[cat_name] or {}
local selected = items[state.item_idx] or items[1]

local cat_list_str = table.concat(CATEGORIES, ",")

local item_names = {}
for _, itm in ipairs(items) do
    table.insert(item_names, core.formspec_escape(itm.name))
end
local item_list_str = table.concat(item_names, ",")

-- Clean formatting with better spacing for hypertext
local ht_body = string.format(
    "<global size=16 color=%s font=normal halign=left valign=top>" ..
    "<center><b color=%s size=20>%s</b></center>\n" ..
    "%s\n\n" ..
    "<b color=%s size=18>Dynamic Telemetry:</b>\n" ..
    "%s",
    U.TEXT_NORM,
    U.TEXT_TITLE, selected.name,
    selected.desc,
    U.TEXT_ACCENT,
    get_dynamic_stats(selected.id)
)

-- Widened the UI layout for better text fitting
local fs = {
    "size[15.5,9.5]",
    "bgcolor[" .. U.BG_WINDOW .. ";false]",
    
    -- Header
    "box[0,0;15.5,1;" .. U.BG_HEADER .. "]",
    "label[0.3,0.5;" .. core.colorize(U.TEXT_TITLE, "KINETICA ENGINEERING GUIDE") .. "]",
    
    -- Categories (Left)
    "box[0.2,1.2;4.2,8.1;" .. U.BG_CARD .. "]",
    "textlist[0.3,1.3;4.0,7.9;cat_list;" .. cat_list_str .. ";" .. state.cat_idx .. ";false]",
    
    -- Items (Middle)
    "box[4.5,1.2;4.2,8.1;" .. U.BG_CARD .. "]",
    "textlist[4.6,1.3;4.0,7.9;item_list;" .. item_list_str .. ";" .. state.item_idx .. ";false]",
    
    -- Details (Right)
    "box[8.8,1.2;6.5,8.1;" .. U.BG_CARD .. "]",
    
    -- 3D Isometric View Using item_image
    "box[10.55,1.4;3,3;" .. U.BG_PANEL .. "]",
    "item_image[10.55,1.4;3,3;" .. selected.id .. "]",
    
    -- Expanded Info Text Area
    "hypertext[9.0,4.6;6.1,4.5;item_desc;" .. core.formspec_escape(ht_body) .. "]"
}

return table.concat(fs)


end

local function show_guide(player)
local pname = player:get_player_name()
core.show_formspec(pname, "kinetica:guide", get_guide_formspec(pname))
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================
core.register_on_player_receive_fields(function(player, formname, fields)
if formname ~= "kinetica:guide" then return false end

local pname = player:get_player_name()
local state = player_states[pname] or { cat_idx = 1, item_idx = 1 }
local needs_update = false

if fields.cat_list then
    local e = core.explode_textlist_event(fields.cat_list)
    if e.type == "CHG" then
        state.cat_idx = e.index
        state.item_idx = 1
        needs_update = true
    end
end

if fields.item_list then
    local e = core.explode_textlist_event(fields.item_list)
    if e.type == "CHG" then
        state.item_idx = e.index
        needs_update = true
    end
end

if fields.quit then
    player_states[pname] = nil
elseif needs_update then
    player_states[pname] = state
    show_guide(player)
end

return true


end)

-- ============================================================================
-- REGISTRATION
-- ============================================================================
if CONFIG.ENABLE_GUIDE_ITEM then
local book_icon = file_exists(CONFIG.TEX_GUIDE_BOOK)
and CONFIG.TEX_GUIDE_BOOK
or "default_book_written.png^[colorize:#F5B041:100"

core.register_craftitem(CONFIG.GUIDE_ITEM_NAME, {
    description = "Kinetica Engineering Guide\nRead to learn about kinetic automation.",
    inventory_image = book_icon,
    wield_image = book_icon,
    groups = {book = 1, handy = 1},
    on_use = function(itemstack, user, pointed_thing)
        if user and user:is_player() then
            show_guide(user)
        end
        return itemstack
    end,
})

core.register_craft({
    output = CONFIG.GUIDE_ITEM_NAME,
    recipe = {
        {"kinetica:andesite_alloy", "default:book"}
    }
})


end

core.register_chatcommand("kinetica", {
description = "Open the Kinetica Engineering Guide",
func = function(name, param)
local player = core.get_player_by_name(name)
if player then
show_guide(player)
return true, "Opening guide..."
end
return false, "Player not found."
end,
})