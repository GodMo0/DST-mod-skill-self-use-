local _G = GLOBAL

local wrapped_apis = _G.setmetatable({}, { __mode = "k" })
local patched_skin_data = _G.setmetatable({}, { __mode = "k" })
local last_reported_total = -1

local stats = {
	registration = 0,
	characters = 0,
}

local function allow_server_skin()
	return true, 0
end

local function allow_client_skin()
	return true
end

local function patch_character_skin_data(data)
	if type(data) ~= "table" then
		return 0
	end

	data.checkfn = allow_server_skin
	data.checkclientfn = allow_client_skin
	data.unlock = true

	if patched_skin_data[data] then
		return 0
	end
	patched_skin_data[data] = true
	stats.characters = stats.characters + 1
	return 1
end

local function patch_character_registration(api)
	if type(api) ~= "table" then
		return 0
	end

	local original = _G.rawget(api, "MakeCharacterSkin")
	if type(original) ~= "function" then
		return 0
	end
	if wrapped_apis[api] == original then
		return 0
	end

	local wrapper = function(base, skin_name, data, ...)
		if base == "ccs" and type(skin_name) == "string" then
			patch_character_skin_data(data)
		end
		return original(base, skin_name, data, ...)
	end

	_G.rawset(api, "MakeCharacterSkin", wrapper)
	wrapped_apis[api] = wrapper
	stats.registration = stats.registration + 1
	return 1
end

local function patch_ccs_character_skins()
	local patched_now = patch_character_registration(_G.rawget(_G, "CCSAPI"))
	if stats.characters ~= last_reported_total or patched_now > 0 then
		last_reported_total = stats.characters
		print(_G.string.format(
			"[SKIN_BRIDGE_CCS] registration=%d characters=%d patched_now=%d",
			stats.registration,
			stats.characters,
			patched_now
		))
	end
end

patch_ccs_character_skins()
AddSimPostInit(patch_ccs_character_skins)

local function patch_after_world_spawn(inst)
	inst:DoTaskInTime(0, patch_ccs_character_skins)
	inst:DoTaskInTime(1, patch_ccs_character_skins)
end

AddPrefabPostInit("world", patch_after_world_spawn)
AddPrefabPostInit("cave", patch_after_world_spawn)
