local function register_chatcommand(cmd, desc, func, param)
    cmdlib.register_chatcommand(
            "cells " .. cmd,
            {
                description = desc,
                params = param,
                func = function(name, params)
                    local arena = arena.get_by_name(name)
                    if not arena then
                        return false, "Not inside exactly one arena"
                    end
                    if not arena:is_owner(name) and not is_cellestial(name) then
                        return false, "Not an owner of the current arena"
                    end
                    return func(arena, name, params)
                end
            }
    )
end
register_chatcommand(
        "clear",
        "Clear the current arena",
        function(arena)
            arena:clear()
            return true, "Arena cleared"
        end
)
register_chatcommand(
        "update",
        "Update the current arena",
        function(arena)
            arena:update()
            return true, "Arena updated"
        end
)
register_chatcommand(
        "randomize",
        "Randomize the current arena",
        function(arena, _, params)
            local threshold = conf.arena_defaults.threshold
            if params.threshold then
                threshold = tonumber(params.threshold)
                if not threshold or threshold < 0 or threshold > 1 then
                    return false, "Threshold needs to be a number from 0 to 1"
                end
            end
            arena:randomize(threshold)
            return true, "Arena randomized"
        end,
        "[threshold]"
)
register_chatcommand(
        "evolve",
        "Evolve/simulate the cells inside the current arena",
        function(arena, _, params)
            local steps = conf.arena_defaults.steps
            if params.steps then
                steps = tonumber(params.steps)
                if not steps or steps <= 0 or steps % 1 ~= 0 then
                    return false, "Steps need to be a positive integer number"
                end
            end
            arena:next_steps(steps)
            return true, "Simulated " .. steps .. " step" .. ((steps > 1 and "s") or "")
        end,
        "[steps]"
)
register_chatcommand(
        "start",
        "Start the simulation",
        function(arena, _, params)
            local steps_per_second = 1
            if params.steps_per_second then
                steps_per_second = tonumber(params.steps_per_second)
                if not steps_per_second or steps_per_second <= 0 then
                    return false, "Steps per second needs to be > 0"
                end
            end
            arena:start(steps_per_second)
            return true, "Started simulation with a speed of " .. steps_per_second .. " steps per second"
        end,
        "[steps_per_second]"
)
register_chatcommand(
        "stop",
        "Stop the simulation",
        function(arena)
            local s = arena:stop()
            if not s then
                return false, "Simulation not running"
            end
            return true, "Simulation stopped"
        end
)
local assign = {
    width_change = "x",
    height_change = "y",
    length_change = "z",
    x_move = "x",
    y_move = "y",
    z_move = "z"
}
local human_names = {
    width_change = "Width Change",
    height_change = "Height Change",
    length_change = "Length Change",
    x_move = "X move",
    y_move = "Y move",
    z_move = "Z move"
}
local dim_human_names = {
    width_change = "Width",
    height_change = "Height",
    length_change = "Length",
    x_move = "X",
    y_move = "Y",
    z_move = "Z"
}
register_chatcommand(
        "resize",
        "Resize arena",
        function(arena, _, params)
            local dim = arena:get_dim()
            for name, val in pairs(params) do
                val = tonumber(val)
                if not val or val % 1 ~= 0 then
                    return false, human_names[name] .. " needs to be an integer number"
                end
                local new_dim = dim[assign[name]] + val
                if new_dim < 3 then
                    return false, dim_human_names[name] .. " needs to be at least 3 (as it includes the borders)"
                end
                dim[assign[name]] = new_dim
            end
            if arena:resize(dim) then
                return true, "Arena resized to " .. (dim.x + 1) .. ", " .. (dim.y + 1) .. ", " .. (dim.z + 1)
            end
            return false, "Arena would collide with other arenas if resized"
        end,
        "<width_change> [height_change] [length_change]"
)
register_chatcommand(
        "move",
        "Move arena",
        function(arena, _, params)
            local position = modlib.table.copy(arena.min)
            for name, val in pairs(params) do
                val = tonumber(val)
                if not val or val % 1 ~= 0 then
                    return false, human_names[name] .. " needs to be an integer number"
                end
                local new_dim = position[assign[name]] + val
                position[assign[name]] = new_dim
            end
            if arena:move(position) then
                return true, "Arena moved to " .. position.x .. ", " .. position.y .. ", " .. position.z
            end
            return false, "Arena would collide with other arenas if moved"
        end,
        "<x_move> [y_move] [z_move]"
)

local function get_id(name, params)
    local id = tonumber(params.id)
    if not id or id % 1 ~= 0 or id < 0 then
        return false, "ID needs to be a non-negative integer number"
    end
    local arena = arena.get_by_id(id)
    if not arena then
        return false, "No area with the ID #" .. params.id
    end
    return true, arena
end

cmdlib.register_chatcommand(
        "cells get id",
        {
            params = "<id>",
            description = "Get the arena with the corresponding ID",
            func = function(name, params)
                local success, arena = get_id(name, params)
                if success then
                    return success, arena:info()
                end
                return success, arena
            end
        }
)

cmdlib.register_chatcommand(
        "cells teleport id",
        {
            params = "<id>",
            description = "Teleport to the arena with the corresponding ID",
            func = function(name, params)
                local success, arena = get_id(name, params)
                if success then
                    local player = minetest.get_player_by_name(name)
                    if not player then
                        return false, "You need to be online to teleport"
                    end
                    if not arena:is_owner(name) then
                        return false, "Not an owner of the corresponding arena"
                    end
                    arena:teleport(player)
                    return success, "Teleporting to: " .. arena:info()
                end
                return success, arena
            end
        }
)

cmdlib.register_chatcommand(
        "cells get player",
        {
            params = "[name]",
            description = "Get the arena the player is currently in",
            func = function(name, params)
                local arena = arena.get_by_name(params.name or name)
                if not arena then
                    return false, "Not inside an arena"
                end
                return true, arena:info()
            end
        }
)

local function get_pos(params)
    local vector = {}
    for _, param in ipairs({ "x", "y", "z" }) do
        vector[param] = tonumber(params[param])
        if not vector[param] then
            return false, param.upper() .. " needs to be a valid number"
        end
    end
    local arena = arena.get(params)
    if not arena then
        return false, "Not inside an arena"
    end
    return true, arena, vector
end

cmdlib.register_chatcommand(
        "cells get pos",
        {
            params = "<x> <y> <z>",
            description = "Get the arena at position",
            func = function(_, params)
                local success, arena = get_pos(params)
                if success then
                    return success, arena:info()
                end
                return success, arena
            end
        }
)

cmdlib.register_chatcommand(
        "cells teleport pos",
        {
            params = "<x> <y> <z>",
            description = "Teleport to the position",
            func = function(name, params)
                local success, arena, vector = get_pos(params)
                if success then
                    local player = minetest.get_player_by_name(name)
                    if not player then
                        return false, "You need to be online to teleport"
                    end
                    if not arena:get_position(name) then
                        return false, "Not an owner of the arena"
                    end
                    player:set_pos(vector)
                    return success, ("Teleporting to (%s, %s, %s)"):format(vector)
                end
                return success, arena
            end
        }
)

local function create_teleport_request(name, arena, property, value)
    if teleport_requests[name] then
        return false, "You already have a running request"
    end
    if arena:get_position(name) then
        return false, "No need for a teleport request"
    end
    local sent_to = {}
    local timers = {}
    for _, owner in ipairs(arena.meta.owners) do
        owner_ref = minetest.get_player_by_name(owner)
        if owner_ref then
            table.insert(sent_to, owner)
            minetest.chat_send_player(owner, "Player " .. minetest.get_color_escape_sequence(colors.cell.fill) .. name .. " " ..
                    minetest.get_color_escape_sequence("#FFFFFF") .. " requests to teleport to (%s, %s, %s).")
            timers[owner] = hud_timers.add_timer(owner, { name = name .. "'s request", duration = request_duration, color = colors.cell.fill:sub(2) })
        end
    end
    if #sent_to == 0 then
        return false, ("No owner (none of %s) online"):format(arena:owner_info())
    end
    local timer = hud_timers.add_timer(name, { name = "Teleport", duration = request_duration, color = colors.cell.edge:sub(2), on_complete = modlib.func.curry(remove_teleport_request, name)  })
    local request = { timer = timer, timers = timers, [property] = value }
    for _, owner in pairs(sent_to) do
        teleport_requests_last[owner] = request
    end
    teleport_requests[name] = request
    return true, "Teleport request sent to " .. table.concat(sent_to, ", ")
end

request_duration = 30
teleport_requests = {}
teleport_requests_last = {}

local function remove_request_receivers(name)
    local request = teleport_requests[name]
    for owner_name, timer in pairs(request.timers) do
        hud_timers.remove_timer_by_reference(owner_name, timer)
        local last_requests = teleport_requests_last[owner_name]
        local index = modlib.table.find(last_requests, name)
        if index then
            table.remove(last_requests, index)
        end
    end
end

local function remove_teleport_request(name)
    remove_request_receivers(name)
    teleport_requests[name] = nil
end

minetest.register_on_joinplayer(function(player)
    teleport_requests_last[player:get_player_name()] = {}
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    local request = teleport_requests[name]
    if request then
        remove_teleport_request(name, request)
    end
    local last_requests = teleport_requests_last[name]
    if last_requests then
        for _, requester_name in pairs(teleport_requests_last) do
            local request = teleport_requests[requester_name]
            if request then
                request.timers[name] = nil
                if modlib.table.is_empty(request.timers) then
                    remove_teleport_request(requester_name)
                end
            end
        end
        teleport_requests_last[name] = nil
    end
end)

cmdlib.register_chatcommand(
        "cells teleport request pos",
        {
            params = "<x> <y> <z>",
            description = "Send teleport request to owners of the arena",
            func = function(name, params)
                local success, arena, vector = get_pos(params)
                if success then
                    local player = minetest.get_player_by_name(name)
                    if not player then
                        return false, "You need to be online to teleport"
                    end
                    return create_teleport_request(name, arena, "pos", vector)
                end
                return success, arena
            end
        }
)

cmdlib.register_chatcommand(
        "cells teleport request id",
        {
            params = "<id>",
            description = "Send teleport request to owners of the arena",
            func = function(name, params)
                local id = tonumber(params.id)
                if not id or id % 1 ~= 0 or id < 0 then
                    return false, "ID needs to be a non-negative integer number"
                end
                local arena = arena.get_by_id(id)
                if not arena then
                    return false, "No arena with the ID #"..id
                end
                return create_teleport_request(name, arena, "id", id)
            end
        }
)

cmdlib.register_chatcommand(
        "cells teleport request player",
        {
            params = "<name>",
            description = "Send teleport request to player",
            func = function(name, params)
                local player = minetest.get_player_by_name(name)
                if not player then
                    return false, "You need to be online to teleport"
                end
                if teleport_requests[name] then
                    return false, "You already have a running request"
                end
                local target = minetest.get_player_by_name(params.name)
                if not target then
                    return false, "Player "..params.name.." is not online"
                end
                local request = {
                    name = params.name,
                    timer = hud_timers.add_timer(name, { name = "Teleport", duration = request_duration, color = colors.cell.edge:sub(2), on_complete = modlib.func.curry(remove_teleport_request, name) }),
                    timers = { [params.name] = hud_timers.add_timer(params.name, { name = name .. "'s request", duration = request_duration, color = colors.cell.fill:sub(2) }) },
                }
                teleport_requests[name] = request
                table.insert(teleport_requests_last[params.name], name)
            end
        }
)

cmdlib.register_chatcommand(
        "cells teleport accept",
        {
            params = "[name]",
            description = "Accept teleport request of player or last request",
            func = function(name, params)
                local requester_name = params.name
                if not requester_name then
                    requester_name = teleport_requests_last[name]
                    if not requester_name then
                        return false, "No outstanding last request"
                    end
                end
                local request = teleport_requests[params.name]
                if params.name then
                    request = teleport_requests[params.name]
                    if not request or not request.timers[name] then
                        return false, "No outstanding request by player " .. params.name
                    end
                else
                    request = teleport_requests_last[name]
                    if not request then
                        return false, "No outstanding last request"
                    end
                end
                remove_teleport_request(requester_name)
                local pos, message
                if request.pos then
                    pos = request.pos
                    message = ("Player %s teleported to %s, %s, %s"):format(requester_name, tonumber(request.pos.x), tonumber(request.pos.y), tonumber(request.pos.z))
                elseif request.name then
                    pos = minetest.get_player_by_name(request.name):get_pos()
                    message = ("Player %s teleported to %s"):format(requester_name, request.name)
                else
                    arena.get_by_id(request.id):teleport(requester_name)
                    return true, ("Player %s teleported to %s"):format(requester_name, request.name)
                end
                minetest.get_player_by_name(requester_name):set_pos(pos)
                return true, message
            end
        }
)

function create_arena(sendername, params, nums)
    for _, param in ipairs({ "x", "y", "z", "width", "height", "length" }) do
        if not nums[param] then
            local number = tonumber(params[param])
            if not number or number % 1 ~= 0 then
                return false, modlib.text.upper_first(param) .. " needs to be a valid integer number"
            end
            nums[param] = number
        end
    end
    for _, param in ipairs({ "width", "height", "length" }) do
        if nums[param] < 3 then
            return false, modlib.text.upper_first(param) .. " needs to be positive and at least 3"
        end
    end
    local name = params.name
    local owners = params.owners or { sendername }
    for _, owner in ipairs(owners) do
        if not minetest.get_player_by_name(owner) then
            return false, "Player " .. owner .. " is not online. All owners need to be online."
        end
    end
    local min = { x = nums.x, y = nums.y, z = nums.z }
    local max = { x = nums.x + nums.width, y = nums.y + nums.height, z = nums.z + nums.length }
    if arena.overlaps(min, max) then
        return false, "Selected area intersects with existing arenas"
    end
    local arena = arena.new(min, vector.subtract(max, 1), { name = name, owners = owners })
    arena:teleport(minetest.get_player_by_name(owners[1]))
    if arena then
        return true, "Arena created"
    end
    return false, "Failed to create arena, would intersect with other arenas"
end

cmdlib.register_chatcommand(
        "cells create there",
        {
            params = "<x> <y> <z> <width> <height> <length> [name] {owners}",
            description = "Create a new arena",
            func = function(sendername, params)
                return create_arena(sendername, params, {})
            end
        }
)

cmdlib.register_chatcommand(
        "cells create here",
        {
            params = "<width> <height> <length> [name] {owners}",
            description = "Create a new arena",
            func = function(sendername, params)
                local player = minetest.get_player_by_name(sendername)
                if not player then
                    return false, "You need to be online in-game to use the command."
                end
                return create_arena(sendername, params, vector.floor(player:get_pos()))
            end
        }
)

cmdlib.register_chatcommand(
        "cells arenas list",
        {
            params = "[name]",
            description = "Lists all arenas of a player",
            func = function(sendername, params)
                local name = sendername or params.name
                local ids = arena.list_by_name(name)
                if not ids then
                    return false, "Player " .. name .. " is not online."
                end
                if #ids == 0 then
                    return true, "Player " .. name .. " does not have any arenas."
                end
                modlib.table.map(ids, arena.info)
                table.insert(ids, 1, "Player " .. name .. " owns the following arenas:")
                return true, table.concat(ids, "\n")
            end
        }
)

function show_arenas_formspec(sendername, name)
    local ids = arena.list_by_name(name) or {}
    modlib.table.map(ids, arena.formspec_table_info)
    local table_height = math.min(3, #ids * 0.35)
    local message, fs_table
    if #ids == 0 then
        message = "Player " .. name .. " does not have any arenas."
        fs_table = ""
        table_height = 0.25
    else
        message = "Player " .. name .. " owns the following arenas (double-click to teleport):"
        fs_table = ([[
tablecolumns[color;text,align=inline;color;text,align=inline;color;text,align=inline;text,align=inline]
tableoptions[background=#00000000;highlight=#00000000;border=false]
table[0.15,1.6;7.6,%s;arenas;%s]
]]):format(table_height, table.concat(ids, ","))
        table_height = table_height + 0.25
    end
    minetest.show_formspec(sendername, "cellestial:arenas",
            ([[
size[8,%s]
real_coordinates[true]
box[0,0;8,1;%s]
label[0.25,0.5;Arenas of player]
field[2,0.25;2,0.5;player;;%s]
field_close_on_enter[player;false]
button[4.25,0.25;1,0.5;show;Show]
label[0.25,1.35;%s]
%simage_button_exit[7.25,0.25;0.5,0.5;cmdlib_cross.png;close;]
]]):format(table_height + 1.5, colors.cell.fill, minetest.formspec_escape(name), minetest.formspec_escape(message), fs_table))
end

cmdlib.register_chatcommand(
        "cells arenas show",
        {
            params = "[name]",
            description = "Shows all arenas of a player",
            func = function(sendername, params)
                show_arenas_formspec(sendername, params.name or sendername)
                return true
            end
        }
)

modlib.minetest.register_form_listener("cellestial:arenas", function(player, fields)
    if fields.quit then
        return
    end

    local name
    if fields.player then
        -- not using key_enter_field
        name = fields.player
    end
    if not name or name:len() == 0 then
        name = player:get_player_name()
    end
    if fields.arenas then
        local event = minetest.explode_table_event(fields.arenas)
        if event.type == "DCL" then
            local id = arena.list_ids_by_name(name)[event.row]
            if id then
                local arena = arena.get_by_id(id)
                if arena:get_position(player:get_player_name()) then
                    arena:teleport(player)
                else
                    create_teleport_request(player:get_player_name(), arena, "id", id)
                end
            end
        end
    end
    show_arenas_formspec(player:get_player_name(), name)
end)

cmdlib.register_chatcommand(
        "cells help",
        {
            description = "Shows help",
            func = function(name, _)
                show_help(name)
            end
        }
)

register_chatcommand(
        "owner add",
        "Add owner to the current arena",
        function(arena, name, param)
            local param_name = param.name or name
            local namepos = arena:get_position(name)
            if not namepos then
                return false, "Only owners can add others"
            end
            local position
            if param.position then
                position = tonumber(param.position)
                if not position or position % 1 ~= 0 or position < namepos or position > #arena.meta.owners + 1 then
                    return false, "Position needs to be an integer number between " .. namepos .. " (your position) and " .. #arena.meta.owners + 1
                end
            end
            local success = arena:add_owner(name, position)
            if success == false then
                return false, "Player " .. param_name .. " is not online"
            end
            return true, "Added player " .. param_name .. " to arena #" .. arena.id .. ", owners now: " .. table.concat(arena.meta.owners, ", ")
        end,
        "[name] [position]"
)

register_chatcommand(
        "owner remove",
        "Remove owner from current arena",
        function(arena, name, param)
            local param_name = param.name or name
            local namepos = arena:get_position(name)
            local parampos = arena:get_position(param_name)
            if not (namepos and parampos) then
                return false, "Both players need to be owners"
            end
            if namepos > parampos then
                return false, "Player " .. param_name .. " is in a higher position"
            end
            local success = arena:remove_owner(param_name)
            if success == false then
                return false, "Player " .. param_name .. " is not online"
            end
            return true, "Removed player " .. param_name .. " from arena #" .. arena.id .. ", owners now: " .. table.concat(arena.meta.owners, ", ")
        end,
        "[name]"
)

register_chatcommand(
        "set_name",
        "Set name of current arena",
        function(arena, name, params)
            local namepos = arena:get_position(name)
            if not namepos or namepos > 1 then
                return false, "Only the first owner can change the name."
            end
            local oldname = arena.meta.name
            arena.meta.name = params.name
            arena:store()
            return true, ('Name changed from "%s" to "%s"'):format(oldname, arena.meta.name)
        end,
        "<name>"
)
