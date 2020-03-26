if not minetest.features.area_store_persistent_ids then
    error("Cellestial requires persistent area store IDs, upgrade to Minetest 5.1 or newer")
end
cellestial = {} -- to stop Minetest complaining about undeclared globals...
modlib.mod.extend("cellestial", "conf")
local cellestiall_init = modlib.mod.get_resource("cellestiall", "init.lua")
if cellestiall and modlib.file.exists(cellestiall_init) then
    dofile(cellestiall_init)
end
modlib.mod.extend("cellestial", "main")
cellestial.arena = modlib.mod.loadfile_exports(modlib.mod.get_resource("cellestial", "arena.lua"))
modlib.mod.extend("cellestial", "chatcommands")
cellestiall.after_cellestial_loaded()