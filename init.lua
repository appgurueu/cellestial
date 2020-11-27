local mod = modlib.mod
mod.create_namespace()
if not minetest.features.area_store_persistent_ids then
    error("Cellestial requires persistent area store IDs, upgrade to Minetest 5.1 or newer")
end
mod.extend("conf")
local cellestiall_init = minetest.get_modpath"cellestiall"
if cellestiall_init then
    cellestiall_init = cellestiall_init .. "/init.lua"
end
if cellestiall and modlib.file.exists(cellestiall_init) then
    dofile(cellestiall_init)
end
mod.extend("main")
cellestial.arena = mod.loadfile_exports(mod.get_resource("arena.lua"))
mod.extend("chatcommands")
if cellestiall then
    cellestiall.after_cellestial_loaded()
end