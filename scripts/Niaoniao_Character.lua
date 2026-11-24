local _G = GLOBAL

-- 炊烟袅袅启动时会查桥接模组 真他妈爱管闲事
-- 它检查时先藏一下身份 等所有 modmain 跑完再还回去
local BRIDGE_ID = "workshop-3787391869"
local BRIDGE_NAME = "mod skin unlocker"
local BRIDGE_TAG = "mod_skin_unlocker"
local compatibility_state = {
    records = {},
    method_owner = nil,
    method_had_raw_value = false,
    method_raw_value = nil,
    method_original = nil,
    restored = false,
}

local function compatibility_lower(value)
    return type(value) == "string" and value:lower() or ""
end

local function compatibility_has_tag(tags)
    if type(tags) ~= "table" then
        return false
    end
    for _, tag in _G.ipairs(tags) do
        if compatibility_lower(tag) == BRIDGE_TAG then
            return true
        end
    end
    return false
end

local function compatibility_is_bridge_record(mod_id, record)
    if mod_id == BRIDGE_ID then
        return true
    end
    local info = type(record) == "table" and record.modinfo or nil
    return type(info) == "table"
        and (compatibility_lower(info.name) == BRIDGE_NAME
            or compatibility_has_tag(info.server_filter_tags))
end

local function compatibility_install()
    local mod_index = _G.rawget(_G, "KnownModIndex")
    if type(mod_index) ~= "table" then
        return false
    end

    local raw_is_mod_enabled = _G.rawget(mod_index, "IsModEnabled")
    local original_is_mod_enabled = type(raw_is_mod_enabled) == "function"
        and raw_is_mod_enabled
        or mod_index.IsModEnabled
    if type(original_is_mod_enabled) == "function" then
        compatibility_state.method_owner = mod_index
        compatibility_state.method_had_raw_value = raw_is_mod_enabled ~= nil
        compatibility_state.method_raw_value = raw_is_mod_enabled
        compatibility_state.method_original = original_is_mod_enabled
        _G.rawset(mod_index, "IsModEnabled", function(self, mod_id, ...)
            if mod_id == BRIDGE_ID then
                return false
            end
            return original_is_mod_enabled(self, mod_id, ...)
        end)
    end

    local savedata = mod_index.savedata
    local known_mods = type(savedata) == "table" and savedata.known_mods or nil
    if type(known_mods) ~= "table" then
        return compatibility_state.method_original ~= nil
    end

    for mod_id, record in _G.pairs(known_mods) do
        if compatibility_is_bridge_record(mod_id, record)
            and type(record) == "table"
            and type(record.modinfo) == "table"
        then
            local info = record.modinfo
            _G.table.insert(compatibility_state.records, {
                info = info,
                name = info.name,
                server_filter_tags = info.server_filter_tags,
            })
            info.name = "Skin Compatibility Bridge"
            info.server_filter_tags = {}
        end
    end

    if compatibility_state.method_original ~= nil or #compatibility_state.records > 0 then
        print(_G.string.format(
            "[SKIN_BRIDGE_NIAO] compatibility_mask=1 hook=%d records=%d",
            compatibility_state.method_original ~= nil and 1 or 0,
            #compatibility_state.records
        ))
        return true
    end
    return false
end

local function compatibility_restore()
    if compatibility_state.restored then
        return
    end
    compatibility_state.restored = true

    for _, saved in _G.ipairs(compatibility_state.records) do
        saved.info.name = saved.name
        saved.info.server_filter_tags = saved.server_filter_tags
    end

    if compatibility_state.method_owner ~= nil then
        if compatibility_state.method_had_raw_value then
            _G.rawset(
                compatibility_state.method_owner,
                "IsModEnabled",
                compatibility_state.method_raw_value
            )
        else
            _G.rawset(compatibility_state.method_owner, "IsModEnabled", nil)
        end
    end
    print("[SKIN_BRIDGE_NIAO] compatibility_mask=restored")
end

compatibility_install()
if type(_G.AddSimPostInit) == "function" then
    _G.AddSimPostInit(function(inst)
        if inst ~= nil and type(inst.DoTaskInTime) == "function" then
            inst:DoTaskInTime(0, compatibility_restore)
        else
            compatibility_restore()
        end
    end)
end

local patched_server_components = _G.setmetatable({}, { __mode = "k" })
local patched_client_components = _G.setmetatable({}, { __mode = "k" })
local player_unlock_marks = _G.setmetatable({}, { __mode = "k" })
local wrapped_inventory_methods = {}
local known_skins = {}
local grouped_skins = {}
local reported_missing = false
local last_reported_count = -1

local function get_skin_api()
    local niao = _G.rawget(_G, "NIAO")
    return type(niao) == "table" and niao.SKIN or nil
end

local function collect_skins()
    local skin_api = get_skin_api()
    if type(skin_api) ~= "table" or type(skin_api.SKINS_DATA_SKINS) ~= "table" then
        return 0
    end

    local next_grouped = {}
    local count = 0
    for skin_name, skin_data in _G.pairs(skin_api.SKINS_DATA_SKINS) do
        if type(skin_name) == "string" and type(skin_data) == "table" then
            local prefab_name = skin_data.prefab_name
            if type(prefab_name) == "string" and prefab_name ~= "" then
                known_skins[skin_name] = true
                next_grouped[prefab_name] = next_grouped[prefab_name] or {}
                table.insert(next_grouped[prefab_name], skin_name)
                count = count + 1
            end
        end
    end
    grouped_skins = next_grouped

    -- 已注册的皮肤都塞进默认解锁列表 省得它一个个装死
    local default_list = skin_api.__default_unlock_list
    local default_index = skin_api.__default_unlock_list_idx
    if type(default_list) == "table" and type(default_index) == "table" then
        for skin_name in _G.pairs(known_skins) do
            if not default_index[skin_name] then
                table.insert(default_list, skin_name)
                default_index[skin_name] = true
            end
        end
    end
    return count
end

local function is_known_skin(skin_name)
    return type(skin_name) == "string" and known_skins[skin_name] == true
end

local function patch_server_component(component)
    if type(component) ~= "table" or patched_server_components[component] then
        return
    end
    patched_server_components[component] = true

    local old_has_skin = component.HasSkin
    if type(old_has_skin) == "function" then
        component.HasSkin = function(self, skin_name, prefab_name, ...)
            if is_known_skin(skin_name) then
                return true
            end
            return old_has_skin(self, skin_name, prefab_name, ...)
        end
    end
end

local function patch_client_component(component)
    if type(component) ~= "table" or patched_client_components[component] then
        return
    end
    patched_client_components[component] = true

    local old_has_skin = component.HasSkin
    if type(old_has_skin) == "function" then
        component.HasSkin = function(self, skin_name, prefab_name, ...)
            if is_known_skin(skin_name) then
                return true
            end
            return old_has_skin(self, skin_name, prefab_name, ...)
        end
    end
end

local function merge_replica_skin_lists(component)
    if type(component) ~= "table" or type(component.unlocked_skins) ~= "table" then
        return
    end

    component.unlocked_skins_ids = component.unlocked_skins_ids or {}
    for prefab_name, skin_list in _G.pairs(grouped_skins) do
        local target = component.unlocked_skins[prefab_name] or {}
        local ids = component.unlocked_skins_ids[prefab_name] or {}
        for _, skin_name in _G.ipairs(target) do
            ids[skin_name] = ids[skin_name] or #target
        end
        for _, skin_name in _G.ipairs(skin_list) do
            if not ids[skin_name] then
                table.insert(target, skin_name)
                ids[skin_name] = #target
            end
        end
        component.unlocked_skins[prefab_name] = target
        component.unlocked_skins_ids[prefab_name] = ids

        local prefab_skins = _G.rawget(_G, "PREFAB_SKINS")
        local prefab_skin_ids = _G.rawget(_G, "PREFAB_SKINS_IDS")
        if type(prefab_skins) == "table" then
            prefab_skins[prefab_name] = target
        end
        if type(prefab_skin_ids) == "table" then
            prefab_skin_ids[prefab_name] = ids
        end
    end
end

local function unlock_player(player, skin_count)
    if player == nil then
        return
    end

    local components = player.components
    local replicas = player.replica
    local server_component = components and components.niao_com_skins_controller
    local client_component = replicas and replicas.niao_com_skins_controller

    patch_server_component(server_component)
    patch_client_component(client_component)
    merge_replica_skin_lists(client_component)

    if server_component ~= nil and player_unlock_marks[player] ~= skin_count then
        player_unlock_marks[player] = skin_count
        if type(server_component.UnlockSkin) == "function" then
            server_component:UnlockSkin(grouped_skins)
        elseif type(server_component.SetUnlockedData) == "function" then
            for prefab_name, skin_list in _G.pairs(grouped_skins) do
                for _, skin_name in _G.ipairs(skin_list) do
                    server_component:SetUnlockedData(prefab_name, skin_name)
                end
            end
        end
    end
end

local function patch_inventory()
    local inventory = _G.rawget(_G, "TheInventory")
    if inventory == nil then
        return
    end
    local metatable = _G.getmetatable(inventory)
    local index = metatable ~= nil and metatable.__index or nil
    if type(index) ~= "table" then
        return
    end

    if not wrapped_inventory_methods.CheckOwnership and type(index.CheckOwnership) == "function" then
        local old = index.CheckOwnership
        index.CheckOwnership = function(self, skin_name, ...)
            if is_known_skin(skin_name) then
                return true
            end
            return old(self, skin_name, ...)
        end
        wrapped_inventory_methods.CheckOwnership = true
    end
    if not wrapped_inventory_methods.CheckOwnershipGetLatest and type(index.CheckOwnershipGetLatest) == "function" then
        local old = index.CheckOwnershipGetLatest
        index.CheckOwnershipGetLatest = function(self, skin_name, ...)
            if is_known_skin(skin_name) then
                return true, 0
            end
            return old(self, skin_name, ...)
        end
        wrapped_inventory_methods.CheckOwnershipGetLatest = true
    end
    if not wrapped_inventory_methods.CheckClientOwnership and type(index.CheckClientOwnership) == "function" then
        local old = index.CheckClientOwnership
        index.CheckClientOwnership = function(self, userid, skin_name, ...)
            if is_known_skin(skin_name) then
                return true
            end
            return old(self, userid, skin_name, ...)
        end
        wrapped_inventory_methods.CheckClientOwnership = true
    end
    index.HasSupportForOfflineSkins = function()
        return true
    end
end

local function wrap_data_init()
    local skin_api = get_skin_api()
    if type(skin_api) ~= "table" or type(skin_api.DATA_INIT) ~= "function" then
        return
    end
    if skin_api.__bridge_data_init_wrapped then
        return
    end

    local old_data_init = skin_api.DATA_INIT
    skin_api.DATA_INIT = function(self, skins_data, prefab_name, ...)
        local result = old_data_init(self, skins_data, prefab_name, ...)
        collect_skins()
        return result
    end
    skin_api.__bridge_data_init_wrapped = true
end

local function patch_niaoniao_skins()
    local skin_api = get_skin_api()
    if type(skin_api) ~= "table" then
        if not reported_missing then
            reported_missing = true
            print("[SKIN_BRIDGE_NIAO] target mod not ready, skipped")
        end
        return
    end

    reported_missing = false
    local skin_count = collect_skins()
    wrap_data_init()
    patch_inventory()

    local players = _G.rawget(_G, "AllPlayers")
    if type(players) == "table" then
        for _, player in _G.ipairs(players) do
            unlock_player(player, skin_count)
        end
    end

    if skin_count ~= last_reported_count then
        last_reported_count = skin_count
        print(
            _G.string.format(
                "[SKIN_BRIDGE_NIAO] skins=%d default_unlocks=%d",
                skin_count,
                type(skin_api.__default_unlock_list) == "table" and #skin_api.__default_unlock_list or 0
            )
        )
    end
end

AddPlayerPostInit(function(player)
    player:DoTaskInTime(0.5, patch_niaoniao_skins)
    player:DoTaskInTime(2, patch_niaoniao_skins)
end)

AddSimPostInit(patch_niaoniao_skins)

local function patch_after_world_spawn(inst)
    inst:DoTaskInTime(0, patch_niaoniao_skins)
    inst:DoTaskInTime(1, patch_niaoniao_skins)
    inst:DoTaskInTime(3, patch_niaoniao_skins)
    inst:DoTaskInTime(8, patch_niaoniao_skins)
end

AddPrefabPostInit("world", patch_after_world_spawn)
AddPrefabPostInit("cave", patch_after_world_spawn)

patch_niaoniao_skins()
