local adv_chat = minetest.global_exists("adv_chat") and adv_chat
local speedup = cellestial.conf.speedup
local mapcache = cellestial.conf.mapcache
local c_cell = minetest.get_content_id("cellestial:cell")
local c_border = minetest.get_content_id("cellestial:border")
local c_air = minetest.CONTENT_AIR
local area_store = AreaStore()
local area_store_path = minetest.get_worldpath() .. "/data/cellestial.dat"
function load_store()
    if modlib.file.exists(area_store_path) then
        area_store:from_file(area_store_path)
    end
end
load_store()
local delta = 0
function store_store()
    if delta > 0 then
        area_store:to_file(area_store_path)
        delta = 0
    end
end
modlib.minetest.register_globalstep(60, function()
    if delta > 10 then
        store_store()
    end
end)
modlib.minetest.register_globalstep(600, store_store)
minetest.register_on_shutdown(store_store)
-- TODO use set_cell and the like for the performant step

arenas = {}
function unload_arenas()
    for id, arena in pairs(arenas) do
        local owner_online = false
        for _, owner in pairs(arena.meta.owners) do
            if minetest.get_player_by_name(owner) then
                owner_online = true
                break
            end
        end
        if not owner_online then
            arenas[id] = nil
        end
    end
end
modlib.minetest.register_globalstep(60, unload_arenas)
simulating = {}
function calculate_offsets(voxelarea)
    --[[
        Lua API: "Y stride and z stride of a flat array"
        +x          +1
        -x          -1
        +y          +ystride
        -y          -ystride
        +z          +zstride
        -z          -zstride
    ]]
    local ystride, zstride = voxelarea.ystride, voxelarea.zstride
    local offsets = {}
    for x = -1, 1, 1 do
        for y = -ystride, ystride, ystride do
            for z = -zstride, zstride, zstride do
                local offset = x + y + z
                if offset ~= 0 then
                    table.insert(offsets, offset)
                end
            end
        end
    end
    return offsets
end

function initialize_cells(self)
    local cells = {}
    self.cells = cells
    for index, data in pairs(self.area) do
        if data == c_cell then
            cells[index] = true
        end
    end
end

function read_from_map(self)
    self.voxelmanip = minetest.get_voxel_manip(self.min, self.max)
    local emin, emax = self.voxelmanip:read_from_map(self.min, self.max)
    self.voxelarea = VoxelArea:new { MinEdge = emin, MaxEdge = emax }
    self.offsets = calculate_offsets(self.voxelarea)
    self.area = self.voxelmanip:get_data()
end

function overlaps(min, max)
    local areas = area_store:get_areas_in_area(min, max, true, true, false)
    if not modlib.table.is_empty(areas) then
        return true
    end
    return false
end

function update(self)
    read_from_map(self)
    if speedup then
        initialize_cells(self)
        calculate_neighbors(self)
    end
    remove_area(self)
end

function create_base(min, max)
    local obj = { min = min, max = max }
    update(obj)
    return setmetatable(obj, { __index = getfenv(1), __call = getfenv(1) })
end

function create_role(self)
    local role = "#" .. self.id
    if adv_chat and not adv_chat.roles[role] then
        adv_chat.register_role(role, { title = self.meta.name, color = cellestial.colors.cell.edge })
        for _, owner in pairs(self.meta.owners) do
            if minetest.get_player_by_name(owner) then
                adv_chat.add_role(owner, role)
            end
        end
    end
end

function new(min, max, meta)
    local obj = create_base(min, max)
    if not obj then
        return obj
    end
    meta.name = meta.name or cellestial.conf.arena_defaults.name
    obj.meta = meta
    obj.id = store(obj)
    create_role(obj)
    modlib.table.foreach_value(meta.owners, modlib.func.curry(add_owner_to_meta, obj))
    arenas[obj.id] = obj
    obj:reset()
    store_store()
    return obj
end

function deserialize(self, data)
    self.meta = minetest.parse_json(data)
end

function load(id, min, max, data)
    local obj = create_base(min, max)
    obj.id = id
    deserialize(obj, data)
    arenas[id] = obj
    create_role(obj)
    return obj
end

function create_from_area(area)
    return load(area.id, area.min, area.max, area.data)
end

function owner_info(self)
    return table.concat(self.meta.owners, ", ")
end

function info(self)
    local dim = get_dim(self)
    return ('Arena #%s "%s" by %s from (%s, %s, %s) to (%s, %s, %s) - %s wide, %s tall and %s long'):format(
            self.id,
            self.meta.name,
            owner_info(self),
            self.min.x,
            self.min.y,
            self.min.z,
            self.max.x,
            self.max.y,
            self.max.z,
            dim.x,
            dim.y,
            dim.z
    )
end

function formspec_table_info(self)
    local dim = get_dim(self)
    return table.concat(modlib.table.map({
        cellestial.colors.cell.fill,
        "#" .. self.id,
        cellestial.colors.cell.edge,
        self.meta.name,
        "#FFFFFF",
        owner_info(self),
        table.concat({ self.min.x, self.min.y, self.min.z }, ", ") .. " - " .. table.concat({ self.max.x, self.max.y, self.max.z }, ", ") ..
                " (" .. table.concat({ dim.x, dim.y, dim.z }, ", ") .. ")"
    }, minetest.formspec_escape), ",")
end

function serialize(self)
    return minetest.write_json(self.meta)
end

function store(self)
    delta = delta + 1
    return area_store:insert_area(self.min, self.max, serialize(self), self.id)
end

function is_owner(self, other_owner)
    return modlib.table.contains(self.meta.owners, other_owner)
end

function get_position(self, name)
    if cellestial.is_cellestial(name) then
        return 1
    end
    return is_owner(self, name)
end

function serialize_ids(ids)
    return table.concat(ids, ",")
end

function store_ids(meta, ids)
    meta:set_string("cellestial_arena_ids", serialize_ids(ids))
end

function deserialize_ids(text)
    return modlib.table.map(modlib.text.split(text, ","), tonumber)
end

function load_ids(meta)
    local ids = meta:get_string("cellestial_arena_ids")
    return deserialize_ids(ids)
end

function owner_action(func)
    return function(self, name)
        local player = minetest.get_player_by_name(name)
        if not player then
            return
        end
        local meta = player:get_meta()
        local ids = load_ids(meta)
        local index = modlib.table.binary_search(ids, self.id)
        local err = func(self, ids, index)
        if err ~= nil then
            return err
        end
        store_ids(meta, ids)
        return true
    end
end

add_owner_to_meta = owner_action(
        function(self, ids, index)
            if index > 0 then
                return false
            end
            table.insert(ids, -index, self.id)
        end
)
function add_owner(self, name, index)
    local success = add_owner_to_meta(self, name)
    if success == nil then
        return
    end
    if adv_chat then
        adv_chat.add_role(name, "#" .. self.id)
    end
    if not modlib.table.contains(self.meta.owners) then
        table.insert(self.meta.owners, index or (#self.meta.owners + 1), name)
    end
    return success
end

remove_owner_from_meta = owner_action(
        function(self, ids, index)
            if index < 1 then
                return false
            end
            table.remove(ids, index)
        end
)
function remove_owner(self, name)
    local success = remove_owner_from_meta(self, name)
    if success == nil then
        return
    end
    if adv_chat then
        adv_chat.remove_role(name, "#" .. self.id)
    end
    local owner_index = modlib.table.contains(self.meta.owners, name)
    if owner_index then
        table.remove(self.meta.owners, owner_index)
    end
end

function set_owners(self, owners)
    local owner_set = modlib.table.set(owners)
    local self_owner_set = modlib.table.set(self.owners)
    local to_be_added = modlib.table.difference(owner_set, self_owner_set)
    local to_be_removed = modlib.table.difference(self_owner_set, owner_set)
    modlib.table.foreach_key(to_be_added, modlib.func.curry(add_owner, self))
    modlib.table.foreach_key(to_be_removed, modlib.func.curry(add_owner, self))
end

function get_dim(self)
    return vector.subtract(self.max, self.min)
end

function get_area(self)
    if mapcache then
        return self.area
    end
    read_from_map(self)
    self.area = self.voxelmanip:get_data()
    return self.area
end

function get_area_temp(self)
    if mapcache then
        return self.area
    end
    return self.voxelmanip:get_data()
end

function remove_area(self)
    if not mapcache then
        self.area = nil
    end
end

function set_area(self, min, dim)
    local new_min = min or self.min
    local new_max = self.max
    if dim then
        new_max = vector.add(new_min, dim)
    end
    local areas = area_store:get_areas_in_area(new_min, new_max, true, true)
    areas[self.id] = nil
    if modlib.table.is_empty(areas) then
        self.min = new_min
        self.max = new_max
        update(self)
        return true
    end
    return false
end

function get(pos)
    local areas = area_store:get_areas_for_pos(pos, true, true)
    local id = next(areas)
    if not id then
        return
    end
    if next(areas, id) then
        return
    end
    if arenas[id] then
        return arenas[id]
    end
    local area = areas[id]
    area.id = id
    return create_from_area(area)
end

local guaranteed_max = 128
local cutoff_min_iteration = 4
local cutoff_factor = 1.25

-- uses a monte-carlo like iterative tree level search
function create_free(meta, origin, dim)
    dim = dim or modlib.table.copy(cellestial.conf.arena_defaults.dimension)
    local visited_ids = {}
    local current_level = { origin or modlib.table.copy(cellestial.conf.arena_defaults.search_origin) }
    local iteration = 1
    local found_min
    local area_found = false
    repeat
        local new_level = {}
        local function process_level()
            for _, min in pairs(current_level) do
                local areas = area_store:get_areas_in_area(min, vector.add(min, dim), true, true, false)
                if modlib.table.is_empty(areas) then
                    found_min = min
                    area_found = true
                    return
                end
                for id, area in pairs(modlib.table.shuffle(areas)) do
                    if not visited_ids[id] then
                        visited_ids[id] = true
                    end
                    for _, coord in pairs(modlib.table.shuffle({ "x", "y", "z" })) do
                        for _, new_value in pairs(modlib.table.shuffle({ area.min[coord] - dim[coord] - 1, area.max[coord] + 1 })) do
                            local new_min = modlib.table.copy(area.min)
                            new_min[coord] = new_value
                            if iteration <= cutoff_min_iteration or math.random() < 1 / math.pow(cutoff_factor, iteration - cutoff_min_iteration) then
                                table.insert(new_level, new_min)
                                if #new_level >= guaranteed_max then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
        process_level()
        modlib.table.shuffle(new_level)
        current_level = new_level
        iteration = iteration + 1
    until area_found
    local arena = new(found_min, vector.add(found_min, dim), meta)
    return arena
end

function get_by_id(id)
    if arenas[id] then
        return arenas[id]
    end
    local area = area_store:get_area(id, true, true)
    if not area then
        return
    end
    area.id = id
    return create_from_area(area)
end

function get_by_player(player)
    return get(player:get_pos())
end

function get_by_name(name)
    local player = minetest.get_player_by_name(name)
    if not player then
        return
    end
    return get_by_player(player)
end

function list_ids_by_name(name)
    local player = minetest.get_player_by_name(name)
    if not player then
        return
    end
    local arena_ids = load_ids(player:get_meta())
    return arena_ids
end

function list_by_name(name)
    local ids = list_ids_by_name(name)
    if not ids then
        return ids
    end
    return modlib.table.map(ids, get_by_id)
end

function remove(self)
    arenas[(type(self) == "table" and self.id) or self] = nil
end

function get_cell(self, pos)
    local index = self.voxelarea:indexp(pos)
    if speedup then
        return self.cells[index] == true
    end
    if self.area then
        return self.area[index] == c_cell
    end
    return minetest.get_node(pos).name == "cellestial:cell"
end

if speedup then
    function __set_cell(self, index, cell)
        local cell_or_nil = (cell or nil)
        if self.cells[index] == cell_or_nil then
            return true
        end
        self.cells[index] = cell_or_nil
        local neighbors = self.neighbors
        if cell then
            neighbors[index] = neighbors[index] or 0
        end
        local delta = (cell and 1) or -1
        for _, offset in pairs(self.offsets) do
            local newindex = index + offset
            neighbors[newindex] = (neighbors[newindex] or 0) + delta
        end
    end
end
-- does everything except setting the node
function _set_cell(self, pos, cell)
    local index = self.voxelarea:indexp(pos)
    if speedup then
        if __set_cell(self, index, cell) then
            return
        end
    else
        if get_cell(self, pos) == (cell or false) then
            return
        end
    end
    if self.area then
        self.area[index] = (cell and c_cell) or c_air
    end
    return true
end

function set_cell(self, pos, cell)
    if _set_cell(self, pos, cell) then
        minetest.set_node(pos, { name = (cell and "cellestial:cell") or "air" })
    end
end

function calculate_neighbors(self)
    local cells = self.cells
    local offsets = self.offsets
    local neighbors = {}
    self.neighbors = neighbors
    for index, _ in pairs(cells) do
        neighbors[index] = neighbors[index] or 0
        for _, offset in pairs(offsets) do
            local new_index = index + offset
            neighbors[new_index] = (neighbors[new_index] or 0) + 1
        end
    end
end

function apply_rules(self, rules)
    local cells, area = self.cells, get_area(self)
    local birth = rules.birth
    local death = rules.death
    local delta_cells = {}
    for index, amount in pairs(self.neighbors) do
        if cells[index] then
            if death[amount] and area[index] == c_cell then
                delta_cells[index] = false
            end
        elseif birth[amount] and area[index] == c_air then
            delta_cells[index] = true
        end
    end
    if birth[0] then
        for index in iter_content(self) do
            if not cells[index] then
                delta_cells[index] = true
            end
        end
    end
    for index, cell in pairs(delta_cells) do
        __set_cell(self, index, cell)
        self.area[index] = (cell and c_cell) or c_air
    end
end

function write_to_map(self)
    local vm = self.voxelmanip
    vm:set_data(self.area)
    vm:write_to_map()
end

if speedup then
    function next_step(self, rules)
        apply_rules(self, rules)
        write_to_map(self)
        remove_area(self)
    end
else
    function next_step(self, rules)
        local offsets = self.offsets
        local birth = rules.birth
        local death = rules.death
        read_from_map(self)
        local vm = self.voxelmanip
        local data = vm:get_data()
        local new_data = {}
        for index, c_id in ipairs(data) do
            new_data[index] = c_id
        end
        self.area = new_data
        local min, max = self.min, self.max
        for index in iter_content(self) do
            local c_id = data[index]
            local amount = 0
            for _, offset in pairs(offsets) do
                if data[index + offset] == c_cell then
                    amount = amount + 1
                end
            end
            if c_id == c_cell then
                if death[amount] then
                    c_id = c_air
                end
            elseif c_id == c_air and birth[amount] then
                c_id = c_cell
            end
            new_data[index] = c_id
        end
        write_to_map(self)
    end
end

function iter_content(self)
    return self.voxelarea:iter(self.min.x + 1, self.min.y + 1, self.min.z + 1, self.max.x - 1, self.max.y - 1, self.max.z - 1)
end

function _clear(self)
    for index in iter_content(self) do
        self.area[index] = c_air
    end
    if speedup then
        self.cells = {}
        self.neighbors = {}
    end
end

function clear(self)
    get_area(self)
    _clear(self)
    write_to_map(self)
    remove_area(self)
end

function reset(self)
    local min, max = self.min, self.max
    get_area(self)
    _clear(self)
    for coord = 1, 6 do
        local coords = { min.x, min.y, min.z, max.x, max.y, max.z }
        if coord > 3 then
            coords[coord] = coords[coord - 3]
        else
            coords[coord] = coords[coord + 3]
        end
        for index in self.voxelarea:iter(unpack(coords)) do
            self.area[index] = c_border
        end
    end
    local light_data = self.voxelmanip:get_light_data()
    for index in self.voxelarea:iter(min.x, min.y, min.z, max.x, max.y, max.z) do
        light_data[index] = minetest.LIGHT_MAX
    end
    self.voxelmanip:set_light_data(light_data)
    write_to_map(self)
    remove_area(self)
end

function randomize(self, threshold)
    self.area = get_area(self)
    self.cells = {}
    for index in iter_content(self) do
        if math.random() < threshold then
            self.cells[index] = true
            self.area[index] = c_cell
        else
            self.area[index] = c_air
        end
    end
    calculate_neighbors(self)
    write_to_map(self)
    remove_area(self)
end

function next_steps(self, steps, rules)
    for _ = 1, steps do
        next_step(self, rules)
    end
end

function start(self, steps_per_second, rules)
    simulating[self.id] = { arena = self, steps_per_second = steps_per_second, outstanding_steps = 0, rules = rules }
end

function stop(self)
    simulating[self.id] = nil
end

function simulate(self, steps_per_second, rules)
    if simulating[self.id] then
        return stop(self)
    end
    return start(self, steps_per_second, rules)
end

function teleport(self, player)
    local area = get_area(self)
    for index in iter_content(self) do
        local c_id = area[index]
        if c_id == c_air then
            -- move to place with air
            player:set_pos(vector.add(self.voxelarea:position(index), 0.5))
            return true
        end
    end
    player:set_pos(vector.add(self.min, vector.divide(vector.subtract(self.max, self.min), 2))) -- move to center
    return false
end

minetest.register_globalstep(
        function(dtime)
            for _, sim in pairs(simulating) do
                local outstanding_steps = sim.outstanding_steps + dtime * sim.steps_per_second
                local steps = math.floor(outstanding_steps)
                sim.arena:next_steps(steps, sim.rules)
                sim.outstanding_steps = outstanding_steps - steps
            end
        end
)