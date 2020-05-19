-- TODO func = int is deprecated and only kept for compatibility
local int = function(value) if value % 1 ~= 0 then return "Integer instead of float expected" end end
local pos_int = { type = "number", range = { 1 }, int = true, func = int }
local component = { type = "number", range = { 0, 255 }, int = true, func = int }
local color = { type = "table", children = {r = component, g = component, b = component} }
local node_colors = { fill = color, edge = color }
local vector = { type = "table", children = { x = pos_int, y = pos_int, z = pos_int } }
local conf_spec = {
    type = "table",
    children = {
        colors = {
            type = "table",
            children = {
                cell = node_colors,
                border = node_colors
            }
        },
        max_steps = pos_int,
        request_duration = pos_int,
        arena_defaults = {
            name = { type = "string" },
            dimension = vector,
            search_origin = vector,
            steps = pos_int,
            threshold = { type = "number", range = {0, 1} }
        },
        creative = { type = "boolean" },
        speedup = { type = "boolean" },
        mapcache = { type = "boolean" },
        place_inside_player = { type = "boolean" }
    }
}

conf = modlib.conf.import("cellestial", conf_spec)

for _, colors in pairs(conf.colors) do
    for prop, color in pairs(colors) do
        colors[prop] = ("#%02X%02X%02X"):format(color.r, color.g, color.b)
    end
end