local _G = GLOBAL

local TARGET_ID = "3573399040"
local known_skins = {}
local patched_skin_data = _G.setmetatable({}, { __mode = "k" })
local registration_states = _G.setmetatable({}, { __mode = "k" })
local inventory_states = _G.setmetatable({}, { __mode = "k" })
local scheduled_hosts = _G.setmetatable({}, { __mode = "k" })
local last_reported_total = -1

local stats = {
	character_skins = 0,
	item_skins = 0,
	registration_wrappers = 0,
	inventory_wrappers = 0,
}

local function allow_skin()
	return true
end

local function allow_skin_latest()
	return true, 0
end

local function remember_skin(name, data, kind)
	if type(name) ~= "string" or type(data) ~= "table" then
		return false
	end

	known_skins[name] = true
	data.checkfn = allow_skin
	data.checkclientfn = allow_skin
	data.is_restricted = false
	data.unlock = true

	if patched_skin_data[data] then
		return false
	end
	patched_skin_data[data] = true
	if kind == "character" or data.ischaracterskins then
		stats.character_skins = stats.character_skins + 1
	else
		stats.item_skins = stats.item_skins + 1
	end
	return true
end

local function patch_registry(registry, kind)
	if type(registry) ~= "table" then
		return 0
	end

	local changed = 0
	for name, data in _G.pairs(registry) do
		if remember_skin(name, data, kind) then
			changed = changed + 1
		end
	end
	return changed
end

local function patch_registration(api, name, kind)
	local current = _G.rawget(api, name)
	if type(current) ~= "function" then
		return 0
	end

	local states = registration_states[api]
	if states == nil then
		states = {}
		registration_states[api] = states
	end
	if states[name] == current then
		return 0
	end

	local original = current
	local wrapper = function(base, skin_name, data, ...)
		remember_skin(skin_name, data, kind)
		return original(base, skin_name, data, ...)
	end
	_G.rawset(api, name, wrapper)
	states[name] = wrapper
	stats.registration_wrappers = stats.registration_wrappers + 1
	return 1
end

local function patch_api(api)
	if type(api) ~= "table" then
		return 0
	end

	local changed = 0
	local get_all_skin = _G.rawget(api, "GetAllSkin")
	if type(get_all_skin) == "function" then
		local ok, character_skins, item_skins = _G.pcall(get_all_skin)
		if ok then
			changed = changed + patch_registry(character_skins, "character")
			changed = changed + patch_registry(item_skins, "item")
		end
	end

	for _, name in _G.ipairs({ "_SkinCheckFn", "_SkinCheckClientFn", "skdwdwswpp" }) do
		if type(_G.rawget(api, name)) == "function" then
			_G.rawset(api, name, allow_skin)
		end
	end

	changed = changed + patch_registration(api, "MakeCharacterSkin", "character")
	changed = changed + patch_registration(api, "MakeItemSkin", "item")
	return changed
end

local function is_known_skin(api, name)
	if type(name) ~= "string" then
		return false
	end
	if known_skins[name] then
		return true
	end

	local get_skin_map = type(api) == "table" and _G.rawget(api, "GetSkinMap") or nil
	if type(get_skin_map) == "function" then
		local ok, mapped = _G.pcall(get_skin_map, name)
		if ok and known_skins[mapped] then
			return true
		end
	end

	local get_skin = type(api) == "table" and _G.rawget(api, "GetSkin") or nil
	if type(get_skin) == "function" then
		local ok, data = _G.pcall(get_skin, name)
		if ok and type(data) == "table" then
			return true
		end
	end
	return false
end

local function patch_inventory(api)
	local inventory = _G.rawget(_G, "TheInventory")
	if inventory == nil then
		return 0
	end

	local metatable = _G.getmetatable(inventory)
	local index = type(metatable) == "table" and metatable.__index or nil
	if type(index) ~= "table" then
		return 0
	end

	local state = inventory_states[index]
	if state == nil then
		state = {}
		inventory_states[index] = state
	end

	local changed = 0
	local function wrap(name, kind)
		local current = _G.rawget(index, name)
		if type(current) ~= "function" or state[name] == current then
			return
		end
		local original = current
		local wrapper
		if kind == "client" then
			wrapper = function(self, userid, skin_name, ...)
				if is_known_skin(api, skin_name) then
					return true
				end
				return original(self, userid, skin_name, ...)
			end
		elseif kind == "latest" then
			wrapper = function(self, skin_name, ...)
				if is_known_skin(api, skin_name) then
					return allow_skin_latest()
				end
				return original(self, skin_name, ...)
			end
		else
			wrapper = function(self, skin_name, ...)
				if is_known_skin(api, skin_name) then
					return true
				end
				return original(self, skin_name, ...)
			end
		end
		_G.rawset(index, name, wrapper)
		state[name] = wrapper
		changed = changed + 1
		stats.inventory_wrappers = stats.inventory_wrappers + 1
	end

	wrap("CheckOwnership", "owner")
	wrap("CheckOwnershipGetLatest", "latest")
	wrap("CheckClientOwnership", "client")
	return changed
end

local function find_target_mod()
	local known_mod_index = _G.rawget(_G, "KnownModIndex")
	local mod_manager = _G.rawget(_G, "ModManager")
	if known_mod_index == nil or mod_manager == nil then
		return nil, nil
	end

	local fallback = nil
	for _, modname in _G.pairs(known_mod_index:GetModsToLoad(true) or {}) do
		local name_text = _G.tostring(modname)
		if name_text:find(TARGET_ID, 1, true) ~= nil then
			return mod_manager:GetMod(modname), name_text
		end
		local modinfo = known_mod_index:GetModInfo(modname)
		local title = type(modinfo) == "table" and _G.tostring(modinfo.name or "") or ""
		if title:find("守护甜心", 1, true) ~= nil or title:find("Shugo Chara", 1, true) ~= nil then
			fallback = { mod_manager:GetMod(modname), name_text }
		end
	end
	if fallback ~= nil then
		return fallback[1], fallback[2]
	end
	return nil, nil
end

local function patch_shugo_skins()
	local api, modname = find_target_mod()
	if modname == nil then
		return
	end

	local changed = patch_api(api) + patch_inventory(api)
	local total = stats.character_skins + stats.item_skins
	if total ~= last_reported_total or changed > 0 then
		last_reported_total = total
		print(_G.string.format(
			"[SKIN_BRIDGE_SHUGO] mod=%s skins=%d character=%d item=%d registration=%d inventory=%d changed=%d",
			modname,
			total,
			stats.character_skins,
			stats.item_skins,
			stats.registration_wrappers,
			stats.inventory_wrappers,
			changed
		))
	end
end

patch_shugo_skins()
AddGamePostInit(patch_shugo_skins)
AddSimPostInit(patch_shugo_skins)

local function schedule_scans(inst)
	if inst == nil or type(inst.DoTaskInTime) ~= "function" or scheduled_hosts[inst] then
		return
	end
	scheduled_hosts[inst] = true
	for _, delay in _G.ipairs({ 0, 0.25, 1, 3, 8, 30 }) do
		inst:DoTaskInTime(delay, patch_shugo_skins)
	end
end

AddPrefabPostInit("world", schedule_scans)
AddPrefabPostInit("cave", schedule_scans)
AddPlayerPostInit(function(inst)
	inst:DoTaskInTime(0.5, patch_shugo_skins)
	inst:DoTaskInTime(2, patch_shugo_skins)
end)
