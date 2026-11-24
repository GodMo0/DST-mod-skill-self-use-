local _G = GLOBAL
local debug_lib = _G.rawget(_G, "debug")
local error_fn = _G.rawget(_G, "error")

local PRISM_PATCH_PROFILE = "7.7.0"
local PRISM_WORKSHOP_ID = "1392778117"
local PRISM_KICK_RPC = "ufnzoql_L"

local function allow_all_skins()
	return true
end

local function allow_all_users()
	return 0
end

local function allow_all_builds()
	return false
end

local function harmless_integrity_check()
	return false
end

local function noop()
end

local cleared_access_tables = _G.setmetatable({}, { __mode = "k" })
local scheduled_scan_hosts = _G.setmetatable({}, { __mode = "k" })

local active_legion_modenv = nil
local active_legion_skin_data = nil
local patch_scan_in_progress = false
local legion_patch_complete = false
local require_hook_installed = false
local reskin_refresh_installed = false

local function safe_field(value, key)
	if value == nil then
		return nil
	end
	local ok, result = _G.pcall(function()
		return value[key]
	end)
	return ok and result or nil
end

local function is_dedicated()
	local net = _G.rawget(_G, "TheNet")
	local method = safe_field(net, "IsDedicated")
	if type(method) ~= "function" then
		return false
	end
	local ok, value = _G.pcall(method, net)
	return ok and value == true
end

local function is_prism_modname(modname)
	return type(modname) == "string" and modname:find(PRISM_WORKSHOP_ID, 1, true) ~= nil
end

local function get_upvalue(fn, index)
	if type(fn) ~= "function" or debug_lib == nil
		or type(debug_lib.getupvalue) ~= "function" then
		return nil
	end
	local ok, name, value = _G.pcall(debug_lib.getupvalue, fn, index)
	if not ok then
		return nil
	end
	return name, value
end

local function setup_upvalue(fn, index, replacement)
	if type(fn) ~= "function" or debug_lib == nil
		or type(debug_lib.setupvalue) ~= "function" then
		return false
	end
	local ok = _G.pcall(debug_lib.setupvalue, fn, index, replacement)
	if not ok then
		return false
	end
	local _, current = get_upvalue(fn, index)
	return current == replacement
end

local function find_named_upvalue(fn, accepted, limit)
	for index = 1, limit or 64 do
		local name, value = get_upvalue(fn, index)
		if name == nil then
			break
		end
		if accepted[name] then
			return index, name, value
		end
	end
	return nil
end

local ACCESS_FUNCTION_NAMES = { B = true, getAccessLevel = true }
local ACCESS_TABLE_NAMES = { k = true, ACCESS_LEVEL_BY_ENCODED_ID = true }
local AVAILABILITY_NAMES = { Fs = true, isSkinAvailableToUser = true }
local SET_SKIN_NAMES = { vs = true, setSkin = true }
local INSTALL_BUILD_NAMES = { Us = true, installBuildHook = true }
local BUILD_GATE_NAMES = { o = true, shouldOverrideBuild = true }
local FAIL_CHECK_NAMES = { Ns = true, failIntegrityCheck = true }
local INTEGRITY_CHECK_NAMES = { ks = true, verifySkinDataIntegrity = true }

local function clear_access_map(access_fn)
	if type(access_fn) ~= "function" then
		return
	end
	local _, _, access_map = find_named_upvalue(access_fn, ACCESS_TABLE_NAMES, 16)
	if type(access_map) ~= "table" then
		return
	end
	if cleared_access_tables[access_map] then
		return
	end

	local keys = {}
	for key in _G.pairs(access_map) do
		keys[#keys + 1] = key
	end
	for _, key in _G.ipairs(keys) do
		_G.rawset(access_map, key, nil)
	end
	cleared_access_tables[access_map] = true
end

local function patch_access_reference(fn)
	local index, _, access_fn = find_named_upvalue(fn, ACCESS_FUNCTION_NAMES, 32)
	if index == nil or type(access_fn) ~= "function" then
		return 0
	end
	if access_fn ~= allow_all_users then
		clear_access_map(access_fn)
	end
	return setup_upvalue(fn, index, allow_all_users) and 1 or 0
end

local function patch_availability_reference(fn)
	local index, _, availability_fn = find_named_upvalue(fn, AVAILABILITY_NAMES, 32)
	if index == nil or type(availability_fn) ~= "function" then
		return 0
	end
	return setup_upvalue(fn, index, allow_all_skins) and 1 or 0
end

local function function_info(fn)
	if type(fn) ~= "function" or debug_lib == nil or type(debug_lib.getinfo) ~= "function" then
		return nil
	end
	local ok, info = _G.pcall(debug_lib.getinfo, fn, "Snu")
	return ok and type(info) == "table" and info or nil
end

local function has_raw_770_player_guard_signature(fn)
	local expected = {
		[1] = "U",
		[2] = "Ws",
		[3] = "B",
		[8] = "Ns",
		[14] = "ks",
	}
	for index, expected_name in _G.pairs(expected) do
		local name = get_upvalue(fn, index)
		if name ~= expected_name then
			return false
		end
	end
	local info = function_info(fn)
	return info == nil or info.nups == nil or info.nups == 15
end

local function is_readable_770_player_guard(fn)
	local info = function_info(fn)
	if info == nil then
		return false
	end
	local source = tostring(info.source or "")
	local line = tonumber(info.linedefined)
	return source:find("modmain.lua", 1, true) ~= nil
		and line ~= nil and line >= 5200 and line <= 5250
end

local function is_raw_770_main_chunk(fn)
	local info = function_info(fn)
	local source = info and tostring(info.source or "") or ""
	return source:find("local is,cs do", 1, true) ~= nil
		or source:find("(k()).debug.sethook()", 1, true) ~= nil
end

local function patch_770_player_guard(fn)
	if type(fn) ~= "function" then
		return
	end
	local raw_signature = has_raw_770_player_guard_signature(fn)
	if not raw_signature and not is_readable_770_player_guard(fn)
		and not is_raw_770_main_chunk(fn) then
		return
	end

	for index = 1, 32 do
		local name, value = get_upvalue(fn, index)
		if name == nil then
			break
		end
		if ACCESS_FUNCTION_NAMES[name] and type(value) == "function" then
			if value ~= allow_all_users then
				clear_access_map(value)
			end
			setup_upvalue(fn, index, allow_all_users)
		elseif FAIL_CHECK_NAMES[name] and type(value) == "function" then
			setup_upvalue(fn, index, harmless_integrity_check)
		elseif INTEGRITY_CHECK_NAMES[name] and type(value) == "function" then
			setup_upvalue(fn, index, harmless_integrity_check)
		elseif AVAILABILITY_NAMES[name] and type(value) == "function" then
			setup_upvalue(fn, index, allow_all_skins)
		end
	end
end

local function is_postinit_blacklist_callback(fn)
	local info = function_info(fn)
	if info ~= nil then
		local source = tostring(info.source or "")
		local line = tonumber(info.linedefined)
		if source:find("postinit_legion.lua", 1, true) ~= nil
			and line ~= nil and line >= 331 and line <= 347 then
			return true
		end
	end

	local string_lib = _G.rawget(_G, "string")
	local dump_fn = type(string_lib) == "table" and _G.rawget(string_lib, "dump") or nil
	if type(dump_fn) == "function" then
		local ok, dumped = _G.pcall(dump_fn, fn)
		if ok and type(dumped) == "string" then
			local matches = 0
			for _, user_id in _G.ipairs({ "KU_3NiPP26E", "KU_qE7e9BEF", "KU_jvdHqV3-" }) do
				if dumped:find(user_id, 1, true) ~= nil then
					matches = matches + 1
				end
			end
			return matches >= 2
		end
	end
	return false
end

local function install_prism_callback_guards(modenv)
	if type(modenv) ~= "table" or _G.rawget(modenv, "PRISM_CALLBACK_GUARDS_770") then
		return
	end

	local add_player = _G.rawget(modenv, "AddPlayerPostInit")
	if type(add_player) == "function" then
		_G.rawset(modenv, "AddPlayerPostInit", function(callback, ...)
			if is_postinit_blacklist_callback(callback) then
				return add_player(noop, ...)
			end
			patch_770_player_guard(callback)
			return add_player(callback, ...)
		end)
	end

	local add_client_rpc = _G.rawget(modenv, "AddClientModRPCHandler")
	if type(add_client_rpc) == "function" then
		_G.rawset(modenv, "AddClientModRPCHandler", function(namespace, name, callback, ...)
			if namespace == "LegionSkin" and name == PRISM_KICK_RPC then
				return add_client_rpc(namespace, name, noop, ...)
			end
			return add_client_rpc(namespace, name, callback, ...)
		end)
	end

	_G.rawset(modenv, "PRISM_CALLBACK_GUARDS_770", true)
end

local initialized_modmain_guard = false
local initialized_modmain_wrapper = nil
local initialized_modmain_original = nil

local function install_prism_load_guard()
	if initialized_modmain_guard then
		return
	end
	local manager = _G.rawget(_G, "ModManager")
	local original = safe_field(manager, "InitializeModMain")
	local method_owner = manager
	if type(original) ~= "function" and manager ~= nil then
		local meta = _G.getmetatable(manager)
		local methods = type(meta) == "table" and _G.rawget(meta, "__index") or nil
		if type(methods) == "table" then
			original = _G.rawget(methods, "InitializeModMain")
			method_owner = methods
		end
	end
	if type(original) ~= "function" then
		return
	end

	initialized_modmain_original = original
	initialized_modmain_wrapper = function(self, modname, modenv, ...)
		if not is_prism_modname(modname) then
			return initialized_modmain_original(self, modname, modenv, ...)
		end

		install_prism_callback_guards(modenv)
		local old_global_net = _G.rawget(_G, "TheNet")
		local old_env_net = type(modenv) == "table" and _G.rawget(modenv, "TheNet") or nil
		local debug_table = _G.rawget(_G, "debug")
		local old_sethook = type(debug_table) == "table" and _G.rawget(debug_table, "sethook") or nil
		local global_net_replaced = false
		local env_net_replaced = false
		local debug_replaced = false

		if old_global_net ~= nil then
			local proxy = {}
			_G.setmetatable(proxy, {
				__index = function(_, key)
					if key == "GetUserID" then
						return function()
							return ""
						end
					end
					local ok, value = _G.pcall(function()
						return old_global_net[key]
					end)
					if not ok then
						return nil
					end
					if type(value) == "function" then
						return function(_, ...)
							return value(old_global_net, ...)
						end
					end
					return value
				end,
			})
			global_net_replaced = _G.pcall(function()
				_G.rawset(_G, "TheNet", proxy)
			end)
			if type(modenv) == "table" then
				env_net_replaced = _G.pcall(function()
					_G.rawset(modenv, "TheNet", proxy)
				end)
			end
		end

		if type(old_sethook) == "function" then
			debug_replaced = _G.pcall(function()
				debug_table.sethook = noop
			end)
		end

		local result = { _G.pcall(initialized_modmain_original, self, modname, modenv, ...) }
		if global_net_replaced then
			_G.pcall(function()
				_G.rawset(_G, "TheNet", old_global_net)
			end)
		end
		if env_net_replaced and type(modenv) == "table" then
			_G.pcall(function()
				_G.rawset(modenv, "TheNet", old_env_net)
			end)
		end
		if debug_replaced then
			_G.pcall(function()
				debug_table.sethook = old_sethook
			end)
		end

		_G.pcall(function()
			manager.InitializeModMain = initialized_modmain_wrapper
		end)
		if method_owner ~= manager then
			_G.pcall(function()
				method_owner.InitializeModMain = initialized_modmain_wrapper
			end)
		end

		if not result[1] then
			if type(error_fn) == "function" then
				error_fn(result[2], 0)
			end
			return nil
		end
		return result[2]
	end

	local ok = _G.pcall(function()
		manager.InitializeModMain = initialized_modmain_wrapper
	end)
	if not ok or safe_field(manager, "InitializeModMain") ~= initialized_modmain_wrapper then
		ok = _G.pcall(function()
			method_owner.InitializeModMain = initialized_modmain_wrapper
		end)
	end
	if ok then
		initialized_modmain_guard = true
	end
end

install_prism_load_guard()

local function get_legion_skin_data()
	if type(active_legion_skin_data) == "table" then
		return active_legion_skin_data
	end
	if type(active_legion_modenv) == "table" then
		local data = _G.rawget(active_legion_modenv, "ls_skineddata")
		if type(data) == "table" then
			active_legion_skin_data = data
			return data
		end
	end
	local data = _G.rawget(_G, "ls_skineddata")
	if type(data) == "table" then
		active_legion_skin_data = data
		return data
	end
	return nil
end

local function register_prism_skin_index(prefab, skin_id)
	if type(prefab) ~= "string" or type(skin_id) ~= "string" then
		return
	end
	local prefab_skins = _G.rawget(_G, "PREFAB_SKINS")
	local prefab_ids = _G.rawget(_G, "PREFAB_SKINS_IDS")
	if type(prefab_skins) ~= "table" or type(prefab_ids) ~= "table" then
		return
	end
	local list = _G.rawget(prefab_skins, prefab)
	if type(list) ~= "table" then
		list = {}
		_G.rawset(prefab_skins, prefab, list)
	end
	local ids = _G.rawget(prefab_ids, prefab)
	if type(ids) ~= "table" then
		ids = {}
		_G.rawset(prefab_ids, prefab, ids)
	end
	if _G.rawget(ids, skin_id) == nil then
		list[#list + 1] = skin_id
		_G.rawset(ids, skin_id, #list)
	end
end

local function index_prism_skins(data)
	if type(data) ~= "table" then
		return 0
	end
	local count = 0
	for skin_id, skin_def in _G.pairs(data) do
		if type(skin_id) == "string" and type(skin_def) == "table" then
			local prefab = _G.rawget(skin_def, "base_prefab")
			if type(prefab) == "string" then
				count = count + 1
				register_prism_skin_index(prefab, skin_id)
			end
		end
	end
	return count
end

local function patch_set_skin_export(setup_skin_replica)
	local _, _, set_skin = find_named_upvalue(setup_skin_replica, SET_SKIN_NAMES, 24)
	if type(set_skin) ~= "function" then
		return 0, 0
	end
	return patch_access_reference(set_skin), patch_availability_reference(set_skin)
end

local function patch_build_export(initialize_skin_entity)
	local _, _, install_build_hook = find_named_upvalue(initialize_skin_entity, INSTALL_BUILD_NAMES, 32)
	if type(install_build_hook) ~= "function" then
		return 0, false
	end
	local index, _, gate = find_named_upvalue(install_build_hook, BUILD_GATE_NAMES, 16)
	if index == nil or type(gate) ~= "function" then
		return 0, true
	end
	return setup_upvalue(install_build_hook, index, allow_all_builds) and 1 or 0, true
end

local function resolve_export(modenv, name)
	local value = type(modenv) == "table" and _G.rawget(modenv, name) or nil
	if type(value) ~= "function" then
		value = _G.rawget(_G, name)
	end
	return type(value) == "function" and value or nil
end

local function build_full_shop_items(screen)
	local data = get_legion_skin_data()
	if type(data) ~= "table" then
		return
	end
	local selected = safe_field(safe_field(screen, "selected_item"), "item_key")
	local skin_ids = {}
	for skin_id, skin_def in _G.pairs(data) do
		if type(skin_id) == "string" and type(skin_def) == "table"
			and type(_G.rawget(skin_def, "base_prefab")) == "string"
			and _G.rawget(skin_def, "noshow") ~= true then
			skin_ids[#skin_ids + 1] = skin_id
		end
	end
	_G.table.sort(skin_ids)

	local items = {}
	local selected_item = nil
	for _, skin_id in _G.ipairs(skin_ids) do
		local item = {
			item_key = skin_id,
			item_id = skin_id,
			owned_count = 1,
			isnew = false,
			isfocused = false,
			isselected = false,
			isowned = true,
			isunlockable = false,
		}
		items[#items + 1] = item
		if selected == skin_id then
			selected_item = item
		end
	end

	local set_items = safe_field(screen, "SetItems")
	if type(set_items) == "function" then
		_G.pcall(set_items, screen, items)
	end
	local set_info = safe_field(screen, "SetItemInfo")
	if type(set_info) == "function" and items[1] ~= nil then
		_G.pcall(set_info, screen, selected_item or items[1])
	end
end

local function patch_shop_instance(instance)
	if type(instance) ~= "table" or _G.rawget(instance, "__prism_770_shop_wrapped") then
		return
	end
	local reset_items = safe_field(instance, "ResetItems")
	if type(reset_items) ~= "function" then
		return
	end

	local attention = safe_field(instance, "bg_attention")
	if attention ~= nil then
		local kill = safe_field(attention, "Kill")
		if type(kill) == "function" then
			_G.pcall(kill, attention)
		end
		_G.rawset(instance, "bg_attention", nil)
	end
	_G.rawset(instance, "tagtag", 1)
	_G.rawset(instance, "__prism_770_shop_wrapped", true)
	_G.rawset(instance, "ResetItems", function(self, ...)
		local ok, result = _G.pcall(reset_items, self, ...)
		build_full_shop_items(self)
		return ok and result or nil
	end)
	_G.pcall(function()
		instance:ResetItems()
	end)
end

local function hook_shop_class(classdef)
	if type(classdef) ~= "table" then
		return
	end
	if _G.rawget(classdef, "__prism_770_ctor") then
		return
	end
	local constructor = _G.rawget(classdef, "_ctor")
	if type(constructor) ~= "function" then
		return
	end
	_G.rawset(classdef, "_ctor", function(self, ...)
		constructor(self, ...)
		_G.pcall(patch_shop_instance, self)
	end)
	_G.rawset(classdef, "__prism_770_ctor", true)
end

local function install_shop_require_hook()
	if require_hook_installed or is_dedicated() then
		return
	end
	local require_fn = _G.rawget(_G, "require")
	local package_lib = _G.rawget(_G, "package")
	if type(require_fn) ~= "function" or type(package_lib) ~= "table" then
		return
	end
	if _G.rawget(_G, "PRISM_770_SHOP_REQUIRE_HOOK") then
		require_hook_installed = true
		return
	end
	_G.rawset(_G, "PRISM_770_SHOP_REQUIRE_HOOK", true)
	_G.rawset(_G, "require", function(module_name, ...)
		local result = require_fn(module_name, ...)
		if module_name == "widgets/skinlegiondialog" then
			hook_shop_class(result)
		end
		return result
	end)
	require_hook_installed = true
	local loaded = _G.rawget(package_lib, "loaded")
	if type(loaded) == "table" then
		hook_shop_class(_G.rawget(loaded, "widgets/skinlegiondialog"))
	end
end

local function install_reskin_refresh()
	if reskin_refresh_installed or is_dedicated() or type(AddPrefabPostInitAny) ~= "function" then
		return
	end
	reskin_refresh_installed = true
	AddPrefabPostInitAny(function(inst)
		if inst == nil or type(safe_field(inst, "DoTaskInTime")) ~= "function" then
			return
		end
		local components = safe_field(inst, "components")
		if type(components) ~= "table" or _G.rawget(components, "skinedlegion") == nil then
			return
		end
		local function refresh()
			local push_event = safe_field(inst, "PushEvent")
			if type(push_event) == "function" then
				push_event(inst, "skin_idx_l_dirty")
				push_event(inst, "pskin_idx_l_dirty")
			end
		end
		for _, delay in _G.ipairs({ 0.2, 1.5, 4, 8 }) do
			inst:DoTaskInTime(delay, refresh)
		end
	end)
end

local function is_legion_770(modname, modinfo)
	if type(modinfo) ~= "table" or tostring(_G.rawget(modinfo, "version") or "") ~= PRISM_PATCH_PROFILE then
		return false
	end
	if is_prism_modname(modname) then
		return true
	end
	local title = tostring(_G.rawget(modinfo, "name") or "")
	return title == "[DST] Legion" or title == "[DST]棱镜" or title == "[DST] 棱镜"
end

local function patch_legion(modenv)
	if type(modenv) ~= "table" then
		return
	end
	active_legion_modenv = modenv
	local exported_data = _G.rawget(modenv, "ls_skineddata")
	if type(exported_data) ~= "table" then
		exported_data = _G.rawget(_G, "ls_skineddata")
	end
	local indexed = 0
	if type(exported_data) == "table" then
		active_legion_skin_data = exported_data
		indexed = index_prism_skins(exported_data)
	end

	local setup_skin = resolve_export(modenv, "LS_C_Set")
	local initialize_skin = resolve_export(modenv, "LS_C_Init")
	local broom = resolve_export(modenv, "LS_Broom")
	local access, availability = 0, 0
	if setup_skin ~= nil then
		access, availability = patch_set_skin_export(setup_skin)
	end
	if broom ~= nil then
		access = access + patch_access_reference(broom)
	end
	local build, build_required = 0, false
	if initialize_skin ~= nil then
		build, build_required = patch_build_export(initialize_skin)
	end

	local complete = setup_skin ~= nil
		and initialize_skin ~= nil
		and access > 0
		and availability > 0
		and indexed >= 136
		and (not build_required or build > 0)
	if complete then
		legion_patch_complete = true
	end
end

local function patch_loaded_legion_mods()
	if debug_lib == nil or type(debug_lib.getupvalue) ~= "function"
		or type(debug_lib.setupvalue) ~= "function" then
		return
	end
	install_shop_require_hook()
	if legion_patch_complete then
		return
	end
	local known_mod_index = _G.rawget(_G, "KnownModIndex")
	local mod_manager = _G.rawget(_G, "ModManager")
	if known_mod_index == nil or mod_manager == nil then
		return
	end
	local get_mods = safe_field(known_mod_index, "GetModsToLoad")
	local get_info = safe_field(known_mod_index, "GetModInfo")
	local get_mod = safe_field(mod_manager, "GetMod")
	if type(get_mods) ~= "function" or type(get_info) ~= "function" then
		return
	end
	local ok, modnames = _G.pcall(get_mods, known_mod_index, true)
	if not ok or type(modnames) ~= "table" then
		return
	end

	for _, modname in _G.pairs(modnames) do
		local info_ok, modinfo = _G.pcall(get_info, known_mod_index, modname)
		if info_ok and is_legion_770(modname, modinfo) then
			local modenv = nil
			if type(get_mod) == "function" then
				local env_ok, value = _G.pcall(get_mod, mod_manager, modname)
				if env_ok and type(value) == "table" then
					modenv = value
				end
			end
			patch_legion(modenv or _G)
		end
	end
end

local function patch_loaded_legion_mods_safe()
	if patch_scan_in_progress then
		return
	end
	patch_scan_in_progress = true
	_G.pcall(patch_loaded_legion_mods)
	patch_scan_in_progress = false
end

local function schedule_scans(inst)
	if inst == nil or type(safe_field(inst, "DoTaskInTime")) ~= "function"
		or scheduled_scan_hosts[inst] then
		return
	end
	scheduled_scan_hosts[inst] = true
	for _, delay in _G.ipairs({ 0, 0.25, 1, 3, 8, 15, 30 }) do
		inst:DoTaskInTime(delay, function()
			if not legion_patch_complete then
				patch_loaded_legion_mods_safe()
			end
		end)
	end
end

install_shop_require_hook()
install_reskin_refresh()
patch_loaded_legion_mods_safe()

AddSimPostInit(function(inst)
	patch_loaded_legion_mods_safe()
	schedule_scans(_G.rawget(_G, "TheWorld") or inst)
end)

local function after_world_spawn(inst)
	schedule_scans(inst)
end

AddPrefabPostInit("world", after_world_spawn)
AddPrefabPostInit("cave", after_world_spawn)

AddPlayerPostInit(function(inst)
	if inst ~= nil and type(safe_field(inst, "DoTaskInTime")) == "function" then
		inst:DoTaskInTime(0.5, patch_loaded_legion_mods_safe)
		inst:DoTaskInTime(2, patch_loaded_legion_mods_safe)
	end
end)
