local _G = GLOBAL
local debug_lib = _G.rawget(_G, "debug")

local registry_tables = _G.setmetatable({}, { __mode = "k" })
local seen_functions = _G.setmetatable({}, { __mode = "k" })
local known_skins = {}
local reported_missing = false
local last_reported_total = -1

local stats = {
    item_skins = 0,
    character_skins = 0,
    registries = 0,
}

local function allow_skin()
    return true
end

local function current_userid()
    local net = _G.rawget(_G, "TheNet")
    if net ~= nil and type(net.GetUserID) == "function" then
        return net:GetUserID()
    end
    return nil
end

local function remember_registry(value)
    if type(value) == "table" then
        registry_tables[value] = true
    end
end

local function inspect_function(fn, depth)
    if debug_lib == nil or type(debug_lib.getupvalue) ~= "function" then
        return
    end
    if type(fn) ~= "function" or depth > 10 or seen_functions[fn] then
        return
    end
    seen_functions[fn] = true

    for index = 1, 160 do
        local name, value = debug_lib.getupvalue(fn, index)
        if name == nil then
            break
        end
        if name == "itemskins" or name == "characterskins" then
            remember_registry(value)
            stats.registries = stats.registries + 1
        elseif type(value) == "function" then
            inspect_function(value, depth + 1)
        end
    end
end

local function patch_registry(registry)
    if type(registry) ~= "table" then
        return
    end

    for skin_name, data in _G.pairs(registry) do
        if type(skin_name) == "string" and type(data) == "table" then
            data.checkfn = allow_skin
            data.checkclientfn = allow_skin
            data.is_restricted = false
            data.unlock = true
            known_skins[skin_name] = "perm"
        end
    end
end

local function patch_inventory_registries()
    if debug_lib == nil or type(debug_lib.getupvalue) ~= "function" then
        return
    end

    local inventory = _G.rawget(_G, "TheInventory")
    if inventory == nil then
        return
    end

    local methods = {
        "CheckOwnership",
        "CheckOwnershipGetLatest",
        "CheckClientOwnership",
    }
    local metatable = _G.getmetatable(inventory)
    local index = metatable ~= nil and metatable.__index or nil
    for _, method_name in _G.ipairs(methods) do
        local method = inventory[method_name]
        if type(method) == "function" then
            inspect_function(method, 0)
        end
        if type(index) == "table" and type(index[method_name]) == "function" then
            inspect_function(index[method_name], 0)
        end
    end

    for registry in _G.pairs(registry_tables) do
        patch_registry(registry)
    end
end

local function copy_known_skins()
    local skins = {}
    for skin_name, state in _G.pairs(known_skins) do
        skins[skin_name] = state
    end
    return skins
end

local function patch_cache_upvalue(fn, cache_name)
    if debug_lib == nil or type(debug_lib.getupvalue) ~= "function" or type(fn) ~= "function" then
        return
    end

    for index = 1, 160 do
        local name, value = debug_lib.getupvalue(fn, index)
        if name == nil then
            break
        end
        if name == cache_name and type(value) == "table" then
            local userid = current_userid()
            if type(userid) == "string" and userid ~= "" then
                value[userid] = {
                    coins = 0,
                    points = 0,
                    updated_at = 0,
                    skins = copy_known_skins(),
                }
            end
            local players = _G.rawget(_G, "AllPlayers")
            if type(players) == "table" then
                for _, player in _G.ipairs(players) do
                    if player ~= nil and type(player.userid) == "string" then
                        value[player.userid] = {
                            coins = 0,
                            points = 0,
                            updated_at = 0,
                            skins = copy_known_skins(),
                        }
                    end
                end
            end
        end
    end
end

local function patch_hmr_api()
    local api = _G.rawget(_G, "HMR_SKIN_SYNC_API")
    if type(api) ~= "table" then
        return false
    end

    local client_check = _G.rawget(api, "CheckOwnership")
    local server_check = _G.rawget(api, "CheckClientOwnership")
    patch_cache_upvalue(client_check, "CLIENT_SKIN_LIST")
    patch_cache_upvalue(server_check, "SERVER_SKIN_LIST")

    _G.rawset(api, "CheckOwnership", allow_skin)
    _G.rawset(api, "CheckClientOwnership", allow_skin)
    _G.rawset(api, "HasSkin", allow_skin)
    _G.rawset(_G, "HMRIsSkinOwned", allow_skin)
    _G.rawset(_G, "HMRIsClientSkinOwned", allow_skin)
    return true
end

local function fake_network_sync(userid, callback)
    if type(callback) ~= "function" then
        return
    end

    callback(true, {
        userid = userid or current_userid(),
        coins = 0,
        points = 0,
        updated_at = 0,
        skins = copy_known_skins(),
    }, nil)
end

local function patch_network_entry()
    _G.rawset(_G, "HMRGetSkinDataFromNet", fake_network_sync)
end

local function is_hmr_mod(modname, modinfo)
    if type(modname) == "string" and modname:find("3609964985", 1, true) ~= nil then
        return true
    end

    local title = type(modinfo) == "table" and _G.tostring(modinfo.name or "") or ""
    return title:find("丰耘秘境", 1, true) ~= nil
        or title:find("Harvest Mysterious Realm", 1, true) ~= nil
end

local function target_loaded()
    local known_mod_index = _G.rawget(_G, "KnownModIndex")
    if known_mod_index == nil then
        return false
    end

    for _, modname in _G.pairs(known_mod_index:GetModsToLoad(true) or {}) do
        if is_hmr_mod(modname, known_mod_index:GetModInfo(modname)) then
            return true
        end
    end
    return false
end

local function patch_hmr_skins()
    if not target_loaded() then
        if not reported_missing then
            reported_missing = true
            print("[SKIN_BRIDGE_HMR] target mod not loaded, skipped")
        end
        return
    end

    reported_missing = false
    patch_inventory_registries()
    local api_ready = patch_hmr_api()
    patch_network_entry()

    local total = 0
    for _ in _G.pairs(known_skins) do
        total = total + 1
    end
    stats.item_skins = total

    if total ~= last_reported_total or api_ready then
        last_reported_total = total
        print(
            _G.string.format(
                "[SKIN_BRIDGE_HMR] api=%d skins=%d registries=%d",
                api_ready and 1 or 0,
                total,
                stats.registries
            )
        )
    end
end

patch_hmr_skins()
AddSimPostInit(patch_hmr_skins)

local function patch_after_world_spawn(inst)
    inst:DoTaskInTime(0, patch_hmr_skins)
    inst:DoTaskInTime(0.25, patch_hmr_skins)
    inst:DoTaskInTime(1, patch_hmr_skins)
    inst:DoTaskInTime(3, patch_hmr_skins)
    inst:DoTaskInTime(8, patch_hmr_skins)
end

AddPrefabPostInit("world", patch_after_world_spawn)
AddPrefabPostInit("cave", patch_after_world_spawn)
