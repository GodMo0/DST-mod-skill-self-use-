local _G = GLOBAL
local debug_lib = _G.rawget(_G, "debug")

local TARGET_ID = "3544387985"

local known_skins = {}
local known_skin_data = {}
local known_skin_order = {}
local registry_tables = _G.setmetatable({}, { __mode = "k" })
local registration_wrappers = _G.setmetatable({}, { __mode = "k" })
local inventory_wrappers = _G.setmetatable({}, { __mode = "k" })
local validator_wrappers = _G.setmetatable({}, { __mode = "k" })
local component_wrappers = _G.setmetatable({}, { __mode = "k" })
local scheduled_scan_hosts = _G.setmetatable({}, { __mode = "k" })

local reported_missing = false
local last_reported_total = -1

local function safe_rawget(value, key)
    if type(value) ~= "table" then
        return nil
    end
    return _G.rawget(value, key)
end

local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    return _G.pcall(fn, ...)
end

local function allow_skin()
    return true
end

local function copy_known_skins()
    local result = {}
    for index, skin_name in _G.ipairs(known_skin_order) do
        result[index] = skin_name
    end
    return result
end

local function add_known_skin(name, data)
    if type(name) ~= "string" or name == "" then
        return false
    end

    if not known_skins[name] then
        known_skins[name] = true
        _G.table.insert(known_skin_order, name)
    end
    if type(data) == "table" then
        known_skin_data[name] = data
    end
    return true
end

local target_api
local target_get_skin
local target_get_skin_map

local function is_target_skin(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    if known_skins[name] then
        return true
    end

    if type(target_get_skin_map) == "function" then
        local ok, mapped = _G.pcall(target_get_skin_map, name)
        if ok and type(mapped) == "string" and known_skins[mapped] then
            known_skins[name] = true
            return true
        end
    end

    if type(target_get_skin) == "function" then
        local ok, data = _G.pcall(target_get_skin, name)
        if ok and data ~= nil then
            add_known_skin(name, data)
            return true
        end
    end

    return false
end

local function patch_skin_data(name, data, stats)
    if type(name) ~= "string" then
        return 0
    end

    add_known_skin(name, data)
    if type(data) ~= "table" then
        return 0
    end

    local changed = 0
    if data.checkfn ~= allow_skin then
        data.checkfn = allow_skin
        changed = changed + 1
    end
    if data.checkclientfn ~= allow_skin then
        data.checkclientfn = allow_skin
        changed = changed + 1
    end
    if data.is_restricted then
        data.is_restricted = false
        changed = changed + 1
    end
    if data.unlock ~= true then
        data.unlock = true
        changed = changed + 1
    end

    if stats then
        stats.data_changed = stats.data_changed + changed
    end
    return changed
end

local function patch_registry(registry, stats)
    if type(registry) ~= "table" then
        return 0
    end

    registry_tables[registry] = true
    local changed = 0
    for name, data in _G.pairs(registry) do
        if type(name) == "string" then
            changed = changed + patch_skin_data(name, data, stats)
        end
    end
    return changed
end

local function patch_registration_function(api, name, stats)
    if type(api) ~= "table" then
        return
    end

    local current = _G.rawget(api, name)
    if type(current) ~= "function" then
        return
    end

    local state = registration_wrappers[api]
    if not state then
        state = {}
        registration_wrappers[api] = state
    end
    if state[name] and state[name].wrapper == current then
        return
    end

    local old = current
    local wrapper = function(base, skin_name, data, ...)
        patch_skin_data(skin_name, data, stats)
        return old(base, skin_name, data, ...)
    end

    _G.rawset(api, name, wrapper)
    state[name] = { old = old, wrapper = wrapper }
end

local function patch_api_table(api, stats)
    if type(api) ~= "table" then
        return
    end

    local get_skin = _G.rawget(api, "GetSkin")
    if type(get_skin) == "function" then
        target_get_skin = get_skin
    end
    local get_skin_map = _G.rawget(api, "GetSkinMap")
    if type(get_skin_map) == "function" then
        target_get_skin_map = get_skin_map
    end

    patch_registration_function(api, "MakeCharacterSkin", stats)
    patch_registration_function(api, "MakeItemSkin", stats)

    patch_registry(_G.rawget(api, "characterskins"), stats)
    patch_registry(_G.rawget(api, "itemskins"), stats)
    patch_registry(_G.rawget(api, "CHARACTERSKINS"), stats)
    patch_registry(_G.rawget(api, "ITEMSKINS"), stats)

    local get_all_skin = _G.rawget(api, "GetAllSkin")
    if type(get_all_skin) == "function" then
        local ok, character_skins, item_skins = _G.pcall(get_all_skin)
        if ok then
            patch_registry(character_skins, stats)
            patch_registry(item_skins, stats)
        end
    end

    local prefab_skins = _G.rawget(_G, "PREFAB_SKINS")
    if type(prefab_skins) == "table" and type(get_skin) == "function" then
        for _, skins in _G.pairs(prefab_skins) do
            if type(skins) == "table" then
                for _, skin_name in _G.ipairs(skins) do
                    local ok, data = _G.pcall(get_skin, skin_name)
                    if ok and data ~= nil then
                        patch_skin_data(skin_name, data, stats)
                    end
                end
            end
        end
    end
end

local function add_skin_names_to_set(set, names)
    if type(set) ~= "table" then
        return
    end
    for _, skin_name in _G.ipairs(known_skin_order) do
        set[skin_name] = true
    end
    if type(names) == "table" then
        for skin_name in _G.pairs(names) do
            if type(skin_name) == "string" then
                set[skin_name] = true
            end
        end
    end
end

local function seed_auth_cache(cache)
    if type(cache) ~= "table" then
        return
    end

    local function seed_user(userid)
        if type(userid) == "string" and userid ~= "" then
            cache[userid] = copy_known_skins()
        end
    end

    local net = _G.rawget(_G, "TheNet")
    if net ~= nil and type(net.GetUserID) == "function" then
        local ok, userid = _G.pcall(net.GetUserID, net)
        if ok then
            seed_user(userid)
        end
    end

    local player = _G.rawget(_G, "ThePlayer")
    if player ~= nil then
        seed_user(player.userid)
    end

    local players = _G.rawget(_G, "AllPlayers")
    if type(players) == "table" then
        for _, item in _G.ipairs(players) do
            if item ~= nil then
                seed_user(item.userid)
            end
        end
    end
end

local function seed_world_skin_data()
    local world = _G.rawget(_G, "TheWorld")
    if world == nil then
        return
    end

    if type(world.tbat_skin_data) ~= "table" then
        world.tbat_skin_data = {}
    end

    local function seed_user(userid)
        if type(userid) == "string" and userid ~= "" then
            world.tbat_skin_data[userid] = {
                userid = userid,
                skins = copy_known_skins(),
            }
        end
    end

    local players = _G.rawget(_G, "AllPlayers")
    if type(players) == "table" then
        for _, item in _G.ipairs(players) do
            if item ~= nil then
                seed_user(item.userid)
            end
        end
    end

    local player = _G.rawget(_G, "ThePlayer")
    if player ~= nil then
        seed_user(player.userid)
    end
end

local function patch_upvalue(fn, index, replacement, stats)
    if debug_lib == nil or type(debug_lib.setupvalue) ~= "function" then
        return false
    end
    local ok, name, current = _G.pcall(debug_lib.getupvalue, fn, index)
    if not ok or name == nil or current == replacement then
        return false
    end
    local setup_ok, setup_result = _G.pcall(debug_lib.setupvalue, fn, index, replacement)
    if setup_ok and setup_result ~= nil then
        if stats then
            stats.upvalues = stats.upvalues + 1
        end
        return true
    end
    return false
end

local inspect_table

local function inspect_function(fn, depth, state, stats)
    if type(fn) ~= "function"
        or debug_lib == nil
        or type(debug_lib.getupvalue) ~= "function"
        or depth > 8
        or state.seen_functions[fn]
        or state.functions >= 1800 then
        return
    end

    state.seen_functions[fn] = true
    state.functions = state.functions + 1

    for index = 1, 180 do
        local ok, name, value = _G.pcall(debug_lib.getupvalue, fn, index)
        if not ok or name == nil then
            break
        end

        if name == "test" then
            patch_upvalue(fn, index, true, stats)
        elseif name == "auth_caches" then
            seed_auth_cache(value)
        elseif name == "PROTECTED_SKINS" then
            add_skin_names_to_set(value)
        elseif name == "need_lock_skin" then
            if type(value) == "table" then
                for _, skin_name in _G.pairs(value) do
                    if type(skin_name) == "string" then
                        add_known_skin(skin_name)
                    end
                end
            end
        elseif name == "ProtectedClientHasSkin" or name == "ProtectedServerHasSkin" then
            patch_upvalue(fn, index, allow_skin, stats)
        end

        if type(value) == "function" then
            inspect_function(value, depth + 1, state, stats)
        elseif type(value) == "table" and value ~= _G then
            inspect_table(value, depth + 1, state, stats)
        end
    end
end

inspect_table = function(value, depth, state, stats)
    if type(value) ~= "table"
        or value == _G
        or depth > 8
        or state.seen_tables[value]
        or state.tables >= 1200 then
        return
    end

    state.seen_tables[value] = true
    state.tables = state.tables + 1
    local count = 0
    for key, nested in _G.pairs(value) do
        count = count + 1
        if count > 1200 then
            break
        end

        if type(key) == "string"
            and (key == "characterskins" or key == "itemskins"
                or key == "CHARACTERSKINS" or key == "ITEMSKINS") then
            patch_registry(nested, stats)
        end

        if type(nested) == "function" then
            inspect_function(nested, depth + 1, state, stats)
        elseif type(nested) == "table"
            and nested ~= _G
            and key ~= "PREFAB_SKINS"
            and key ~= "PREFAB_SKINS_IDS" then
            inspect_table(nested, depth + 1, state, stats)
        end
    end
end

local function patch_function_graph(api, stats)
    local state = {
        seen_functions = {},
        seen_tables = {},
        functions = 0,
        tables = 0,
    }

    if type(api) == "table" then
        for _, name in _G.ipairs({
            "TbatSkinCheckFn",
            "TbatSkinCheckClientFn",
            "ValidateRecipeSkinRequest",
            "GetSkin",
            "GetAllSkin",
        }) do
            local value = _G.rawget(api, name)
            if type(value) == "function" then
                inspect_function(value, 0, state, stats)
            end
        end

        local postinitfns = _G.rawget(api, "postinitfns")
        if type(postinitfns) == "table" then
            inspect_table(postinitfns, 0, state, stats)
        end
    end

    local inventory = _G.rawget(_G, "TheInventory")
    if inventory ~= nil then
        local mt = _G.getmetatable(inventory)
        local index = type(mt) == "table" and mt.__index or nil
        if type(index) == "table" then
            for _, name in _G.ipairs({
                "CheckOwnership",
                "CheckOwnershipGetLatest",
                "CheckClientOwnership",
            }) do
                local value = _G.rawget(index, name)
                if type(value) == "function" then
                    inspect_function(value, 0, state, stats)
                end
            end
        end
    end

    local validate = _G.rawget(_G, "ValidateRecipeSkinRequest")
    if type(validate) == "function" then
        inspect_function(validate, 0, state, stats)
    end

    local sim = _G.rawget(_G, "Sim")
    if sim ~= nil then
        local ok, reskin = _G.pcall(function()
            return sim.ReskinEntity
        end)
        if ok and type(reskin) == "function" then
            inspect_function(reskin, 0, state, stats)
        end
    end

    stats.functions = state.functions
end

local function replace_check_function(holder, name)
    if type(holder) ~= "table" then
        return
    end

    local current = _G.rawget(holder, name)
    if current ~= allow_skin then
        _G.rawset(holder, name, allow_skin)
    end
end

local function patch_validator(holder, stats)
    if type(holder) ~= "table" then
        return
    end

    local current = _G.rawget(holder, "ValidateRecipeSkinRequest")
    if type(current) ~= "function" then
        return
    end

    local state = validator_wrappers[holder]
    if state and state.wrapper == current then
        return
    end

    local old = current
    local wrapper = function(user_id, prefab_name, skin, ...)
        if is_target_skin(skin) then
            return skin
        end
        return old(user_id, prefab_name, skin, ...)
    end

    _G.rawset(holder, "ValidateRecipeSkinRequest", wrapper)
    validator_wrappers[holder] = { old = old, wrapper = wrapper }
    if stats then
        stats.validators = stats.validators + 1
    end
end

local function get_method_table(object)
    if object == nil then
        return nil
    end
    local mt = _G.getmetatable(object)
    if type(mt) == "table" and type(mt.__index) == "table" then
        return mt.__index
    end
    if type(object) == "table" then
        return object
    end
    return nil
end

local function patch_inventory(stats)
    local inventory = _G.rawget(_G, "TheInventory")
    if inventory == nil then
        return
    end

    local method_table = get_method_table(inventory)
    if type(method_table) ~= "table" then
        return
    end

    local state = inventory_wrappers[method_table]
    if not state then
        state = {}
        inventory_wrappers[method_table] = state
    end

    local function wrap(method_name, kind)
        local current = _G.rawget(method_table, method_name)
        if type(current) ~= "function" then
            return
        end
        if state[method_name] and state[method_name].wrapper == current then
            return
        end

        local old = current
        local wrapper
        if kind == "latest" then
            wrapper = function(self, name, ...)
                if is_target_skin(name) then
                    return true, 0
                end
                return old(self, name, ...)
            end
        elseif kind == "client" then
            wrapper = function(self, userid, name, ...)
                if is_target_skin(name) then
                    return true
                end
                return old(self, userid, name, ...)
            end
        else
            wrapper = function(self, name, ...)
                if is_target_skin(name) then
                    return true
                end
                return old(self, name, ...)
            end
        end

        _G.rawset(method_table, method_name, wrapper)
        state[method_name] = { old = old, wrapper = wrapper }
        if stats then
            stats.inventory = stats.inventory + 1
        end
    end

    wrap("CheckOwnership", "normal")
    wrap("CheckOwnershipGetLatest", "latest")
    wrap("CheckClientOwnership", "client")
    _G.rawset(method_table, "HasSupportForOfflineSkins", function()
        return true
    end)
end

local function patch_old_skin_system(api, stats)
    local tbat = safe_rawget(api, "TBAT") or _G.rawget(_G, "TBAT")
    local skin_api = safe_rawget(tbat, "SKIN")
    if type(skin_api) ~= "table" then
        return
    end

    local all_skin_data = _G.rawget(skin_api, "SKINS_DATA_SKINS")
    if type(all_skin_data) == "table" then
        patch_registry(all_skin_data, stats)
    end

    local get_all = _G.rawget(skin_api, "GET_ALL_SKINS_DATA")
    if type(get_all) == "function" then
        local ok, skins, prefabs = _G.pcall(get_all, skin_api)
        if ok then
            patch_registry(skins, stats)
            patch_registry(prefabs, stats)
        end
    end

    for _, list_name in _G.ipairs({ "__default_unlock_list", "__vip_unlock_list" }) do
        local list = _G.rawget(skin_api, list_name)
        if type(list) == "table" then
            local index = {}
            for _, name in _G.ipairs(list) do
                index[name] = true
            end
            for _, name in _G.ipairs(known_skin_order) do
                if not index[name] then
                    _G.table.insert(list, name)
                    index[name] = true
                end
            end
        end
    end
end

local function patch_component(component, stats)
    if component == nil then
        return
    end

    local current = nil
    local ok, value = _G.pcall(function()
        return component.HasSkin
    end)
    if ok then
        current = value
    end
    if type(current) ~= "function" then
        return
    end

    local state = component_wrappers[component]
    if state and state.wrapper == current then
        return
    end

    local old = current
    local wrapper = function(self, skin_name, prefab, ...)
        if is_target_skin(skin_name) then
            return true
        end
        return old(self, skin_name, prefab, ...)
    end

    local set_ok = _G.pcall(function()
        component.HasSkin = wrapper
    end)
    if set_ok then
        component_wrappers[component] = { old = old, wrapper = wrapper }
        if stats then
            stats.components = stats.components + 1
        end
    end
end

local function patch_players(stats)
    local players = _G.rawget(_G, "AllPlayers")
    if type(players) == "table" then
        for _, player in _G.ipairs(players) do
            if player ~= nil then
                local components = player.components
                local replica = player.replica
                patch_component(components and components.tbat_com_skins_controller, stats)
                patch_component(replica and replica.tbat_com_skins_controller, stats)
                if replica and replica._ then
                    patch_component(replica._.tbat_com_skins_controller, stats)
                end
            end
        end
    end

    local player = _G.rawget(_G, "ThePlayer")
    if player ~= nil then
        local components = player.components
        local replica = player.replica
        patch_component(components and components.tbat_com_skins_controller, stats)
        patch_component(replica and replica.tbat_com_skins_controller, stats)
        if replica and replica._ then
            patch_component(replica._.tbat_com_skins_controller, stats)
        end
    end
end

local function find_target_mod()
    local known_mod_index = _G.rawget(_G, "KnownModIndex")
    local mod_manager = _G.rawget(_G, "ModManager")

    if known_mod_index ~= nil then
        local ok, modnames = _G.pcall(function()
            return known_mod_index:GetModsToLoad(true) or {}
        end)
        if ok and type(modnames) == "table" then
            for _, modname in _G.pairs(modnames) do
                local info_ok, modinfo = _G.pcall(function()
                    return known_mod_index:GetModInfo(modname)
                end)
                local title = info_ok and type(modinfo) == "table"
                    and _G.tostring(modinfo.name or "") or ""
                local name_text = type(modname) == "string"
                    and modname or _G.tostring(modname)
                if name_text:find(TARGET_ID, 1, true) ~= nil
                    or title:find("万物书", 1, true) ~= nil
                    or title:find("The Book of All Things", 1, true) ~= nil
                    or title:find("沉迷幻境", 1, true) ~= nil then
                    if mod_manager ~= nil then
                        local env_ok, modenv = _G.pcall(function()
                            return mod_manager:GetMod(modname)
                        end)
                        if env_ok and type(modenv) == "table" then
                            return modenv, name_text
                        end
                    end
                    return nil, name_text
                end
            end
        end
    end

    local global_api = _G.rawget(_G, "BOOKOFALLTHINGS")
    if type(global_api) == "table" then
        return global_api, TARGET_ID
    end

    return nil, nil
end

local function patch_book_skins()
    local root_api, modname = find_target_mod()
    if root_api == nil then
        if not reported_missing then
            reported_missing = true
            print("[SKIN_BRIDGE_BOOK] target mod not loaded, skipped")
        end
        return
    end

    reported_missing = false
    local apis = {}
    local book_api = _G.rawget(_G, "BOOKOFALLTHINGS")
    if type(book_api) == "table" then
        _G.table.insert(apis, book_api)
    end
    if type(root_api) == "table" and root_api ~= book_api then
        _G.table.insert(apis, root_api)
    end

    target_api = book_api or root_api
    for _, api in _G.ipairs(apis) do
        target_get_skin = _G.rawget(api, "GetSkin") or target_get_skin
        target_get_skin_map = _G.rawget(api, "GetSkinMap") or target_get_skin_map
    end

    local stats = {
        data_changed = 0,
        upvalues = 0,
        inventory = 0,
        validators = 0,
        components = 0,
        functions = 0,
    }

    for _, api in _G.ipairs(apis) do
        patch_api_table(api, stats)
        patch_old_skin_system(api, stats)
        patch_function_graph(api, stats)
        replace_check_function(api, "TbatSkinCheckFn")
        replace_check_function(api, "TbatSkinCheckClientFn")
        patch_validator(api, stats)
    end

    replace_check_function(_G, "TbatSkinCheckFn")
    replace_check_function(_G, "TbatSkinCheckClientFn")

    patch_validator(_G, stats)
    patch_inventory(stats)
    patch_players(stats)
    seed_world_skin_data()

    local total = #known_skin_order
    if total ~= last_reported_total
        or stats.data_changed > 0
        or stats.upvalues > 0
        or stats.inventory > 0
        or stats.validators > 0
        or stats.components > 0 then
        last_reported_total = total
        print(_G.string.format(
            "[SKIN_BRIDGE_BOOK] mod=%s skins=%d data=%d upvalues=%d inventory=%d validators=%d components=%d functions=%d",
            modname,
            total,
            stats.data_changed,
            stats.upvalues,
            stats.inventory,
            stats.validators,
            stats.components,
            stats.functions
        ))
    end

    _G.rawset(_G, "PRISM_TERRA_BRIDGE_BOOK_ENABLED", true)
end

patch_book_skins()

local function schedule_host_scans(inst)
    if inst == nil or type(inst.DoTaskInTime) ~= "function" then
        return
    end
    if scheduled_scan_hosts[inst] then
        return
    end

    scheduled_scan_hosts[inst] = true
    for _, delay in _G.ipairs({ 0, 0.25, 1, 3, 8, 15, 30, 120 }) do
        inst:DoTaskInTime(delay, patch_book_skins)
    end
    if type(inst.DoPeriodicTask) == "function" then
        inst:DoPeriodicTask(60, patch_book_skins)
    end
end

AddSimPostInit(function(inst)
    patch_book_skins()
    schedule_host_scans(_G.rawget(_G, "TheWorld") or inst)
end)

local function patch_after_world_spawn(inst)
    schedule_host_scans(inst)
end

AddPrefabPostInit("world", patch_after_world_spawn)
AddPrefabPostInit("cave", patch_after_world_spawn)

AddPlayerPostInit(function(inst)
    patch_book_skins()
    patch_component(inst.components and inst.components.tbat_com_skins_controller)
    if inst.replica then
        patch_component(inst.replica.tbat_com_skins_controller)
        if inst.replica._ then
            patch_component(inst.replica._.tbat_com_skins_controller)
        end
    end
    inst:DoTaskInTime(0.5, patch_book_skins)
    inst:DoTaskInTime(2, patch_book_skins)
    inst:DoTaskInTime(5, patch_book_skins)
end)
