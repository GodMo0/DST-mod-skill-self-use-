local _G = GLOBAL
local debug_lib = _G.rawget(_G, "debug")
local unpack_fn = _G.rawget(_G, "unpack") or _G.table.unpack

local bridge_modname = type(env) == "table" and _G.rawget(env, "modname") or nil
local ENV_MARKER = {}
local patched_authorities = _G.setmetatable({}, { __mode = "k" })
local patched_environments = _G.setmetatable({}, { __mode = "k" })

local stats = {
	hidden = 0,
	authorities = 0,
	environments = 0,
	blacklist_entries = 0,
	restart_guards = 0,
}

local function allow_local()
	return true, 0
end

local function allow()
	return true
end

local function noop()
end

local function acquire_skin_checks()
	return allow, allow_local, allow
end

local function acquire_server_check()
	return allow
end

local function pack(...)
	return { n = _G.select("#", ...), ... }
end

local function member(object, key)
	if object == nil then
		return nil
	end
	local ok, value = _G.pcall(function()
		return object[key]
	end)
	return ok and value or nil
end

local function module_name(path)
	return type(path) == "string"
		and path:gsub("^@", ""):gsub("\\", "/"):gsub("%.lua$", ""):lower()
		or ""
end

local function make_net_proxy(net)
	return _G.setmetatable({}, {
		__index = function(_, key)
			if key == "GetUserID" then
				return function()
					return ""
				end
			end
			local value = member(net, key)
			if type(value) == "function" then
				return function(_, ...)
					return value(net, ...)
				end
			end
			return value
		end,
	})
end

local function patch_authority(authority)
	if type(authority) ~= "table" then
		return false
	end
	local expected = {
		Install = true,
		AcquireSkinChecks = true,
		AcquireServerCheck = true,
	}
	local count = 0
	for key, value in _G.pairs(authority) do
		if not expected[key] or type(value) ~= "function" then
			return false
		end
		count = count + 1
	end
	if count ~= 3 then
		return false
	end
	_G.rawset(authority, "Install", allow)
	_G.rawset(authority, "AcquireSkinChecks", acquire_skin_checks)
	_G.rawset(authority, "AcquireServerCheck", acquire_server_check)
	if not patched_authorities[authority] then
		patched_authorities[authority] = true
		stats.authorities = stats.authorities + 1
	end
	return true
end

local function patch_skin_api(modenv)
	for name, fn in _G.pairs({
		VR_GateLocal_41 = allow_local,
		VR_GatePeer_73 = allow,
		VR_GateServer_26 = allow,
		VR_GateReady_58 = allow,
		TrTryLoad = noop,
	}) do
		_G.rawset(modenv, name, fn)
	end
	if type(_G.rawget(modenv, "SetSkinOwnershipPolicy")) == "function" then
		_G.rawset(modenv, "SetSkinOwnershipPolicy", allow)
	end
	if not patched_environments[modenv] then
		patched_environments[modenv] = true
		stats.environments = stats.environments + 1
	end
end

local function hide_bridge(list)
	if type(list) ~= "table" or type(bridge_modname) ~= "string" then
		return list
	end
	local clean = {}
	local count, maximum, dense = 0, 0, true
	for key in _G.pairs(list) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			dense = false
			break
		end
		count = count + 1
		maximum = _G.math.max(maximum, key)
	end
	dense = dense and count == maximum
	if dense then
		for index = 1, maximum do
			local entry = list[index]
			local modname = type(entry) == "table" and entry.modname or entry
			if modname == bridge_modname then
				stats.hidden = stats.hidden + 1
			else
				clean[#clean + 1] = entry
			end
		end
	else
		for key, entry in _G.pairs(list) do
			local modname = type(entry) == "table" and entry.modname or entry
			if modname == bridge_modname or key == bridge_modname then
				stats.hidden = stats.hidden + 1
			else
				clean[key] = entry
			end
		end
	end
	return clean
end

local function make_mod_index_proxy(index)
	local get_mods = member(index, "GetModsToLoad")
	local get_clients = member(index, "GetClientModNamesTable")
	local get_info = member(index, "GetModInfo")
	if type(get_mods) ~= "function" or type(get_info) ~= "function" then
		return index
	end

	local proxy = {
		GetModsToLoad = function(_, ...)
			return hide_bridge(get_mods(index, ...))
		end,
		GetClientModNamesTable = function(_, ...)
			return type(get_clients) == "function" and hide_bridge(get_clients(index, ...)) or {}
		end,
		GetModInfo = function(_, modname, ...)
			local info = get_info(index, modname, ...)
			if modname ~= bridge_modname or type(info) ~= "table" then
				return info
			end
			local clean = {}
			for key, value in _G.pairs(info) do
				clean[key] = value
			end
			clean.name = "Compatibility Layer"
			clean.workshopid = nil
			clean.workshop_id = nil
			clean.configuration_options = {}
			return clean
		end,
	}
	return _G.setmetatable(proxy, {
		__index = function(_, key)
			local value = member(index, key)
			if type(value) == "function" then
				return function(_, ...)
					return value(index, ...)
				end
			end
			return value
		end,
	})
end

local function install_open_environment(modenv)
	if type(modenv) ~= "table" or _G.rawget(modenv, ENV_MARKER) then
		return noop, { authority_seen = false }
	end
	_G.rawset(modenv, ENV_MARKER, true)

	local saved, installed, keys = {}, {}, {}
	local function replace(key, value)
		keys[#keys + 1] = key
		saved[key] = _G.rawget(modenv, key)
		installed[key] = value
		_G.rawset(modenv, key, value)
	end

	local index = _G.rawget(_G, "KnownModIndex")
	if index ~= nil then
		replace("KnownModIndex", make_mod_index_proxy(index))
	end

	local context = { authority_seen = false }
	local original_require = member(modenv, "require") or _G.rawget(_G, "require")
	if type(original_require) == "function" then
		replace("require", function(...)
			local result = pack(original_require(...))
			if patch_authority(result[1]) then
				context.authority_seen = true
				patch_skin_api(modenv)
			end
			return unpack_fn(result, 1, result.n)
		end)
	end

	local original_import = member(modenv, "modimport")
	if type(original_import) == "function" then
		replace("modimport", function(...)
			local path = _G.select(1, ...)
			local result
			if module_name(path) == "scripts/tr_hook" then
				local real_net = _G.rawget(_G, "TheNet")
				local net_proxy = real_net ~= nil and make_net_proxy(real_net) or nil
				local original_add = member(modenv, "AddPrefabPostInit")
				local previous_add = _G.rawget(modenv, "AddPrefabPostInit")
				local add_wrapper
				if type(original_add) == "function" then
					add_wrapper = function(prefab, callback, ...)
						if prefab == "world" then
							stats.restart_guards = stats.restart_guards + 1
							callback = noop
						end
						return original_add(prefab, callback, ...)
					end
					_G.rawset(modenv, "AddPrefabPostInit", add_wrapper)
				end
				if net_proxy ~= nil then
					_G.rawset(_G, "TheNet", net_proxy)
				end
				local guarded = pack(_G.pcall(original_import, ...))
				if net_proxy ~= nil and _G.rawget(_G, "TheNet") == net_proxy then
					_G.rawset(_G, "TheNet", real_net)
				end
				if add_wrapper ~= nil and _G.rawget(modenv, "AddPrefabPostInit") == add_wrapper then
					_G.rawset(modenv, "AddPrefabPostInit", previous_add)
				end
				if not guarded[1] then
					return _G.error(guarded[2], 0)
				end
				result = pack(unpack_fn(guarded, 2, guarded.n))
			else
				result = pack(original_import(...))
			end
			if context.authority_seen then
				patch_skin_api(modenv)
			end
			return unpack_fn(result, 1, result.n)
		end)
	end

	return function()
		if context.authority_seen then
			patch_skin_api(modenv)
		end
		for _, key in _G.ipairs(keys) do
			if _G.rawget(modenv, key) == installed[key] then
				_G.rawset(modenv, key, saved[key])
			end
		end
		_G.rawset(modenv, ENV_MARKER, nil)
	end, context
end

local function inspect_loader(fn, bridge_wrapper)
	if type(fn) ~= "function" or debug_lib == nil or type(debug_lib.getupvalue) ~= "function" then
		return 0, false
	end
	local removed, chained = 0, false
	for index = 1, 64 do
		local ok, name, value = _G.pcall(debug_lib.getupvalue, fn, index)
		if not ok or name == nil then
			break
		end
		if value == bridge_wrapper then
			chained = true
		end
		local lower = type(name) == "string" and name:lower() or ""
		if type(value) == "table"
			and (lower == "blocked_mods" or lower == "banlist" or lower == "blacklist" or lower == "blocklist")
		then
			for key in _G.pairs(value) do
				_G.rawset(value, key, nil)
				removed = removed + 1
			end
		end
	end
	stats.blacklist_entries = stats.blacklist_entries + removed
	return removed, chained
end

local function resolve_loader(manager)
	local fn = type(manager) == "table" and _G.rawget(manager, "InitializeModMain") or nil
	if type(fn) == "function" then
		return manager, fn
	end
	local ok, metatable = _G.pcall(_G.getmetatable, manager)
	local methods = ok and type(metatable) == "table" and metatable.__index or nil
	fn = type(methods) == "table" and _G.rawget(methods, "InitializeModMain") or nil
	return type(fn) == "function" and methods or nil, fn
end

local function install_loader_patch()
	local manager = _G.rawget(_G, "ModManager")
	local owner, original = resolve_loader(manager)
	if owner == nil or type(original) ~= "function" then
		return
	end

	local wrapper
	local function set_loader(fn)
		_G.rawset(manager, "InitializeModMain", fn)
		_G.rawset(owner, "InitializeModMain", fn)
	end

	wrapper = function(self, modname, modenv, ...)
		if modenv == env or modname == bridge_modname or type(modenv) ~= "table" then
			return original(self, modname, modenv, ...)
		end

		local before = stats.authorities + stats.blacklist_entries + stats.restart_guards
		local restore, context = install_open_environment(modenv)
		local result = pack(_G.pcall(original, self, modname, modenv, ...))
		restore()

		local current = member(manager, "InitializeModMain")
		local removed, chained = 0, false
		if context.authority_seen then
			removed, chained = inspect_loader(current, wrapper)
		end
		if current == original then
			set_loader(wrapper)
		elseif current ~= wrapper and removed > 0 and not chained then
			set_loader(wrapper)
		end

		if not result[1] then
			return _G.error(result[2], 0)
		end
		local after = stats.authorities + stats.blacklist_entries + stats.restart_guards
		if after > before then
			print(_G.string.format(
				"[SKIN_BRIDGE_OPEN] authority=%d env=%d blacklist=%d restart=%d",
				stats.authorities,
				stats.environments,
				stats.blacklist_entries,
				stats.restart_guards
			))
		end
		return unpack_fn(result, 2, result.n)
	end

	set_loader(wrapper)
	print("[SKIN_BRIDGE_OPEN] generic=1")
end

install_loader_patch()
