local _G = GLOBAL
local debug_lib = _G.rawget(_G, "debug")

local TARGET_MOD_ID = "workshop-3235319974"
local TARGET_MOD_VERSION = "20.3"
local encrypted_prefab_loader_installed = false
local encrypted_prefab_loader_reported = false

local missing_skin_clear_fn = function() end
local skin_clear_fn_fallback_count = 0
local skin_clear_fn_names = {
    "xd_backpack1_clear_fn",
    "xd_backpack2_clear_fn",
    "xd_backpack3_clear_fn",
    "xd_chenpingan_bd_clear_fn",
    "xd_chenpingan_cjq_clear_fn",
    "xd_chenpingan_kcd_clear_fn",
    "xd_chenpingan_ljt_builder_clear_fn",
    "xd_chenpingan_qp_clear_fn",
    "xd_chenpingan_ygl_clear_fn",
    "xd_chenpingan_ygp_clear_fn",
    "xd_chenpingan_yjh_clear_fn",
    "xd_chenpingan_zlt_clear_fn",
    "xd_cl_clear_fn",
    "xd_crc_clear_fn",
    "xd_dbg_clear_fn",
    "xd_dc_clear_fn",
    "xd_flower_bh_clear_fn",
    "xd_flower_bmg_clear_fn",
    "xd_flower_md_clear_fn",
    "xd_flower_sfr_clear_fn",
    "xd_ftys_clear_fn",
    "xd_gj_clear_fn",
    "xd_gjx_clear_fn",
    "xd_hhlmz_clear_fn",
    "xd_hjjm_clear_fn",
    "xd_hmsw_clear_fn",
    "xd_htz_ztp_clear_fn",
    "xd_jwtcd_clear_fn",
    "xd_lbjlt_clear_fn",
    "xd_lgzbh_clear_fn",
    "xd_liandanlu_clear_fn",
    "xd_lyd_clear_fn",
    "xd_mg_clear_fn",
    "xd_mglz_clear_fn",
    "xd_mo_builder_clear_fn",
    "xd_pflnw_clear_fn",
    "xd_qljq_clear_fn",
    "xd_qwsk_clear_fn",
    "xd_sgc_clear_fn",
    "xd_shatangshu_clear_fn",
    "xd_sj_by_builder_clear_fn",
    "xd_sj_by_clear_fn",
    "xd_sj_cy_builder_clear_fn",
    "xd_sj_cy_clear_fn",
    "xd_soul_wolf_clear_fn",
    "xd_sudaji_redlantern_clear_fn",
    "xd_sudaji_sjpn_clear_fn",
    "xd_sudaji_tsmd_clear_fn",
    "xd_sudaji_yhly_clear_fn",
    "xd_sudaji_ywfh_clear_fn",
    "xd_tianjiwu_clear_fn",
    "xd_tree_df_clear_fn",
    "xd_tree_xhs_clear_fn",
    "xd_tree_yhs_clear_fn",
    "xd_tree_yls_clear_fn",
    "xd_tree_yxs_clear_fn",
    "xd_wsjx_clear_fn",
    "xd_xcdf_clear_fn",
    "xd_xianjian_builder_clear_fn",
    "xd_xshj_clear_fn",
    "xd_xtbh_clear_fn",
    "xd_yhbs_clear_fn",
    "xd_yhsyz_clear_fn",
    "xd_ylxc_clear_fn",
    "xd_ylxq_clear_fn",
    "xd_zcmj_clear_fn",
    "xd_ztp_clear_fn",
    "xd_hyc_clear_fn",
    "xd_flower_pgy_clear_fn",
    "xd_tree_ls_clear_fn",
    "xd_zzxhcx_clear_fn",
}

local function install_skin_clear_fn_fallbacks()
    for _, name in _G.ipairs(skin_clear_fn_names) do
        if _G.rawget(_G, name) == nil then
            _G.rawset(_G, name, missing_skin_clear_fn)
            skin_clear_fn_fallback_count = skin_clear_fn_fallback_count + 1
        end
    end
end

install_skin_clear_fn_fallbacks()
print(
    _G.string.format(
        "[SKIN_BRIDGE_DENGXIAN] clear_fn_fallbacks=%d (仅补齐缺失回调)",
        skin_clear_fn_fallback_count
    )
)

local DAXSG_MAP_PACKED = "---048193037155---105211248239122---128209218090183117210035009080178232097138095077131---149065"
    .. "185124047058199071081------073116229046186121181110212200160036079100132158060---101085108---252"
    .. "119115083042120206230174033180052136196089208053184094118---------188140092207242142129---075---"
    .. "152064204098167214---170164---------198063106134254---038197034013088068---126076091093225187---"
    .. "156182159010---145191146056039---111123---195112224143163223099061227086------050057253150---246"
    .. "032---045041250055---------177179151172114051059---169240---135175168171---173---109040044---249"
    .. "------107137141054113049072139066---237---233082125043201078190166067103228130153215---202161070"
    .. "104069147154---189226062084144074243176148102157247231216194238133192203165096213------162087205"

local DAXSG_MAP = {}
for index = 0, 255 do
    local token = _G.string.sub(DAXSG_MAP_PACKED, index * 3 + 1, index * 3 + 3)
    if token ~= "---" then
        DAXSG_MAP[index] = _G.tonumber(token)
    end
end

local function is_target_encrypted_prefab(filename, search_root)
    if type(filename) ~= "string" or type(search_root) ~= "string" then
        return false
    end
    local normalized = filename:gsub("\\", "/"):gsub("^/+", "")
    local root = search_root:gsub("\\", "/")
    local is_target_root = root:find(TARGET_MOD_ID, 1, true) ~= nil or root:find("3235319974", 1, true) ~= nil
    return is_target_root and normalized:match("^prefabs/xd_[%w_%-]+%.lua$") ~= nil
        or is_target_root and normalized:match("^prefabs/xd_[%w_%-]+$") ~= nil
end

local function read_target_prefab_bytes(filename, search_root)
    if
        not is_target_encrypted_prefab(filename, search_root)
        or _G.io == nil
        or type(_G.io.open) ~= "function"
    then
        return nil, nil
    end
    local normalized = filename:gsub("\\", "/"):gsub("^/+", "")
    if not normalized:match("%.lua$") then
        normalized = normalized .. ".lua"
    end
    local root = search_root:gsub("[\\/]+$", "")
    local candidates = {
        root .. "/scripts/" .. normalized,
        root .. "/" .. normalized,
    }
    for _, path in _G.ipairs(candidates) do
        local ok, file = _G.pcall(_G.io.open, path, "rb")
        if ok and file ~= nil then
            local read_ok, content = _G.pcall(file.read, file, "*a")
            _G.pcall(file.close, file)
            if read_ok and type(content) == "string" and content ~= "" then
                return content, path
            end
        end
    end
    return nil, nil
end

local function decode_target_prefab(content)
    local output = {}
    for index = #content, 1, -1 do
        local value = DAXSG_MAP[_G.string.byte(content, index)]
        if value == nil then
            return nil
        end
        output[#output + 1] = _G.string.char(value)
    end
    return _G.table.concat(output)
end

local function load_target_prefab_chunk(filename, search_root)
    local content, path = read_target_prefab_bytes(filename, search_root)
    if content == nil then
        return nil, nil
    end
    local compiler = _G.rawget(_G, "loadstring") or _G.rawget(_G, "load")
    if type(compiler) ~= "function" then
        return nil, path
    end
    local source = content
    local ok, chunk = _G.pcall(compiler, source, "@" .. path)
    if not ok or type(chunk) ~= "function" then
        source = decode_target_prefab(content)
        if type(source) ~= "string" then
            return nil, path
        end
        ok, chunk = _G.pcall(compiler, source, "@" .. path)
    end
    if not ok or type(chunk) ~= "function" then
        return nil, path
    end
    local manager = _G.rawget(_G, "ModManager")
    local target_env
    if manager ~= nil and type(manager.GetMod) == "function" then
        local env_ok, value = _G.pcall(manager.GetMod, manager, TARGET_MOD_ID)
        if env_ok and type(value) == "table" then
            target_env = value
        end
    end
    local setfenv_fn = _G.rawget(_G, "setfenv")
    if target_env ~= nil and type(setfenv_fn) == "function" then
        _G.pcall(setfenv_fn, chunk, target_env)
    end
    return chunk, path
end

local function install_encrypted_prefab_loader()
    if encrypted_prefab_loader_installed then
        return
    end
    local original = _G.rawget(_G, "LoadPrefabFile")
    if type(original) ~= "function" then
        return
    end
    local unpack_fn = _G.rawget(_G, "unpack") or (_G.table and _G.table.unpack)
    if type(unpack_fn) ~= "function" then
        return
    end
    _G.rawset(_G, "LoadPrefabFile", function(filename, async_batch_validation, search_root, ...)
        local chunk = load_target_prefab_chunk(filename, search_root)
        if chunk == nil then
            return original(filename, async_batch_validation, search_root, ...)
        end

        local old_loadfile = _G.rawget(_G, "loadfile")
        if type(old_loadfile) ~= "function" then
            return original(filename, async_batch_validation, search_root, ...)
        end
        _G.rawset(_G, "loadfile", function(requested, ...)
            local normalized = type(requested) == "string" and requested:gsub("\\", "/") or ""
            if
                normalized == filename
                or normalized == filename .. ".lua"
                or normalized:match("/workshop%-3235319974/scripts/prefabs/xd_[%w_%-]+%.lua$") ~= nil
            then
                return chunk
            end
            return old_loadfile(requested, ...)
        end)
        local result = { _G.pcall(original, filename, async_batch_validation, search_root, ...) }
        _G.rawset(_G, "loadfile", old_loadfile)
        if not result[1] then
            _G.error(result[2], 0)
        end
        _G.table.remove(result, 1)
        if not encrypted_prefab_loader_reported then
            encrypted_prefab_loader_reported = true
            print(
                "[SKIN_BRIDGE_DENGXIAN] encrypted_prefab_loader=1 登仙加密 prefab 运行时解码已接管"
            )
        end
        return unpack_fn(result)
    end)
    encrypted_prefab_loader_installed = true
end

install_encrypted_prefab_loader()

local patched_apis = _G.setmetatable({}, { __mode = "k" })
local patched_ui_entries = _G.setmetatable({}, { __mode = "k" })
local patched_character_tasks = _G.setmetatable({}, { __mode = "k" })
local item_callback_wrappers = _G.setmetatable({}, { __mode = "k" })
local patched_player_events = _G.setmetatable({}, { __mode = "k" })
local patched_reskin_rechecks = _G.setmetatable({}, { __mode = "k" })
local patched_restart_tables = _G.setmetatable({}, { __mode = "k" })
local registered_inventory_atlases = {}
local registered_names = {}
local last_reported_total = -1
local inventory_atlas_files = 0
local inventory_atlas_entries = 0
local inventory_atlas_reported = false
local stats = { item_skins = 0, character_skins = 0, ui_skins = 0, character_tasks = 0, item_callbacks = 0 }

local function allow_local_skin()
    return true, 0
end

local function allow_client_skin()
    return true
end

local function get_skin(api, skin_name)
    local getter = _G.rawget(api, "GetSkin")
    if type(getter) ~= "function" or type(skin_name) ~= "string" then
        return nil
    end
    local ok, data = _G.pcall(getter, skin_name)
    return ok and type(data) == "table" and data or nil
end

local function patch_skin_data(data)
    if type(data) ~= "table" then
        return 0
    end
    local changed = data.checkfn ~= allow_local_skin
        or data.checkclientfn ~= allow_client_skin
        or data.is_restricted ~= false
        or data.unlock ~= true
    data.checkfn = allow_local_skin
    data.checkclientfn = allow_client_skin
    data.is_restricted = false
    data.unlock = true
    return changed and 1 or 0
end

local function patch_registered_skin(api, skin_name)
    local data = get_skin(api, skin_name)
    if data == nil then
        return 0
    end
    local characters = _G.rawget(api, "XD_CHARACTERSKINS")
    local is_character = data.ischaracterskins
        or (type(characters) == "table" and characters[skin_name] == data)
    local patched = patch_skin_data(data)

    for _, owner in _G.ipairs({ api, _G }) do
        local registry = _G.rawget(owner, "XD_ITEMSKINS")
        local copy = type(registry) == "table" and registry[skin_name] or nil
        if copy ~= data then
            patched = patched + patch_skin_data(copy)
        end
    end
    if not registered_names[skin_name] then
        registered_names[skin_name] = true
        local key = is_character and "character_skins" or "item_skins"
        stats[key] = stats[key] + 1
    end
    return patched
end

local function patch_registries(api)
    local patched, seen = 0, {}
    for _, owner in _G.ipairs({ api, _G }) do
        for _, name in _G.ipairs({ "XD_ITEMSKINS", "XD_CHARACTERSKINS" }) do
            local registry = _G.rawget(owner, name)
            if type(registry) == "table" then
                for skin_name in _G.pairs(registry) do
                    if not seen[skin_name] then
                        seen[skin_name] = true
                        patched = patched + patch_registered_skin(api, skin_name)
                    end
                end
            end
        end
    end
    return patched
end

local function patch_api(api)
    if type(api) ~= "table" then
        return 0
    end
    patched_apis[api] = true
    return patch_registries(api)
end

local function normalize_inventory_atlas_file(file)
    if type(file) ~= "string" then
        return nil
    end
    local normalized = file:gsub("\\", "/")
    normalized = normalized:gsub("^%.%./mods/[^/]+/", "")
    normalized = normalized:gsub("^/+$", "")
    if normalized:match("^images/inventoryimages/[^/]+%.xml$") == nil then
        return nil
    end
    return normalized
end

local function register_inventory_atlas_file(mod, file)
    local atlas = normalize_inventory_atlas_file(file)
    local register = _G.rawget(_G, "RegisterInventoryItemAtlas")
    if
        atlas == nil
        or type(register) ~= "function"
        or registered_inventory_atlases[atlas]
        or _G.io == nil
        or type(_G.io.open) ~= "function"
    then
        return
    end
    local root = _G.rawget(mod, "MODROOT")
    if type(root) ~= "string" then
        root = "../mods/" .. TARGET_MOD_ID .. "/"
    end
    root = root:gsub("[\\/]+$", "")
    local ok, handle = _G.pcall(_G.io.open, root .. "/" .. atlas, "r")
    if not ok or handle == nil then
        return
    end
    local read_ok, data = _G.pcall(handle.read, handle, "*all")
    _G.pcall(handle.close, handle)
    if not read_ok or type(data) ~= "string" then
        return
    end
    local entries = 0
    for image in _G.string.gmatch(data, 'filename="([^"]+%.tex)"') do
        _G.pcall(register, atlas, image)
        entries = entries + 1
    end
    registered_inventory_atlases[atlas] = true
    if entries > 0 then
        inventory_atlas_files = inventory_atlas_files + 1
        inventory_atlas_entries = inventory_atlas_entries + entries
    end
end

local function register_inventory_atlases(mod)
    if type(mod) ~= "table" then
        return
    end
    local function scan_assets(assets)
        if type(assets) ~= "table" then
            return
        end
        for _, asset in _G.ipairs(assets) do
            if type(asset) == "table" and _G.rawget(asset, "type") == "ATLAS" then
                register_inventory_atlas_file(mod, _G.rawget(asset, "file"))
            end
        end
    end
    scan_assets(_G.rawget(mod, "Assets"))
    local prefabs = _G.rawget(mod, "Prefabs")
    if type(prefabs) == "table" then
        for _, prefab in _G.pairs(prefabs) do
            if type(prefab) == "table" then
                scan_assets(_G.rawget(prefab, "assets"))
            end
        end
    end
    if inventory_atlas_entries > 0 and not inventory_atlas_reported then
        inventory_atlas_reported = true
        print(
            _G.string.format(
                "[SKIN_BRIDGE_DENGXIAN] inventory_atlas=1 files=%d entries=%d 登仙库存图集已补注册",
                inventory_atlas_files,
                inventory_atlas_entries
            )
        )
    end
end

local function is_registered_skin(skin_name)
    for api in _G.pairs(patched_apis) do
        if get_skin(api, skin_name) ~= nil then
            return true
        end
    end
    return false
end

local function is_registered_character(skin_name)
    for api in _G.pairs(patched_apis) do
        local data = get_skin(api, skin_name)
        local characters = _G.rawget(api, "XD_CHARACTERSKINS")
        if
            data ~= nil
            and (data.ischaracterskins or (type(characters) == "table" and characters[skin_name] == data))
        then
            return true
        end
    end
    return false
end

local function is_registered_item_for_entity(inst, skin_name)
    if
        type(inst) ~= "table"
        or type(inst.prefab) ~= "string"
        or inst.skinname ~= skin_name
        or skin_name == inst.prefab
        or is_registered_character(skin_name)
    then
        return false
    end
    for api in _G.pairs(patched_apis) do
        local data = get_skin(api, skin_name)
        if data ~= nil and not data.ischaracterskins then
            if data.base_prefab == inst.prefab then
                return true
            end
            local lists = _G.rawget(_G, "PREFAB_SKINS")
            local names = type(lists) == "table" and lists[inst.prefab] or nil
            for _, name in _G.ipairs(type(names) == "table" and names or {}) do
                if name == skin_name then
                    return true
                end
            end
        end
    end
    return false
end

local function is_xd_pi_function(fn)
    local ok, info = _G.pcall(debug_lib.getinfo, fn, "S")
    return ok
        and type(info) == "table"
        and type(info.source) == "string"
        and info.source:gsub("\\", "/"):match("scripts/main/xd_pi%.lua$") ~= nil
end

local function patch_reskin_recheck()
    if
        _G.next(patched_apis) == nil
        or debug_lib == nil
        or type(debug_lib.getinfo) ~= "function"
        or type(debug_lib.getupvalue) ~= "function"
        or type(debug_lib.setupvalue) ~= "function"
    then
        return 0
    end
    local sim = _G.rawget(_G, "Sim") or _G.rawget(_G, "TheSim")
    local fn = sim and sim.ReskinEntity
    if type(fn) ~= "function" or not is_xd_pi_function(fn) then
        return 0
    end
    for index = 1, 60 do
        local name, original = debug_lib.getupvalue(fn, index)
        if name == nil then
            break
        end
        if name == "recheck" and type(original) == "function" then
            if patched_reskin_rechecks[fn] == original then
                return 0
            end
            if not is_xd_pi_function(original) then
                return 0
            end
            local wrapper = function(inst, data, ...)
                if type(data) == "table" and data.id and is_registered_item_for_entity(inst, data.skin) then
                    return
                end
                return original(inst, data, ...)
            end
            local ok, changed = _G.pcall(debug_lib.setupvalue, fn, index, wrapper)
            if ok and changed == "recheck" then
                patched_reskin_rechecks[fn] = wrapper
                stats.reskin_checks = (stats.reskin_checks or 0) + 1
                return 1
            end
            return 0
        end
    end
    return 0
end

local VM_CALLBACK_ENTRIES = {
    character = 12557313,
    item = 14169089,
}

local function is_vm_callback(fn, entry)
    if
        type(fn) ~= "function"
        or debug_lib == nil
        or type(debug_lib.getinfo) ~= "function"
        or type(debug_lib.getupvalue) ~= "function"
    then
        return false
    end
    local info = debug_lib.getinfo(fn, "S")
    if
        info == nil
        or type(info.source) ~= "string"
        or not info.source:gsub("\\", "/"):match("scripts/main/xd_new%.lua$")
    then
        return false
    end

    for index = 1, 20 do
        local name, value = debug_lib.getupvalue(fn, index)
        if name == nil then
            break
        end
        if name == "X" and value == entry then
            return true
        end
    end
    return false
end

local VM_CHECK_ENTRIES = {
    _SkinCheckFn = 8940545,
    _SkinCheckClientFn = 11890689,
}

local VM_REQUIRED_ENTRIES = { 2624513, 3556865, 12557313, 14169089 }
local VM_RESTART_ENTRIES = { 16476673, 8911873 }
local VM_RETURN_SLOT = "5TkTyolwIlOE"

local function safe_upvalue(fn, wanted)
    for index = 1, 60 do
        local ok, name, value = _G.pcall(debug_lib.getupvalue, fn, index)
        if not ok or name == nil then
            return nil
        end
        if name == wanted then
            return value
        end
    end
end

local function xd_new_function_source(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, info = _G.pcall(debug_lib.getinfo, fn, "S")
    if ok and type(info) == "table" and type(info.source) == "string" then
        local source = info.source:gsub("\\", "/")
        if source:match("scripts/main/xd_new%.lua$") then
            return source
        end
    end
end

local function find_vm_handlers(api)
    if
        type(api) ~= "table"
        or debug_lib == nil
        or type(debug_lib.getinfo) ~= "function"
        or type(debug_lib.getupvalue) ~= "function"
    then
        return nil
    end
    for name, entry in _G.pairs(VM_CHECK_ENTRIES) do
        local fn = _G.rawget(api, name) or _G.rawget(_G, name)
        local source = xd_new_function_source(fn)
        if source ~= nil and safe_upvalue(fn, "X") == entry then
            local dispatcher = safe_upvalue(fn, "q")
            if xd_new_function_source(dispatcher) == source then
                local handlers = safe_upvalue(dispatcher, "P")
                if
                    type(handlers) == "table"
                    and _G.rawget(handlers, "QyoVhL0vn") == true
                    and _G.rawget(handlers, 173564416) == 25768
                then
                    local valid = true
                    for _, key in _G.ipairs(VM_REQUIRED_ENTRIES) do
                        valid = valid and xd_new_function_source(_G.rawget(handlers, key)) == source
                    end
                    if valid then
                        return handlers, source
                    end
                end
            end
        end
    end
end

local function patch_private_restart_chain(api)
    if
        type(api) ~= "table"
        or debug_lib == nil
        or type(debug_lib.getinfo) ~= "function"
        or type(debug_lib.getupvalue) ~= "function"
    then
        return 0
    end
    local handlers, source = find_vm_handlers(api)
    if handlers == nil then
        return 0
    end
    local saved = patched_restart_tables[handlers]

    for _, entry in _G.ipairs(VM_RESTART_ENTRIES) do
        local original = _G.rawget(handlers, entry)
        local prior = saved and saved[entry]
        if not (prior and original == prior.wrapper) and xd_new_function_source(original) ~= source then
            return 0
        end
    end
    if saved == nil then
        saved = {}
        patched_restart_tables[handlers] = saved
    end
    local count = 0
    for _, entry in _G.ipairs(VM_RESTART_ENTRIES) do
        local original = _G.rawget(handlers, entry)
        if saved[entry] == nil or original ~= saved[entry].wrapper then
            local reported = false
            local wrapper = function(registers, ...)
                if type(registers) ~= "table" then
                    return original(registers, ...)
                end

                registers[VM_RETURN_SLOT] = { n = 0 }
                if not reported then
                    reported = true
                    print("[SKIN_BRIDGE_DENGXIAN] blocked_mod_restart entry=" .. entry)
                end
                return nil
            end
            saved[entry] = { original = original, wrapper = wrapper }
            _G.rawset(handlers, entry, wrapper)
            count = count + 1
        end
    end
    if count > 0 then
        stats.restart_guards = (stats.restart_guards or 0) + count
        print("[SKIN_BRIDGE_DENGXIAN] restart_guard=1 version=" .. TARGET_MOD_VERSION .. " entries=" .. count)
    end
    return count
end

local function patch_character_tasks(inst)
    if _G.next(patched_apis) == nil or inst == nil or type(inst.pendingtasks) ~= "table" then
        return 0
    end
    local patched = 0
    for task in _G.pairs(inst.pendingtasks) do
        if
            type(task) == "table"
            and task.fn ~= patched_character_tasks[task]
            and task.period == 15
            and is_vm_callback(task.fn, VM_CALLBACK_ENTRIES.character)
        then
            local original = task.fn
            local wrapper = function(player, ...)
                local skinner = player and player.components and player.components.skinner
                if skinner ~= nil and is_registered_character(skinner.skin_name) then
                    return
                end
                return original(player, ...)
            end
            task.fn = wrapper
            patched_character_tasks[task] = wrapper
            stats.character_tasks = stats.character_tasks + 1
            patched = patched + 1
        end
    end
    return patched
end

local function is_item_event(event)
    return event == "builditem" or event == "buildstructure"
end

local function item_callback(event, fn)
    if not is_item_event(event) or not is_vm_callback(fn, VM_CALLBACK_ENTRIES.item) then
        return fn
    end
    local wrapper = item_callback_wrappers[fn]
    if wrapper == nil then
        wrapper = function(player, data, ...)
            local item = type(data) == "table" and data.item or nil
            if
                type(item) == "table"
                and type(item.IsValid) == "function"
                and item:IsValid()
                and item.skinname ~= item.prefab
                and is_registered_skin(item.skinname)
                and not is_registered_character(item.skinname)
            then
                return
            end
            return fn(player, data, ...)
        end
        item_callback_wrappers[fn] = wrapper
        stats.item_callbacks = stats.item_callbacks + 1
    end
    return wrapper
end

local function patch_item_events(inst)
    if
        _G.next(patched_apis) == nil
        or inst == nil
        or debug_lib == nil
        or type(debug_lib.getinfo) ~= "function"
        or type(debug_lib.getupvalue) ~= "function"
    then
        return 0
    end
    if
        not patched_player_events[inst]
        and type(inst.ListenForEvent) == "function"
        and type(inst.RemoveEventCallback) == "function"
    then
        local listen, remove = inst.ListenForEvent, inst.RemoveEventCallback
        inst.ListenForEvent = function(self, event, fn, source, ...)
            return listen(self, event, item_callback(event, fn), source, ...)
        end
        inst.RemoveEventCallback = function(self, event, fn, source, ...)
            local mapped = is_item_event(event) and item_callback_wrappers[fn] or nil
            if mapped ~= nil then
                local sources = self.event_listening and self.event_listening[event]
                local callbacks = sources and sources[source or self]
                local has_original, has_wrapper = false, false
                for _, callback in _G.ipairs(callbacks or {}) do
                    has_original = has_original or callback == fn
                    has_wrapper = has_wrapper or callback == mapped
                end
                if has_original then
                    if not has_wrapper then
                        return remove(self, event, fn, source, ...)
                    end
                    remove(self, event, fn, source, ...)
                end
            end
            return remove(self, event, mapped or fn, source, ...)
        end
        patched_player_events[inst] = true
    end
    local patched = 0
    for _, event in _G.ipairs({ "builditem", "buildstructure" }) do
        local sources = inst.event_listening and inst.event_listening[event]
        if type(sources) == "table" then
            for source, callbacks in _G.pairs(sources) do
                if type(callbacks) == "table" then
                    for index, fn in _G.ipairs(callbacks) do
                        local wrapper = item_callback(event, fn)
                        if wrapper ~= fn then
                            callbacks[index] = wrapper

                            local listeners = source.event_listeners and source.event_listeners[event]
                            local reverse = listeners and listeners[inst]
                            if type(reverse) == "table" then
                                for other_index, other_fn in _G.ipairs(reverse) do
                                    if other_fn == fn then
                                        reverse[other_index] = wrapper
                                    end
                                end
                            end
                            patched = patched + 1
                        end
                    end
                end
            end
        end
    end
    return patched
end

local function patch_player_rechecks(inst)
    for api in _G.pairs(patched_apis) do
        patch_registries(api)
    end
    return patch_character_tasks(inst) + patch_item_events(inst)
end

local function patch_skin_ui()
    local net = _G.rawget(_G, "TheNet")
    if (net ~= nil and net:IsDedicated()) or debug_lib == nil or type(debug_lib.getupvalue) ~= "function" then
        return 0
    end
    local ok, skin_ui = _G.pcall(_G.require, "widgets/xd_skinui")
    if not ok or type(skin_ui) ~= "table" or type(skin_ui.XuanZe) ~= "function" then
        return 0
    end

    local patched = 0
    for index = 1, 60 do
        local name, entries = debug_lib.getupvalue(skin_ui.XuanZe, index)
        if name == nil then
            break
        end
        if name == "skins" and type(entries) == "table" then
            for _, row in _G.pairs(entries) do
                if type(row) == "table" and is_registered_skin(row.name) then
                    if row.unlock ~= true then
                        row.unlock = true
                        patched = patched + 1
                    end
                    if not patched_ui_entries[row] then
                        patched_ui_entries[row] = true
                        stats.ui_skins = stats.ui_skins + 1
                    end
                end
            end
        end
    end
    return patched
end

local function is_dengxian_mod(modname, modinfo)
    if type(modinfo) ~= "table" or _G.tostring(modinfo.version) ~= TARGET_MOD_VERSION then
        return false
    end
    if type(modname) == "string" and modname:find("3235319974", 1, true) ~= nil then
        return true
    end
    local title = type(modinfo) == "table" and _G.tostring(modinfo.name or "") or ""
    return title:find("登仙", 1, true) ~= nil or title:find("Deng Xian", 1, true) ~= nil
end

local function patch_dengxian_skins()
    local known_mod_index = _G.rawget(_G, "KnownModIndex")
    local mod_manager = _G.rawget(_G, "ModManager")
    if known_mod_index == nil or mod_manager == nil then
        return
    end
    local current_modname = _G.rawget(env, "modname")
    local matched, patched_now = 0, 0
    for _, modname in _G.pairs(known_mod_index:GetModsToLoad(true) or {}) do
        if modname ~= current_modname and is_dengxian_mod(modname, known_mod_index:GetModInfo(modname)) then
            matched = matched + 1
            local target_mod = mod_manager:GetMod(modname)
            patched_now = patched_now + patch_private_restart_chain(target_mod)
            register_inventory_atlases(target_mod)
            patched_now = patched_now + patch_api(target_mod)
        end
    end
    if matched == 0 then
        return
    end
    patched_now = patched_now + patch_reskin_recheck()
    patched_now = patched_now + patch_skin_ui()
    for _, player in _G.ipairs(_G.rawget(_G, "AllPlayers") or {}) do
        patched_now = patched_now + patch_player_rechecks(player)
    end
    local total = stats.item_skins
        + stats.character_skins
        + stats.ui_skins
        + stats.character_tasks
        + stats.item_callbacks
        + (stats.reskin_checks or 0)
        + (stats.restart_guards or 0)
    if total ~= last_reported_total or patched_now > 0 then
        last_reported_total = total
        print(
            _G.string.format(
                "[SKIN_BRIDGE_DENGXIAN] source=20.3 item=%d character=%d ui=%d rechecks=%d events=%d reskin=%d restart_guards=%d patched_now=%d",
                stats.item_skins,
                stats.character_skins,
                stats.ui_skins,
                stats.character_tasks,
                stats.item_callbacks,
                stats.reskin_checks or 0,
                stats.restart_guards or 0,
                patched_now
            )
        )
    end
end

patch_dengxian_skins()
AddSimPostInit(patch_dengxian_skins)

local function patch_after_world_spawn(inst)
    inst:DoTaskInTime(0, patch_dengxian_skins)
    inst:DoTaskInTime(1, patch_dengxian_skins)
    inst:DoTaskInTime(3, patch_dengxian_skins)
end

AddPrefabPostInit("world", patch_after_world_spawn)
AddPrefabPostInit("cave", patch_after_world_spawn)

AddPlayerPostInit(function(inst)
    patch_player_rechecks(inst)
    inst:DoTaskInTime(0, patch_player_rechecks)
    inst:DoTaskInTime(1, patch_player_rechecks)
    inst:DoTaskInTime(3, patch_player_rechecks)
end)
