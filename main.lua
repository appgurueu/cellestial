minetest.register_privilege("cellestial", {
    description = "Can manage cellestial arenas",
    give_to_admin = true,
    give_to_singleplayer = true
})
function is_cellestial(name)
    return minetest.check_player_privs(name, { cellestial = true })
end
local creative = conf.creative
arenas = {}
colors = conf.colors
function add_area(params)
    table.insert(arenas, arena.new(params))
end

function get_tile(name)
    return "cellestial_fill.png^[multiply:" .. colors[name].fill .. "^(cellestial_edge.png^[multiply:" .. colors[name].edge .. ")"
end
local border = get_tile("border")
local cell = get_tile("cell")
local max_steps = conf.max_steps

local ces = minetest.get_color_escape_sequence
local _help_content = {
    2, 1, "About",
    1, 2, 'A mod made by LMD aka appguru(eu)',
    2, 1, "Automata",
    1, 2, 'Cellular automata work using simple principles:',
    1, 2, '- the world is made out of cells, which are dead or alive',
    1, 2, '- based on their neighbors, cells die or new ones are born',
    2, 1, "Instructions",
    1, 2, [[How to simulate cellular automata using Cellestial.
Remember that you can open this dialog using "/cells help".]],
    3, 2, "Chat",
    1, 3, [[The chat is where you talk with others and send commands.
Start your message with @name to send it to a player.
Use @#id to send it to all owners of the arena.]],
    3, 2, "Commands",
    1, 3,
    [[Use chatcommands to manage your arena and simulation.
Send "/help cells" in chat to see further help.]],
    3, 2, "Arenas",
    1, 3,
    [[Arenas are areas delimited by undestructible borders.
Only their owners can modify them.]],
    3, 2, "Cells",
    1, 3, "Cells live in your arenas. You can place & dig them at any time.",
    3, 2, "Wand",
    1, 3,
    [[A powerful tool controlling the simulation.
Right-click to configure, left-click to apply.
Possible modes / actions are:
- Advance: Simulates steps
- Simulate: Starts / stops simulation, steps per second
- Place: Living cell ray, steps are length
- Dig: Dead cell ray, steps are length
Rules work as follows:
- Short notation: As described by Bayes. Uses base 27.
- Neighbors: Numbers signify the amount of neighbors.]],
}
for i = 1, #_help_content, 3 do
    _help_content[i] = ({ "#FFFFFF", colors.cell.fill, colors.cell.edge })[_help_content[i]]
end
local help_content = {}
for i = 1, #_help_content, 3 do
    local parts = modlib.text.split(_help_content[i + 2], "\n")
    for _, part in ipairs(parts) do
        table.insert(help_content, _help_content[i])
        table.insert(help_content, _help_content[i + 1])
        table.insert(help_content, minetest.formspec_escape(part))
    end
end
help_formspec = ([[
size[12,8]
real_coordinates[true]
box[0,0;12,1;%s]
label[0.25,0.5;%sCellestial%s - cellular automata for Minetest]
tablecolumns[color;tree;text]
tableoptions[background=#00000000;highlight=#00000000;border=false;opendepth=2]
table[-0.15,1.25;11.9,6.5;help;%s]
image_button_exit[11.25,0.25;0.5,0.5;cmdlib_cross.png;close;]
]]):format(colors.cell.fill, ces(colors.cell.edge), ces(colors.cell.edge), table.concat(help_content, ","))

function show_help(name)
    minetest.show_formspec(name, "cellestial:help", help_formspec)
end

-- Almost indestructible borders
minetest.register_node("cellestial:border", {
    description = "Arena Border",
    post_effect_color = colors.border.fill,
    sunlight_propagates = true,
    light_source = minetest.LIGHT_MAX,
    tiles = { border },
    groups = { not_in_creative_inventory = 1, fall_damage_add_percent = -100 },
    can_dig = function()
        return false
    end,
    on_dig = function()
    end,
    on_place = function()
    end,
    on_use = function()
    end,
    on_secondary_use = function()
    end
})
-- Cells, item can be used for digging & placing
minetest.register_node("cellestial:cell", {
    description = "Cell",
    -- TODO find a proper way for borders connecting to cells
    post_effect_color = "#00000000",
    sunlight_propagates = true,
    light_source = minetest.LIGHT_MAX,
    tiles = { cell },
    groups = { oddly_breakable_by_hand = 3, fall_damage_add_percent = -100 },
    range = (creative and 20) or 4,
    on_dig = function(pos, node, digger)
        if minetest.is_protected(pos, digger:get_player_name()) then
            return
        end
        local arena = arena.get(pos)
        if arena and arena:is_owner(digger:get_player_name()) then
            arena:set_cell(pos)
        else
            return minetest.node_dig(pos, node, digger)
        end
        if not creative then
            local leftover = digger:get_inventory():add_item("main", "cellestial:cell")
            if leftover then
                minetest.add_item(pos, leftover)
            end
        end
    end,
    on_place = function(itemstack, placer, pointed_thing)
        local pos = pointed_thing.above
        if not conf.place_inside_player then
            for _, player in pairs(minetest.get_connected_players()) do
                local ppos = player:get_pos()
                ppos.y = ppos.y + player:get_properties().eye_height
                if ppos.x >= pos.x and ppos.y >= pos.y and ppos.z >= pos.z and ppos.x <= pos.x +1 and ppos.y <= pos.y + 1 and ppos.z <= pos.z + 1 then
                    return itemstack
                end
            end
        end
        if minetest.is_protected(pos, placer:get_player_name()) then
            return
        end
        local arena = arena.get(pos)
        if arena and arena:is_content(pos) and arena:is_owner(placer:get_player_name()) then
            arena:set_cell(pos, true)
        elseif regular_placing then
            return minetest.item_place_node(itemstack, placer, pointed_thing)
        end
        if not creative then
            itemstack:take_item()
            return itemstack
        end
    end
})
local serialized_modes = { advance = "a", simulate = "s", place = "p", dig = "d" }
local function serialize_rule(rule)
    local number = 0
    for i = 26, 0, -1 do
        number = number * 2
        if rule[i] then
            number = number + 1
        end
    end
    return modlib.number.tostring(number, 36)
end
function serialize_wand(wand, meta)
    meta:set_string("mode", serialized_modes[wand.mode])
    meta:set_string("steps", modlib.number.tostring(wand.steps, 36))
    meta:set_string("death", serialize_rule(wand.rule.death))
    meta:set_string("birth", serialize_rule(wand.rule.birth))
end
local deserialized_modes = modlib.table.flip(serialized_modes)
local function deserialize_rule(text)
    local number = tonumber(text, 36)
    local rule = {}
    for i = 0, 26 do
        local digit = math.floor(number % 2)
        rule[i] = digit == 1
        number = math.floor(number / 2)
    end
    return rule
end
function deserialize_mode(meta)
    return deserialized_modes[meta:get("mode")]
end
function deserialize_steps(meta)
    return tonumber(meta:get("steps"), 36)
end
function deserialize_full_rule(meta)
    return { death = deserialize_rule(meta:get("death")), birth = deserialize_rule(meta:get("birth")) }
end
function deserialize_wand(meta)
    return {
        mode = deserialize_mode(meta),
        steps = deserialize_steps(meta),
        rule = deserialize_full_rule(meta)
    }
end
local c0, ca, cA = ("0"):byte(), ("a"):byte(), ("A"):byte()
function read_rule(text)
    if text:len() ~= 4 then
        return nil
    end
    local nums = { text:byte(1), text:byte(2), text:byte(3), text:byte(4) }
    for i, num in pairs(nums) do
        if num >= ca then
            num = num - ca + 10
        elseif num >= cA then
            num = num - cA + 10
        else
            num = num - c0
        end
        if num < 0 or num > 26 then
            return nil
        end
        nums[i] = num
    end
    if nums[1] > nums[2] or nums[3] > nums[4] then
        return nil
    end
    local min_env, max_env, min_birth, max_birth = unpack(nums)
    local rule = { death = {}, birth = {} }
    for i = 0, 26 do
        rule.death[i] = not (i >= min_env and i <= max_env)
        rule.birth[i] = i >= min_birth and i <= max_birth
    end
    return rule
end
local dfunc = modlib.number.default_digit_function
function find_rule(rule)
    local death, birth = rule.death, rule.birth
    -- Finding min. env. and max. env
    local min_env, max_env
    local i = 0
    while i <= 26 and death[i] do
        i = i + 1
    end
    min_env = i
    while i <= 26 and not death[i + 1] do
        i = i + 1
    end
    max_env = i
    for i = max_env + 1, 26 do
        if not death[i] then
            return
        end
    end
    -- Finding min. birth and max. birth
    local min_birth, max_birth
    i = 0
    while i <= 26 and not birth[i] do
        i = i + 1
    end
    min_birth = i
    while i <= 26 and birth[i + 1] do
        i = i + 1
    end
    max_birth = i
    for i = max_birth + 1, 26 do
        if birth[i] then
            return
        end
    end
    return dfunc(min_env) .. dfunc(max_env) .. dfunc(min_birth) .. dfunc(max_birth)
end
local default_wand = {
    mode = "advance",
    steps = 1,
    rule = read_rule("5766")
}
local ray_steps = 10
function ray_function(cell)
    return function(steps, player, arena)
        local eye_offset = player:get_eye_offset()
        eye_offset.y = eye_offset.y + player:get_properties().eye_height
        local lookdir = player:get_look_dir()
        local start = vector.add(vector.add(player:get_pos(), eye_offset), lookdir)
        local step = vector.multiply(lookdir, 1 / ray_steps)
        local set = {}
        local set_count = 0
        local pos = start
        for _ = 1, ray_steps * steps * math.sqrt(3) do
            local rounded = vector.round(pos)
            local min, max = arena.min, arena.max
            if rounded.x <= min.x or rounded.y <= min.y or rounded.z <= min.z or rounded.x >= max.x or rounded.y >= max.y or rounded.z >= max.z then
                break
            end
            local index = arena.voxelarea:indexp(rounded)
            if not set[index] then
                set[index] = true
                arena:set_cell(rounded, cell)
                set_count = set_count + 1
                if set_count == steps then
                    break
                end
            end
            pos = vector.add(pos, step)
        end
    end
end
actions = {
    advance = function(steps, _, arena, meta)
        arena:next_steps(steps, deserialize_full_rule(meta))
    end,
    simulate = function(steps, _, arena, meta)
        arena:simulate(steps, deserialize_full_rule(meta))
    end,
    place = ray_function(true),
    dig = ray_function()
}
function show_wand_formspec(name, wand)
    local function get_image(n)
        if wand.rule.death[n] then
            if wand.rule.birth[n] then
                return "cellestial_fertility.png"
            end
            return "cellestial_border.png"
        else
            if wand.rule.birth[n] then
                return "cellestial_cell.png"
            end
            return "cellestial_environment.png"
        end
    end
    local neighbor_buttons = {
        "image_button[5.25,1.25;0.5,0.5;" .. get_image(0) .. ";n0;0;false;false]",
        "image_button[6.25,1.25;0.5,0.5;" .. get_image(1) .. ";n1;1;false;false]",
        "image_button[7.25,1.25;0.5,0.5;" .. get_image(2) .. ";n2;2;false;false]"
    }
    for y = 0, 2 do
        for x = 0, 7 do
            local n = y * 8 + x + 3
            local t = get_image(n)
            table.insert(neighbor_buttons, ("image_button[%s,%s;0.5,0.5;%s;n%d;%d;false;false]"):format(tostring(0.25 + x * 1), tostring(2 + y * 0.75), t, n, n))
        end
    end
    neighbor_buttons = table.concat(neighbor_buttons, "\n")
    minetest.show_formspec(name, "cellestial:wand",
            ([[
size[8,5]
real_coordinates[true]
box[0,0;8,1;%s]
label[0.25,0.5;Mode:]
dropdown[1,0.25;1.5,0.5;mode;Advance,Simulate,Place,Dig;%d]
label[2.75,0.5;Steps:]
button[3.5,0.25;0.5,0.5;steps_minus;-]
field[4,0.25;0.75,0.5;steps;;%d]
field_close_on_enter[steps;false]
button[4.75,0.25;0.5,0.5;steps_plus;+]
button[5.75,0.25;1,0.5;apply;Apply]
image_button_exit[7.25,0.25;0.5,0.5;cmdlib_cross.png;close;]
label[0.25,1.5;Rule:]
field[1,1.25;1,0.5;rule;;%s]
button[2.25,1.25;1,0.5;set;Set]
label[3.75,1.5;Neighbors:]
%s
image[0.25,4.25;0.5,0.5;cellestial_border.png]
label[1,4.5;Death]
image[2.25,4.25;0.5,0.5;cellestial_environment.png]
label[3,4.5;Survival]
image[4.25,4.25;0.5,0.5;cellestial_fertility.png]
label[5,4.5;Birth]
image[6.25,4.25;0.5,0.5;cellestial_cell.png]
label[7,4.5;Both]
]]):format(colors.cell.fill, ({ advance = 1, simulate = 2, place = 3, dig = 4 })[wand.mode], wand.steps, find_rule(wand.rule) or "", neighbor_buttons))
end

function ensure_wand(meta)
    if not meta:get("mode") or not meta:get("steps") or not meta:get("death") or not meta:get("birth") then
        serialize_wand(default_wand, meta)
        return true
    end
end

function obtain_wand(meta)
    local wand
    if ensure_wand(meta) then
        wand = modlib.table.copy(default_wand)
    else
        wand = deserialize_wand(meta)
    end
    return wand
end

function wand_on_secondary_use(itemstack, user, pointed_thing)
    local name = user:get_player_name()
    local meta = itemstack:get_meta()
    show_wand_formspec(name, obtain_wand(meta))
    return itemstack
end

-- Wand
minetest.register_tool("cellestial:wand", {
    description = "Cellestial Wand",
    inventory_image = "cellestial_wand.png",
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local arena = arena.get_by_name(name)
        if arena and arena:is_owner(name) then
            local meta = itemstack:get_meta()
            ensure_wand(meta)
            local mode = deserialize_mode(meta)
            actions[mode](deserialize_steps(meta), user, arena, meta)
        end
        return itemstack
    end,
    on_secondary_use = wand_on_secondary_use,
    on_place = wand_on_secondary_use
})
modlib.minetest.register_form_listener("cellestial:wand", function(player, fields)
    if fields.quit then
        return
    end

    local wielded_item = player:get_wielded_item()
    local meta = wielded_item:get_meta()
    local wand = obtain_wand(meta)
    if fields.steps then
        local steps = tonumber(fields.steps)
        if steps then
            wand.steps = steps
        end
    end
    if fields.mode then
        local lower = fields.mode:lower()
        if serialized_modes[lower] then
            wand.mode = lower
        end
    end
    if fields.apply then
        local arena = arena.get_by_player(player)
        if arena and arena:is_owner(player:get_player_name()) then
            actions[wand.mode](wand.steps, player, arena, meta)
        end
    elseif fields.set or fields.key_enter_field == "rule" then
        local rule = read_rule(fields.rule)
        if rule then
            wand.rule = rule
        end
    elseif fields.steps_minus then
        wand.steps = wand.steps - 1
    elseif fields.steps_plus then
        wand.steps = wand.steps + 1
    else
        for field, _ in pairs(fields) do
            if modlib.text.starts_with(field, "n") then
                local n = tonumber(field:sub(2))
                if n then
                    if wand.rule.birth[n] then
                        if wand.rule.death[n] then
                            wand.rule.death[n] = false
                        else
                            wand.rule.death[n] = true
                            wand.rule.birth[n] = false
                        end
                    else
                        if wand.rule.death[n] then
                            wand.rule.death[n] = false
                        else
                            wand.rule.death[n] = true
                            wand.rule.birth[n] = true
                        end
                    end
                end
                break
            end
        end
    end
    wand.steps = math.max(1, math.min(wand.steps, max_steps))
    serialize_wand(wand, meta)
    player:set_wielded_item(wielded_item)
    if not fields.close then
        show_wand_formspec(player:get_player_name(), wand)
    end
end)

local adv_chat = minetest.global_exists("adv_chat") and adv_chat

minetest.register_on_joinplayer(function(player)
    arena.get(player:get_pos())
    local name = player:get_player_name()
    for _, id in pairs(arena.list_ids_by_name(name)) do
        local role = "#" .. id
        if adv_chat and adv_chat.roles[role] then
            adv_chat.add_role(name, role)
        end
    end
end)

if adv_chat then
    adv_chat.roles.minetest.color = colors.cell.fill
end
