kinetica = kinetica or {}

local CONFIG = {
    FRONT_FACES_PLAYER            = false,
    ALLOW_VERTICAL_PLACEMENT      = true,
    MIN_RPM                       = 4,
    KU_PER_RPM                    = 4,
    MIN_KU                        = 16,
    MAX_KU                        = 64,
    MAX_RPM_CAP                   = 1024,
    CYCLE_SEC_AT_5_RPM            = 1.10,
    CYCLE_SEC_AT_512_RPM          = 0.16,
    PUNCH_EXTEND_DURATION         = 0.12,
    REACH_DISTANCE                = 1,
    PROFIT_SLOTS                  = 2,
    MAX_CONTRAPTION_SCAN_NODES    = 48,
    ALLOW_BLOCK_PLACEMENT         = true,
    ALLOW_BUCKET_HANDLING         = true,
    ALLOW_ENTITY_ATTACK           = true,
    ALLOW_NODE_INTERACTION        = true,
    ALLOW_SHEARING                = true,
    DAMAGE_TOOLS_ON_USE           = true,
    BASE_PUNCH_DAMAGE             = 2,
    HIDE_INFOTEXT_WITHOUT_GLASSES = true,
    BACK_ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    TEX_CASING        = "kinetica_gold_casing.png",
    TEX_SHAFT_OVERLAY = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME = "kinetica:deployer"
local ITEM_ENT  = "kinetica:deployer_held_item"

local ALL_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local FILLED_BUCKET_TO_LIQUID = {
    ["mcl_buckets:bucket_water"]       = {source = "mcl_core:water_source",             empty = "mcl_buckets:bucket_empty", sound = "default_water_footstep"},
    ["mcl_buckets:bucket_river_water"] = {source = "mclx_core:river_water_source",      empty = "mcl_buckets:bucket_empty", sound = "default_water_footstep"},
    ["mcl_buckets:bucket_lava"]        = {source = "mcl_core:lava_source",              empty = "mcl_buckets:bucket_empty", sound = "default_place_node"},
    ["bucket:bucket_water"]            = {source = "default:water_source",              empty = "bucket:bucket_empty",      sound = "default_water_footstep"},
    ["bucket:bucket_river_water"]      = {source = "default:river_water_source",        empty = "bucket:bucket_empty",      sound = "default_water_footstep"},
    ["bucket:bucket_lava"]             = {source = "default:lava_source",               empty = "bucket:bucket_empty",      sound = "default_place_node"},
}

local LIQUID_SOURCE_TO_BUCKET = {
    ["mcl_core:water_source"]        = {empty = "mcl_buckets:bucket_empty", filled = "mcl_buckets:bucket_water"},
    ["mclx_core:river_water_source"] = {empty = "mcl_buckets:bucket_empty", filled = "mcl_buckets:bucket_river_water"},
    ["mcl_core:lava_source"]         = {empty = "mcl_buckets:bucket_empty", filled = "mcl_buckets:bucket_lava"},
    ["default:water_source"]         = {empty = "bucket:bucket_empty",      filled = "bucket:bucket_water"},
    ["default:river_water_source"]   = {empty = "bucket:bucket_empty",      filled = "bucket:bucket_river_water"},
    ["default:lava_source"]          = {empty = "bucket:bucket_empty",      filled = "bucket:bucket_lava"},
}

local function is_deployer_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_deployer = is_deployer_node

local function is_extended_variant(name)
    return name and string.sub(name, -4) == "_ext"
end

local function strip_ext_suffix(name)
    if is_extended_variant(name) then
        return string.sub(name, 1, #name - 4)
    end
    return name
end

local function get_deployer_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return CONFIG.MIN_KU end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local function get_cycle_interval(rpm)
    if not rpm or rpm <= 0 then return CONFIG.CYCLE_SEC_AT_5_RPM end
    local t = math.min(1.0, math.max(0.0, (rpm - 5) / (512 - 5)))
    return CONFIG.CYCLE_SEC_AT_5_RPM - t * (CONFIG.CYCLE_SEC_AT_5_RPM - CONFIG.CYCLE_SEC_AT_512_RPM)
end

local function get_back_dir(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = d.x, y = d.y, z = d.z}
end

local function get_front_dir(param2)
    local b = get_back_dir(param2)
    return {x = -b.x, y = -b.y, z = -b.z}
end

local function ensure_deployer_inventory(meta)
    local inv = meta:get_inventory()
    if inv:get_size("hand") ~= 1 then
        inv:set_size("hand", 1)
        if inv:get_size("main") == 1 then
            local old = inv:get_stack("main", 1)
            if not old:is_empty() then inv:set_stack("hand", 1, old) end
            inv:set_size("main", 0)
        end
    end
    if inv:get_size("profit") ~= CONFIG.PROFIT_SLOTS then
        inv:set_size("profit", CONFIG.PROFIT_SLOTS)
    end
    return inv
end

local function format_slot_summary(stack)
    if not stack or stack:is_empty() then return "Empty" end
    local iname = stack:get_name()
    local idef  = core.registered_items[iname]
    local desc  = (idef and idef.description) and string.match(idef.description, "^[^\n]+") or iname
    desc = string.gsub(desc, "\27%(.-%)", "")
    desc = string.gsub(desc, "\27.", "")
    return string.format("%s x%d", desc, stack:get_count())
end

local function get_held_item_world_pos(pos, param2, extended)
    local front = get_front_dir(param2)
    local dist  = extended and 0.56 or 0.36
    return {
        x = pos.x + front.x * dist,
        y = pos.y + front.y * dist,
        z = pos.z + front.z * dist,
    }, front
end

local function dir_to_entity_rot(front)
    if front.y > 0 then
        return {x = -math.pi / 2, y = 0, z = 0}
    elseif front.y < 0 then
        return {x = math.pi / 2, y = 0, z = 0}
    end
    local yaw = math.atan2(-front.x, front.z)
    return {x = 0, y = yaw, z = 0}
end

local function clear_held_item_entities(pos)
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.95)) do
        local ent = obj:get_luaentity()
        if ent and ent.name == ITEM_ENT and ent._deployer_hash == core.hash_node_position(pos) then
            obj:remove()
        end
    end
end

local function sync_held_item_entity(pos, node)
    node = node or core.get_node(pos)
    if not is_deployer_node(node.name) then
        clear_held_item_entities(pos)
        return nil
    end

    local meta  = core.get_meta(pos)
    local inv   = ensure_deployer_inventory(meta)
    local stack = inv:get_stack("hand", 1)
    local my_h  = core.hash_node_position(pos)

    if stack:is_empty() then
        clear_held_item_entities(pos)
        return nil
    end

    local item_name   = stack:get_name()
    local is_ext      = is_extended_variant(node.name)
    local wpos, front = get_held_item_world_pos(pos, node.param2, is_ext)
    local target_rot  = dir_to_entity_rot(front)
    local is_block    = core.registered_nodes[item_name] ~= nil
    local v_size      = is_block and {x = 0.24, y = 0.24, z = 0.24} or {x = 0.28, y = 0.28, z = 0.28}

    local found_obj = nil
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.95)) do
        local ent = obj:get_luaentity()
        if ent and ent.name == ITEM_ENT and ent._deployer_hash == my_h then
            if not found_obj then
                found_obj = obj
            else
                obj:remove()
            end
        end
    end

    if not found_obj then
        found_obj = core.add_entity(wpos, ITEM_ENT, core.serialize({
            deployer_pos = pos,
            item_name    = item_name,
        }))
    end

    if found_obj then
        local ent = found_obj:get_luaentity()
        if ent then
            ent._deployer_pos  = {x = pos.x, y = pos.y, z = pos.z}
            ent._deployer_hash = my_h
            ent._item_name     = item_name
        end
        found_obj:set_pos(wpos)
        if found_obj.set_rotation then
            found_obj:set_rotation(target_rot)
        end
        found_obj:set_properties({
            wield_item  = item_name,
            visual_size = v_size,
        })
    end
    return found_obj
end

core.register_entity(ITEM_ENT, {
    initial_properties = {
        visual               = "wielditem",
        wield_item           = "air",
        visual_size          = {x = 0.26, y = 0.26, z = 0.26},
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        static_save          = false,
        glow                 = 2,
    },
    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if type(data) == "table" and data.deployer_pos then
                self._deployer_pos  = data.deployer_pos
                self._deployer_hash = core.hash_node_position(data.deployer_pos)
                self._item_name     = data.item_name
            end
        end
    end,
    on_step = function(self, dtime)
        self._timer = (self._timer or 0) + dtime
        if self._timer < 0.5 then return end
        self._timer = 0
        local dpos = self._deployer_pos
        if not dpos then
            self.object:remove()
            return
        end
        local node = core.get_node(dpos)
        if not is_deployer_node(node.name) then
            self.object:remove()
        end
    end,
})

local STORAGE_LIST_CANDIDATES = {"main", "vault", "items", "storage", "chest"}

local function try_insert_into_storage_node(spos, snode, stack)
    if not stack or stack:is_empty() then return stack end
    if is_deployer_node(snode.name) or (kinetica.is_feeder and kinetica.is_feeder(snode.name)) then
        return stack
    end

    local sdef = core.registered_nodes[snode.name]
    if not sdef then return stack end

    local is_storage = (core.get_item_group(snode.name, "container") > 0) or
                       (core.get_item_group(snode.name, "chest") > 0) or
                       string.find(snode.name, "vault") ~= nil or
                       string.find(snode.name, "chest") ~= nil or
                       string.find(snode.name, "barrel") ~= nil or
                       string.find(snode.name, "hopper") ~= nil or
                       string.find(snode.name, "shulker") ~= nil

    if not is_storage then return stack end

    if kinetica.vault_insert_stack and string.find(snode.name, "vault") then
        stack = kinetica.vault_insert_stack(spos, stack)
        if stack:is_empty() then return stack end
    end

    local smeta = core.get_meta(spos)
    local sinv  = smeta and smeta:get_inventory()
    if not sinv then return stack end

    for _, listname in ipairs(STORAGE_LIST_CANDIDATES) do
        if sinv:get_size(listname) > 0 and sinv:room_for_item(listname, stack) then
            stack = sinv:add_item(listname, stack)
            if stack:is_empty() then return stack end
        end
    end
    return stack
end

local function route_collected_item(deployer_pos, inv, drop_pos, stack)
    if not stack or stack:is_empty() then return end
    local remaining = ItemStack(stack)

    local visited = {[core.hash_node_position(deployer_pos)] = true}
    local queue   = {{x = deployer_pos.x, y = deployer_pos.y, z = deployer_pos.z}}
    local head    = 1

    while head <= #queue and #queue <= CONFIG.MAX_CONTRAPTION_SCAN_NODES and not remaining:is_empty() do
        local cur = queue[head]
        head = head + 1

        for _, d in ipairs(ALL_DIRS) do
            local np   = {x = cur.x + d.x, y = cur.y + d.y, z = cur.z + d.z}
            local nkey = core.hash_node_position(np)
            if not visited[nkey] then
                visited[nkey] = true
                local nnode = core.get_node(np)

                remaining = try_insert_into_storage_node(np, nnode, remaining)
                if remaining:is_empty() then return end

                local is_glued = (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(nnode.name)) or
                                 (kinetica.is_piston_pole_or_head and kinetica.is_piston_pole_or_head(nnode.name))
                if is_glued then
                    queue[#queue + 1] = np
                end
            end
        end
    end

    if not remaining:is_empty() then
        remaining = inv:add_item("profit", remaining)
    end
    if not remaining:is_empty() then
        core.add_item(drop_pos, remaining)
    end
end

local function handle_bucket_action(pos, inv, hand_stack, target_pos, target_node)
    if not CONFIG.ALLOW_BUCKET_HANDLING or hand_stack:is_empty() then
        return nil
    end

    local item_name = hand_stack:get_name()

    local fill_info = FILLED_BUCKET_TO_LIQUID[item_name]
    if fill_info and core.registered_nodes[fill_info.source] then
        local tdef = core.registered_nodes[target_node.name]
        local is_liquid_source = (core.get_item_group(target_node.name, "liquid") > 0 and target_node.name == fill_info.source)
        local can_place_liquid = (target_node.name == "air") or
                                 (tdef and tdef.buildable_to and not is_liquid_source)

        if can_place_liquid then
            core.set_node(target_pos, {name = fill_info.source, param2 = 0})
            hand_stack:take_item(1)
            inv:set_stack("hand", 1, hand_stack)
            route_collected_item(pos, inv, target_pos, ItemStack(fill_info.empty))
            core.sound_play(fill_info.sound, {pos = target_pos, max_hear_distance = 12, gain = 0.7}, true)
            return "Emptied Bucket"
        end
        return "Blocked"
    end

    if item_name == "mcl_buckets:bucket_empty" or item_name == "bucket:bucket_empty" then
        local scoop_info = LIQUID_SOURCE_TO_BUCKET[target_node.name]
        if scoop_info and core.registered_items[scoop_info.filled] then
            core.remove_node(target_pos)
            hand_stack:take_item(1)
            inv:set_stack("hand", 1, hand_stack)
            route_collected_item(pos, inv, target_pos, ItemStack(scoop_info.filled))
            core.sound_play("default_water_footstep", {pos = target_pos, max_hear_distance = 12, gain = 0.7}, true)
            return "Filled Bucket"
        end
        return "No Liquid"
    end

    return nil
end

local function add_wear_to_tool(stack, pos)
    if not CONFIG.DAMAGE_TOOLS_ON_USE or stack:is_empty() then return stack end
    local def  = core.registered_items[stack:get_name()]
    local uses = 238

    if def then
        if type(def._mcl_uses) == "number" and def._mcl_uses > 0 then
            uses = def._mcl_uses
        elseif def.tool_capabilities and def.tool_capabilities.groupcaps then
            for _, gcap in pairs(def.tool_capabilities.groupcaps) do
                if type(gcap.uses) == "number" and gcap.uses > 0 then
                    uses = gcap.uses
                    break
                end
            end
        end
    end

    local unbreaking = 0
    if mcl_enchanting and type(mcl_enchanting.get_enchantment) == "function" then
        unbreaking = mcl_enchanting.get_enchantment(stack, "unbreaking") or 0
    end
    if unbreaking > 0 and math.random(1, unbreaking + 1) > 1 then
        return stack
    end

    stack:add_wear(math.max(1, math.ceil(65535 / math.max(1, uses))))
    if stack:is_empty() then
        core.sound_play("default_tool_breaks", {pos = pos, max_hear_distance = 12, gain = 0.8}, true)
    end
    return stack
end

local function create_mock_player(pos, front_dir, owner_name, held_stack)
    local yaw = 0
    if front_dir.x ~= 0 or front_dir.z ~= 0 then
        yaw = math.atan2(-front_dir.x, front_dir.z)
    end
    local cur_wield = ItemStack(held_stack or "")
    local leftover_drops = {}

    local mock_inv = {
        add_item = function(_, _, stack)
            local st = ItemStack(stack)
            if not st:is_empty() then table.insert(leftover_drops, st) end
            return ItemStack("")
        end,
        room_for_item = function() return true end,
        contains_item = function(_, _, stack)
            return cur_wield:get_name() == ItemStack(stack):get_name()
        end,
        remove_item = function(_, _, stack)
            local req = ItemStack(stack)
            if cur_wield:get_name() == req:get_name() then
                return cur_wield:take_item(req:get_count())
            end
            return ItemStack("")
        end,
        get_stack = function() return cur_wield end,
        set_stack = function(_, _, _, st) cur_wield = ItemStack(st) end,
    }

    local mock = {
        is_player = function() return true end,
        -- Use non-creative virtual name so callbacks never skip item consumption
        get_player_name = function() return "__kinetica_deployer__" end,
        get_pos = function() return {x = pos.x, y = pos.y - 0.5, z = pos.z} end,
        get_look_dir = function() return {x = front_dir.x, y = front_dir.y, z = front_dir.z} end,
        get_look_horizontal = function() return yaw end,
        get_look_vertical = function() return -math.asin(front_dir.y) end,
        get_player_control = function() return {sneak = false, jump = false, up = false, down = false, left = false, right = false, aux1 = false, LMB = false, RMB = true} end,
        get_player_control_bits = function() return 0 end,
        get_wielded_item = function() return cur_wield end,
        set_wielded_item = function(_, st) cur_wield = ItemStack(st) return true end,
        get_wield_index = function() return 1 end,
        get_wield_list = function() return "main" end,
        get_inventory = function() return mock_inv end,
        get_meta = function() return core.get_meta(pos) end,
        get_properties = function() return {eye_height = 1.5} end,
        get_hp = function() return 20 end,
        set_hp = function() end,
        get_armor_groups = function() return {immortal = 1} end,
    }
    return mock, function() return cur_wield end, leftover_drops
end

local function is_shears_item(item_name)
    if not item_name or item_name == "" then return false end
    return core.get_item_group(item_name, "shears") > 0 or string.find(item_name, "shears") ~= nil
end

local function is_valid_attack_target(luaent)
    if not luaent or not luaent.name then return false end
    if string.sub(luaent.name, 1, 10) == "__builtin:" then return false end
    if luaent.name == ITEM_ENT or string.sub(luaent.name, 1, 9) == "kinetica:" then return false end
    if luaent.is_mob or luaent._cmi_is_mob or luaent.health or string.find(luaent.name, "mobs_mc:") then
        return true
    end
    return false
end

local function shear_sheep_entity(pos, inv, hand_stack, obj, luaent, target_pos)
    if luaent.gotten == true or luaent.child == true then
        return false
    end

    local wool_item = "mcl_wool:white"
    if type(luaent.drops) == "table" then
        for _, d in ipairs(luaent.drops) do
            if type(d.name) == "string" and string.find(d.name, "wool") then
                wool_item = d.name
                break
            end
        end
    end
    if type(luaent.color) == "string" and luaent.color ~= "" then
        local cand = "mcl_wool:" .. string.gsub(luaent.color, "^unicolor_", "")
        if core.registered_items[cand] then
            wool_item = cand
        end
    end

    luaent.gotten = true
    if type(luaent.set_textures) == "function" and type(luaent.gotten_texture) == "table" then
        pcall(luaent.set_textures, luaent, luaent.gotten_texture)
    elseif type(luaent.gotten_texture) == "table" then
        obj:set_properties({textures = luaent.gotten_texture})
    end
    if type(luaent.gotten_mesh) == "string" then
        obj:set_properties({mesh = luaent.gotten_mesh})
    end

    local wool_stack = ItemStack(wool_item .. " " .. math.random(1, 3))
    route_collected_item(pos, inv, target_pos, wool_stack)

    hand_stack = add_wear_to_tool(hand_stack, pos)
    inv:set_stack("hand", 1, hand_stack)
    core.sound_play("mcl_tools_shears_cut", {pos = target_pos, max_hear_distance = 12, gain = 0.8}, true)
    return true
end

local function get_weapon_damage(stack)
    if stack:is_empty() then return CONFIG.BASE_PUNCH_DAMAGE end
    local def = core.registered_items[stack:get_name()]
    if def and def.tool_capabilities and def.tool_capabilities.damage_groups and def.tool_capabilities.damage_groups.fleshy then
        return def.tool_capabilities.damage_groups.fleshy
    end
    return CONFIG.BASE_PUNCH_DAMAGE
end

local function trigger_hand_lunge(pos, node)
    local base_variant = strip_ext_suffix(node.name)
    local ext_variant  = base_variant .. "_ext"
    if core.registered_nodes[ext_variant] then
        core.swap_node(pos, {name = ext_variant, param2 = node.param2})
        sync_held_item_entity(pos, {name = ext_variant, param2 = node.param2})
        core.after(CONFIG.PUNCH_EXTEND_DURATION, function()
            local cur = core.get_node(pos)
            if is_deployer_node(cur.name) and is_extended_variant(cur.name) then
                local retracted = strip_ext_suffix(cur.name)
                core.swap_node(pos, {name = retracted, param2 = cur.param2})
                sync_held_item_entity(pos, {name = retracted, param2 = cur.param2})
            end
        end)
    else
        sync_held_item_entity(pos, node)
    end
end

local function execute_deployer_cycle(pos, node)
    node = node or core.get_node(pos)
    if not is_deployer_node(node.name) then return "" end

    local meta       = core.get_meta(pos)
    local inv        = ensure_deployer_inventory(meta)
    local owner      = meta:get_string("owner")
    local front      = get_front_dir(node.param2)
    local hand_stack = inv:get_stack("hand", 1)
    local item_name  = hand_stack:get_name()
    local item_def   = core.registered_items[item_name]

    local target_pos = {
        x = pos.x + front.x * CONFIG.REACH_DISTANCE,
        y = pos.y + front.y * CONFIG.REACH_DISTANCE,
        z = pos.z + front.z * CONFIG.REACH_DISTANCE,
    }

    if core.is_protected(target_pos, owner) then
        return "Protected"
    end

    local target_node = core.get_node(target_pos)

    -- 1. Dedicated Bucket Fill / Empty Handling
    local bucket_res = handle_bucket_action(pos, inv, hand_stack, target_pos, target_node)
    if bucket_res then
        if bucket_res == "Emptied Bucket" or bucket_res == "Filled Bucket" then
            trigger_hand_lunge(pos, node)
            return bucket_res
        end
        sync_held_item_entity(pos, node)
        return ""
    end

    -- 2. Entity Shearing & Combat
    local objs = core.get_objects_inside_radius(target_pos, 0.95)
    for _, obj in ipairs(objs) do
        if not obj:is_player() then
            local luaent = obj:get_luaentity()
            if is_valid_attack_target(luaent) then
                if CONFIG.ALLOW_SHEARING and is_shears_item(item_name) and string.find(luaent.name or "", "sheep") then
                    if shear_sheep_entity(pos, inv, hand_stack, obj, luaent, target_pos) then
                        trigger_hand_lunge(pos, node)
                        return "Sheared Sheep"
                    end
                end

                local is_placeable_block = (core.registered_nodes[item_name] ~= nil)
                if CONFIG.ALLOW_ENTITY_ATTACK and not is_placeable_block then
                    local dmg = get_weapon_damage(hand_stack)
                    local puncher_ref = (owner ~= "" and owner ~= "$unknown" and core.get_player_by_name(owner))
                                        or sync_held_item_entity(pos, node)
                                        or obj

                    pcall(function()
                        obj:punch(puncher_ref, 1.0, {
                            full_punch_interval = 1.0,
                            damage_groups = {fleshy = dmg},
                        }, front)
                    end)

                    if not hand_stack:is_empty() then
                        hand_stack = add_wear_to_tool(hand_stack, pos)
                        inv:set_stack("hand", 1, hand_stack)
                    end
                    core.sound_play("default_punch", {pos = target_pos, max_hear_distance = 10, gain = 0.7}, true)

                    core.after(0.05, function()
                        for _, drop_obj in ipairs(core.get_objects_inside_radius(target_pos, 1.35)) do
                            local dent = drop_obj:get_luaentity()
                            if dent and dent.name == "__builtin:item" and dent.itemstring and dent.itemstring ~= "" then
                                route_collected_item(pos, inv, target_pos, ItemStack(dent.itemstring))
                                drop_obj:remove()
                            end
                        end
                    end)

                    trigger_hand_lunge(pos, node)
                    return "Attacked Mob"
                end
            end
        end
    end

    local target_def = core.registered_nodes[target_node.name]
    local pointed = {
        type  = "node",
        under = target_pos,
        above = {x = target_pos.x - front.x, y = target_pos.y - front.y, z = target_pos.z - front.z},
    }

    -- 3. Block Shearing
    if CONFIG.ALLOW_SHEARING and is_shears_item(item_name) and target_node.name ~= "air" then
        if core.get_item_group(target_node.name, "leaves") > 0 or
           core.get_item_group(target_node.name, "shearsy") > 0 or
           string.find(target_node.name, "vine") or
           string.find(target_node.name, "web") then
            route_collected_item(pos, inv, target_pos, ItemStack(target_node.name))
            core.remove_node(target_pos)
            hand_stack = add_wear_to_tool(hand_stack, pos)
            inv:set_stack("hand", 1, hand_stack)
            core.sound_play("default_dig_snappy", {pos = target_pos, max_hear_distance = 12, gain = 0.7}, true)
            trigger_hand_lunge(pos, node)
            return "Sheared Block"
        end
    end

    -- 4. Empty Hand Block Interaction
    if CONFIG.ALLOW_NODE_INTERACTION and target_node.name ~= "air" and hand_stack:is_empty() then
        if target_def and type(target_def.on_rightclick) == "function" then
            local mock, _, drops = create_mock_player(pos, front, owner, hand_stack)
            local ok = pcall(target_def.on_rightclick, target_pos, target_node, mock, hand_stack, pointed)
            if ok then
                for _, d in ipairs(drops) do route_collected_item(pos, inv, target_pos, d) end
                trigger_hand_lunge(pos, node)
                return "Clicked Block"
            end
        end
    end

    -- 5. Block Placement & Item Use
    if not hand_stack:is_empty() and item_def then
        local can_build = (target_node.name == "air") or (target_def and target_def.buildable_to)
        if CONFIG.ALLOW_BLOCK_PLACEMENT and core.registered_nodes[item_name] and can_build and not is_deployer_node(item_name) then
            local p_def = core.registered_nodes[item_name]
            local p2    = 0
            if p_def.paramtype2 == "facedir" then
                p2 = core.dir_to_facedir(front, true)
            elseif p_def.paramtype2 == "wallmounted" then
                p2 = core.dir_to_wallmounted({x = -front.x, y = -front.y, z = -front.z})
            end
            core.set_node(target_pos, {name = item_name, param2 = p2})
            if core.check_for_falling then
                core.check_for_falling(target_pos)
            end
            hand_stack:take_item(1)
            inv:set_stack("hand", 1, hand_stack)
            core.sound_play("default_place_node", {pos = target_pos, max_hear_distance = 12, gain = 0.7}, true)
            trigger_hand_lunge(pos, node)
            return "Placed Block"
        end

        if not core.registered_nodes[item_name] and type(item_def.on_place) == "function" then
            local orig_name  = hand_stack:get_name()
            local orig_count = hand_stack:get_count()
            local mock, _, drops = create_mock_player(pos, front, owner, hand_stack)
            local ok, res = pcall(item_def.on_place, hand_stack, mock, pointed)
            if ok and res then
                if res:get_name() ~= orig_name then
                    if orig_count > 1 then
                        hand_stack:set_count(orig_count - 1)
                        inv:set_stack("hand", 1, hand_stack)
                    else
                        inv:set_stack("hand", 1, ItemStack(""))
                    end
                    route_collected_item(pos, inv, target_pos, res)
                else
                    inv:set_stack("hand", 1, res)
                end
                for _, d in ipairs(drops) do route_collected_item(pos, inv, target_pos, d) end
                trigger_hand_lunge(pos, node)
                return "Deployed Item"
            end
        end

        if type(item_def.on_use) == "function" then
            local mock, _, drops = create_mock_player(pos, front, owner, hand_stack)
            local ok, res = pcall(item_def.on_use, hand_stack, mock, pointed)
            if ok and res then
                inv:set_stack("hand", 1, res)
                for _, d in ipairs(drops) do route_collected_item(pos, inv, target_pos, d) end
                trigger_hand_lunge(pos, node)
                return "Used Item"
            end
        end
    end

    sync_held_item_entity(pos, node)
    return ""
end

local moved_step_guard = {}
if mcl_pistons and mcl_pistons.register_on_move then
    mcl_pistons.register_on_move(function(moved_nodes)
        local now_us = core.get_us_time()
        for _, moved in ipairs(moved_nodes) do
            if moved.node and is_deployer_node(moved.node.name) then
                if moved.old_pos then
                    clear_held_item_entities(moved.old_pos)
                end
                local dest = {x = moved.pos.x, y = moved.pos.y, z = moved.pos.z}
                local hkey = core.hash_node_position(dest)
                if not moved_step_guard[hkey] or (now_us - moved_step_guard[hkey]) > 50000 then
                    moved_step_guard[hkey] = now_us
                    core.after(0, function()
                        local cur_node = core.get_node(dest)
                        if is_deployer_node(cur_node.name) then
                            execute_deployer_cycle(dest, cur_node)
                            sync_held_item_entity(dest, cur_node)
                        end
                    end)
                end
            end
        end
    end)
end

local function look_to_unit_dir(placer, allow_vertical)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if allow_vertical and ay > ax and ay > az then
        return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then
        return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else
        return {x = 0, y = 0, z = (look.z > 0) and 1 or -1}
    end
end

local function place_deployer(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then return itemstack end

    local under_pos  = pointed_thing.under
    local above_pos  = pointed_thing.above
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local diff = {
        x = above_pos.x - under_pos.x,
        y = above_pos.y - under_pos.y,
        z = above_pos.z - under_pos.z,
    }
    local front_dir = nil

    if not sneaking then
        if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(under_node.name)) or
           under_node.name == "kinetica:piston_head" or
           under_node.name == "kinetica:piston_head_sticky" or
           (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(under_node.name)) or
           (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff)) then
            if CONFIG.ALLOW_VERTICAL_PLACEMENT or diff.y == 0 then
                front_dir = diff
            end
        end
    end

    if not front_dir then
        local ldir   = look_to_unit_dir(placer, CONFIG.ALLOW_VERTICAL_PLACEMENT)
        local invert = CONFIG.FRONT_FACES_PLAYER
        if sneaking then invert = not invert end
        front_dir = invert and {x = -ldir.x, y = -ldir.y, z = -ldir.z} or ldir
    end

    local back_dir = {x = -front_dir.x, y = -front_dir.y, z = -front_dir.z}
    local param2   = core.dir_to_facedir(back_dir, CONFIG.ALLOW_VERTICAL_PLACEMENT)
    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)

    if place_pos then
        local meta  = core.get_meta(place_pos)
        local owner = placer and placer.get_player_name and placer:get_player_name() or ""
        meta:set_string("owner", (owner ~= "") and owner or "$unknown")
    end
    return placed_stack
end

local function make_deployer_back_idle()
    return CONFIG.TEX_CASING .. "^(" .. CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0)"
end

local function make_deployer_back_anim(reverse, anim_length)
    local bg = CONFIG.TEX_CASING
    local ov = CONFIG.TEX_SHAFT_OVERLAY
    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip
    if reverse then
        ov_strip = "[combine:16x64" ..
            ":0,0="  .. ov .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    else
        ov_strip = "[combine:16x64" ..
            ":0,0="  .. ov .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,1" ..
            ":0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,3"
    end
    return {
        name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")",
        animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = anim_length or 0.4},
    }
end

local function get_back_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.BACK_ANIM_TIERS) do
        if clamped <= tier.max_rpm then return tier.name end
    end
    return CONFIG.BACK_ANIM_TIERS[#CONFIG.BACK_ANIM_TIERS].name
end

local function get_active_deployer_node_name(param2, spin_dir, rpm, keep_ext)
    local back      = get_back_dir(param2)
    local axis_sign = back.x + back.y + back.z
    local vis       = ((spin_dir or 1) * axis_sign >= 0) and 1 or -1
    local dir_tag   = (vis == 1) and "cw" or "ccw"
    local tier_name = get_back_anim_tier_name(rpm)
    local base      = IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
    return keep_ext and (base .. "_ext") or base
end

local function format_deployer_glasses_info(pos, node)
    local meta   = core.get_meta(pos)
    local inv    = ensure_deployer_inventory(meta)
    local rpm    = meta:get_float("rpm")
    local supply = meta:get_int("network_supply_ku")
    local avail  = meta:get_int("rotational_power")
    local demand = meta:get_int("machine_demand_ku")
    if demand <= 0 then demand = get_deployer_demand_ku(rpm) end
    local active  = (supply > 0 and rpm >= CONFIG.MIN_RPM)
    local act_str = meta:get_string("last_action")
    if act_str == "" then act_str = active and "Ready" or "Idle" end

    local p1 = inv:get_stack("profit", 1)
    local p2 = inv:get_stack("profit", 2)

    local T = kinetica.api and kinetica.api.telemetry or nil
    if not T then return "" end

    return table.concat({
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  Machine: Mechanical Deployer",
        "│  ● STATE: " .. string.format("%s (%s)", active and "ACTIVE" or "IDLE", act_str),
        "├─ KINETIC NETWORK ─────────────────",
        T.kv_row("Speed",   string.format("%.1f RPM (Min %d RPM)", active and rpm or 0, CONFIG.MIN_RPM)),
        T.kv_row("Stress",  string.format("-%d KU Load (%d / %d KU Avail)", active and demand or 0, avail, supply)),
        "├─ INVENTORY ───────────────────────",
        T.kv_row("Held",    format_slot_summary(inv:get_stack("hand", 1))),
        T.kv_row("Profit 1", format_slot_summary(p1)),
        T.kv_row("Profit 2", format_slot_summary(p2)),
        "└───────────────────────────────────",
    }, "\n")
end

if kinetica.api and kinetica.api.telemetry then
    kinetica.api.telemetry.register_formatter(IDLE_NAME, format_deployer_glasses_info)
end

local function update_deployer_infotext(pos, meta, is_active, action_str)
    meta:set_string("glasses_info", format_deployer_glasses_info(pos, core.get_node(pos)))
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
        return
    end
    local inv   = ensure_deployer_inventory(meta)
    local h_str = format_slot_summary(inv:get_stack("hand", 1))
    if not is_active then
        meta:set_string("infotext", string.format("Mechanical Deployer: Idle [Hand: %s]", h_str))
    else
        local rpm    = meta:get_float("rpm")
        local demand = meta:get_int("machine_demand_ku")
        local tag    = (action_str and action_str ~= "") and (" [" .. action_str .. "]") or ""
        meta:set_string("infotext", string.format("Mechanical Deployer: Active%s [Hand: %s | -%d KU @ %.0f RPM]", tag, h_str, demand, rpm))
    end
end

local function set_deployer_idle(pos, node)
    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    ensure_deployer_inventory(meta)
    meta:set_string("last_action", "Idle")
    update_deployer_infotext(pos, meta, false, "")
    if node.name ~= IDLE_NAME then
        core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
    end
    sync_held_item_entity(pos, {name = IDLE_NAME, param2 = node.param2})
end

local function wake_deployer(pos, node, rpm, spin_dir)
    node = node or core.get_node(pos)
    local target = get_active_deployer_node_name(node.param2, spin_dir, rpm, is_extended_variant(node.name))
    if node.name ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
    end
    sync_held_item_entity(pos, {name = target, param2 = node.param2})
    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(get_cycle_interval(rpm))
    end
end

local function deployer_timer(pos)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if now >= meta:get_int("lit_until") then
        if kinetica.api and kinetica.api.network.update then
            kinetica.api.network.update(pos)
        elseif kinetica.update_network then
            kinetica.update_network(pos)
        end
        node = core.get_node(pos)
    end

    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local spin_dir  = meta:get_int("spin_dir")

    local is_powered, uni_rpm, uni_sup, uni_ava, uni_spin = kinetica.get_node_power(pos, meta)
    if not is_powered or uni_rpm < CONFIG.MIN_RPM then
        set_deployer_idle(pos, node)
        return false
    end
    -- Use the unified power values
    rpm = uni_rpm
    supply_ku = uni_sup
    spin_dir = uni_spin

    local target = get_active_deployer_node_name(node.param2, spin_dir, rpm, false)
    if strip_ext_suffix(node.name) ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
        node.name = target
    end

    local act = execute_deployer_cycle(pos, node)
    meta:set_string("last_action", (act ~= "") and act or "Ready")
    update_deployer_infotext(pos, meta, true, act)
    core.get_node_timer(pos):start(get_cycle_interval(rpm))
    return false
end

if kinetica.register_kinetic_machine then
    kinetica.register_kinetic_machine(IDLE_NAME, {
        can_ride_piston = true,
        get_demand_ku   = function(rpm) return get_deployer_demand_ku(rpm) end,
        has_axle_port   = function(node, d)
            local back = get_back_dir(node.param2)
            return (d.x == back.x and d.y == back.y and d.z == back.z)
        end,
        should_pause_contraption = function(pos, node)
            execute_deployer_cycle(pos, node)
            return false, nil
        end,
        set_idle = set_deployer_idle,
        wake     = wake_deployer,
    })
end

local function on_hopper_in(hopper_pos, to_pos)
    local h_inv  = core.get_meta(hopper_pos):get_inventory()
    local d_meta = core.get_meta(to_pos)
    local d_inv  = ensure_deployer_inventory(d_meta)

    for i = 1, h_inv:get_size("main") do
        local stack = h_inv:get_stack("main", i)
        if not stack:is_empty() then
            local single = stack:peek_item(1)
            if d_inv:room_for_item("hand", single) then
                d_inv:add_item("hand", single)
                stack:take_item(1)
                h_inv:set_stack("main", i, stack)
                sync_held_item_entity(to_pos, core.get_node(to_pos))
                update_deployer_infotext(to_pos, d_meta, d_meta:get_int("network_supply_ku") > 0, d_meta:get_string("last_action"))
                return true
            end
        end
    end
    return false
end

local function on_hopper_out(from_pos, to_hopper_pos)
    local d_meta = core.get_meta(from_pos)
    local d_inv  = ensure_deployer_inventory(d_meta)
    local h_inv  = core.get_meta(to_hopper_pos):get_inventory()

    for idx = 1, CONFIG.PROFIT_SLOTS do
        local p_stack = d_inv:get_stack("profit", idx)
        if not p_stack:is_empty() then
            local single = p_stack:peek_item(1)
            if h_inv:room_for_item("main", single) then
                h_inv:add_item("main", single)
                p_stack:take_item(1)
                d_inv:set_stack("profit", idx, p_stack)
                update_deployer_infotext(from_pos, d_meta, d_meta:get_int("network_supply_ku") > 0, d_meta:get_string("last_action"))
                return true
            end
        end
    end
    return false
end

local function give_to_player_or_drop(clicker, pos, stack)
    if stack:is_empty() then return end
    local pinv = clicker:get_inventory()
    if pinv then
        local leftover = pinv:add_item("main", stack)
        if not leftover:is_empty() then
            core.add_item(clicker:get_pos() or pos, leftover)
        end
    else
        core.add_item(pos, stack)
    end
end

local function on_deployer_rightclick(pos, node, clicker, itemstack)
    if not clicker or not clicker:is_player() then return itemstack end
    local pname = clicker:get_player_name()
    if core.is_protected(pos, pname) then return itemstack end

    local meta = core.get_meta(pos)
    local inv  = ensure_deployer_inventory(meta)
    local hand = inv:get_stack("hand", 1)

    if itemstack:is_empty() then
        if not hand:is_empty() then
            inv:set_stack("hand", 1, ItemStack(""))
            sync_held_item_entity(pos, node)
            update_deployer_infotext(pos, meta, meta:get_int("network_supply_ku") > 0, meta:get_string("last_action"))
            core.sound_play("default_dig_snappy", {pos = pos, max_hear_distance = 8, gain = 0.5}, true)
            return hand
        end
        for idx = 1, CONFIG.PROFIT_SLOTS do
            local p_stack = inv:get_stack("profit", idx)
            if not p_stack:is_empty() then
                inv:set_stack("profit", idx, ItemStack(""))
                update_deployer_infotext(pos, meta, meta:get_int("network_supply_ku") > 0, meta:get_string("last_action"))
                core.sound_play("default_dig_snappy", {pos = pos, max_hear_distance = 8, gain = 0.5}, true)
                return p_stack
            end
        end
        return itemstack
    end

    if hand:is_empty() then
        inv:set_stack("hand", 1, itemstack:take_item(itemstack:get_count()))
        sync_held_item_entity(pos, node)
        update_deployer_infotext(pos, meta, meta:get_int("network_supply_ku") > 0, meta:get_string("last_action"))
        core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 8, gain = 0.5}, true)
        return itemstack
    elseif hand:get_name() == itemstack:get_name() and hand:get_free_space() > 0 then
        local add_cnt = math.min(hand:get_free_space(), itemstack:get_count())
        hand:set_count(hand:get_count() + add_cnt)
        inv:set_stack("hand", 1, hand)
        itemstack:take_item(add_cnt)
        sync_held_item_entity(pos, node)
        update_deployer_infotext(pos, meta, meta:get_int("network_supply_ku") > 0, meta:get_string("last_action"))
        core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 8, gain = 0.5}, true)
        return itemstack
    else
        local old_hand = hand
        inv:set_stack("hand", 1, itemstack:take_item(itemstack:get_count()))
        give_to_player_or_drop(clicker, pos, old_hand)
        sync_held_item_entity(pos, node)
        update_deployer_infotext(pos, meta, meta:get_int("network_supply_ku") > 0, meta:get_string("last_action"))
        core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 8, gain = 0.5}, true)
        return itemstack
    end
end

local function on_after_dig(pos, _, oldmetadata)
    clear_held_item_entities(pos)
    if oldmetadata and oldmetadata.inventory then
        for _, listname in ipairs({"hand", "profit", "main", "output"}) do
            local list = oldmetadata.inventory[listname]
            if list then
                for _, item in ipairs(list) do
                    local st = ItemStack(item)
                    if not st:is_empty() then core.add_item(pos, st) end
                end
            end
        end
    end
    if kinetica.api and kinetica.api.network.schedule_update then
        kinetica.api.network.schedule_update(pos)
    elseif kinetica.schedule_network_update then
        kinetica.schedule_network_update(pos)
    end
end

local deployer_nodebox_retracted = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -2/16,  8/16,  8/16, 8/16},
        {-2/16, -2/16, -5/16,  2/16,  2/16, -2/16},
        {-3/16, -2/16, -7/16,  3/16,  2/16, -5/16},
        {-3/16, -2/16, -8/16, -1/16, -1/16, -7/16},
        { 1/16, -2/16, -8/16,  3/16, -1/16, -7/16},
        {-1/16,  1/16, -8/16,  1/16,  2/16, -7/16},
    },
}

local deployer_nodebox_extended = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -2/16,  8/16,  8/16, 8/16},
        {-2/16, -2/16, -9/16,  2/16,  2/16, -2/16},
        {-3/16, -2/16, -11/16, 3/16,  2/16, -9/16},
        {-3/16, -2/16, -12/16,-1/16, -1/16, -11/16},
        { 1/16, -2/16, -12/16, 3/16, -1/16, -11/16},
        {-1/16,  1/16, -12/16, 1/16,  2/16, -11/16},
    },
}

local deployer_selbox = {
    type = "fixed",
    fixed = {{-8/16, -8/16, -8/16, 8/16, 8/16, 8/16}},
}

local base_groups   = {handy = 1, pickaxey = 1, axey = 1, container = 2, kinetic_receiver = 1, kinetica_deployer = 1}
local active_groups = {handy = 1, pickaxey = 1, axey = 1, container = 2, kinetic_receiver = 1, kinetica_deployer = 1, not_in_creative_inventory = 1}

local function register_deployer_variant(node_name, desc, back_tile, is_base, is_ext)
    core.register_node(node_name, {
        description = desc,
        drawtype = "nodebox",
        paramtype = "light",
        paramtype2 = "facedir",
        is_ground_content = false,
        tiles = {
            CONFIG.TEX_CASING,
            CONFIG.TEX_CASING,
            CONFIG.TEX_CASING,
            CONFIG.TEX_CASING,
            back_tile,
            CONFIG.TEX_CASING,
        },
        node_box = is_ext and deployer_nodebox_extended or deployer_nodebox_retracted,
        selection_box = deployer_selbox,
        on_place = is_base and place_deployer or nil,
        on_rightclick = on_deployer_rightclick,
        drop = IDLE_NAME,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.5,
        sounds = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,

        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            meta:set_string("formspec", "")
            ensure_deployer_inventory(meta)
            set_deployer_idle(pos, core.get_node(pos))
            if kinetica.api and kinetica.api.network.schedule_update then
                kinetica.api.network.schedule_update(pos)
            elseif kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = on_after_dig,
        on_timer = deployer_timer,

        allow_metadata_inventory_put = function(pos, listname, _, stack, player)
            if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then return 0 end
            return (listname == "hand") and stack:get_count() or 0
        end,
        allow_metadata_inventory_take = function(pos, listname, _, stack, player)
            if player and player:is_player() then
                if core.is_protected(pos, player:get_player_name()) then return 0 end
                return stack:get_count()
            end
            return (listname == "profit") and stack:get_count() or 0
        end,
        on_metadata_inventory_put = function(pos)
            sync_held_item_entity(pos, core.get_node(pos))
        end,
        on_metadata_inventory_take = function(pos)
            sync_held_item_entity(pos, core.get_node(pos))
        end,
        _on_hopper_in  = on_hopper_in,
        _on_hopper_out = on_hopper_out,
    })
end

local idle_back = make_deployer_back_idle()
register_deployer_variant(
    IDLE_NAME,
    "Mechanical Deployer (Right-Click to Give/Take Item | Auto-Places, Shears & Attacks)",
    idle_back,
    true,
    false
)
register_deployer_variant(IDLE_NAME .. "_ext", "Mechanical Deployer", idle_back, false, true)

for _, tier in ipairs(CONFIG.BACK_ANIM_TIERS) do
    local back_cw  = make_deployer_back_anim(false, tier.length)
    local back_ccw = make_deployer_back_anim(true,  tier.length)

    local cw_name  = IDLE_NAME .. "_" .. tier.name .. "_cw"
    local ccw_name = IDLE_NAME .. "_" .. tier.name .. "_ccw"

    register_deployer_variant(cw_name,          "Mechanical Deployer", back_ccw, false, false)
    register_deployer_variant(cw_name .. "_ext","Mechanical Deployer", back_ccw, false, true)
    register_deployer_variant(ccw_name,          "Mechanical Deployer", back_cw,  false, false)
    register_deployer_variant(ccw_name .. "_ext","Mechanical Deployer", back_cw,  false, true)
end

core.register_lbm({
    label             = "Wake Kinetica Deployers & Held Items on chunk load",
    name              = "kinetica:wake_deployers_lbm",
    nodenames         = {"group:kinetica_deployer"},
    run_at_every_load = true,
    action = function(pos, node)
        local meta = core.get_meta(pos)
        meta:set_string("formspec", "")
        ensure_deployer_inventory(meta)
        sync_held_item_entity(pos, node)
    end,
})

core.register_craft({
    output = IDLE_NAME,
    recipe = {
        {"",               "mcl_core:gold_ingot",      ""},
        {"kinetica:shaft", "kinetica:gold_casing", "mcl_redstone:redstone"},
        {"",               "mcl_core:iron_ingot",      ""},
    },
})