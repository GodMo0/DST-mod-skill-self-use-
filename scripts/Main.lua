local _G = GLOBAL

-- 这个表给 Update-SteamWorkshopTable.ps1 用来生成工坊版本表
local WORKSHOP_SUPPORT_MATRIX = {
	prism = { id = "1392778117", version = "7.7.0", enabled = true },
	voidrealm = { id = "2526778484", version = "2.3.1", enabled = true },
	dengxian = { id = "3235319974", version = "20.3", enabled = true },
	hmr = { id = "3609964985", version = "1.1.1.3", enabled = true },
	niaoniao = { id = "3626093627", version = "2026-08-23-1", enabled = false },
	xuaner = { id = "3014076942", version = "6.2.2", enabled = true },
	shugo = { id = "3573399040", version = "3.9", enabled = true },
	book = { id = "3544387985", version = "2.4.2", enabled = false },
	ccs = { id = "3043439883", version = "2.31043", enabled = false },
}

local function detect_enabled_source_mods()
	local current_modname = _G.rawget(env, "modname")
	local result = {
		prism = false,
		voidrealm = false,
		dengxian = false,
		hmr = false,
		niaoniao = false,
		xuaner = false,
		shugo = false,
		book = false,
		ccs = false,
	}
	local known_mod_index = _G.rawget(_G, "KnownModIndex")
	if known_mod_index == nil then
		return result
	end

	for _, modname in _G.pairs(known_mod_index:GetModsToLoad(true) or {}) do
		local modinfo = known_mod_index:GetModInfo(modname)
		local title = type(modinfo) == "table" and _G.tostring(modinfo.name or "") or ""

		if modname ~= current_modname and (
			(type(modname) == "string" and modname:find("1392778117", 1, true) ~= nil)
			or title == "[DST] Legion"
			or title == "[DST] 棱镜"
		) then
			result.prism = true
		end

		if modname ~= current_modname and (
			(type(modname) == "string" and modname:find("3235319974", 1, true) ~= nil)
			or title:find("登仙", 1, true) ~= nil
			or title:find("Deng Xian", 1, true) ~= nil
		) then
			result.dengxian = true
		end

		if modname ~= current_modname and (
			(type(modname) == "string" and modname:find("3609964985", 1, true) ~= nil)
			or title:find("丰耘秘境", 1, true) ~= nil
			or title:find("Harvest Mysterious Realm", 1, true) ~= nil
		) then
			result.hmr = true
		end

		-- 炊烟袅袅桥接暂时停用
		-- if modname ~= current_modname and (
		-- 	(type(modname) == "string" and modname:find("3626093627", 1, true) ~= nil)
		-- 	or title:find("炊烟袅袅", 1, true) ~= nil
		-- 	or title:find("Niaoniao", 1, true) ~= nil
		-- 	or title:find("niaoniao-character", 1, true) ~= nil
		-- ) then
		-- 	result.niaoniao = true
		-- end

		if modname ~= current_modname and (
			(type(modname) == "string" and modname:find("3014076942", 1, true) ~= nil)
			or title:find("璇儿", 1, true) ~= nil
			or title:find("Xuaner", 1, true) ~= nil
		) then
			result.xuaner = true
		end

		if modname ~= current_modname and (
			(type(modname) == "string" and modname:find("3573399040", 1, true) ~= nil)
			or title:find("守护甜心", 1, true) ~= nil
			or title:find("Shugo Chara", 1, true) ~= nil
		) then
			result.shugo = true
		end

		-- 万物书桥接暂时停用
		-- if modname ~= current_modname and (
		-- 	(type(modname) == "string" and modname:find("3544387985", 1, true) ~= nil)
		-- 	or title:find("万物书", 1, true) ~= nil
		-- 	or title:find("The Book of All Things", 1, true) ~= nil
		-- 	or title:find("沉迷幻境", 1, true) ~= nil
		-- ) then
		-- 	result.book = true
		-- end

		-- 魔法少女小樱桥接暂时停用
		-- if modname ~= current_modname and (
		-- 	(type(modname) == "string" and modname:find("3043439883", 1, true) ~= nil)
		-- 	or title:find("魔法少女小樱", 1, true) ~= nil
		-- 	or title:find("Cardcaptor Sakura", 1, true) ~= nil
		-- ) then
		-- 	result.ccs = true
		-- end
	end
	return result
end

local function config_enabled(option_name, default)
	local getter = _G.rawget(env, "GetModConfigData")
	if type(getter) ~= "function" then
		return default
	end

	local ok, value = _G.pcall(getter, option_name)
	if not ok or value == nil then
		return default
	end
	if value == true or value == 1 then
		return true
	end
	if value == false or value == 0 then
		return false
	end
	return default
end

local function apply_patch_configuration(enabled)
	enabled.prism = enabled.prism and config_enabled("enable_prism_skin_unlock", false)
	enabled.dengxian = enabled.dengxian and config_enabled("enable_dengxian_skin_unlock", false)
	enabled.hmr = enabled.hmr and config_enabled("enable_hmr_skin_unlock", false)
	enabled.xuaner = enabled.xuaner and config_enabled("enable_xuaner_skin_unlock", false)
	enabled.shugo = enabled.shugo and config_enabled("enable_shugo_skin_unlock", false)
	return enabled
end

local enabled = apply_patch_configuration(detect_enabled_source_mods())
_G.rawset(_G, "PRISM_TERRA_SKIN_BRIDGE_ACTIVE", enabled)

print(
	_G.string.format(
		"[SKIN_BRIDGE] detected prism=%d voidrealm=%d dengxian=%d hmr=%d niaoniao=%d xuaner=%d shugo=%d book=%d ccs=%d",
		enabled.prism and 1 or 0,
		enabled.voidrealm and 1 or 0,
		enabled.dengxian and 1 or 0,
		enabled.hmr and 1 or 0,
		enabled.niaoniao and 1 or 0,
		enabled.xuaner and 1 or 0,
		enabled.shugo and 1 or 0,
		enabled.book and 1 or 0,
		enabled.ccs and 1 or 0
	)
)

if enabled.prism then
	modimport("scripts/Legion.lua")
end

if enabled.voidrealm then
	modimport("scripts/Void_Realm.lua")
end

if enabled.dengxian then
	modimport("scripts/Deng_Xian.lua")
end

if enabled.hmr then
	modimport("scripts/Harvest_Mysterious_Realm.lua")
end

-- 炊烟袅袅桥接暂时停用
-- if enabled.niaoniao then
-- 	modimport("scripts/Niaoniao_Character.lua")
-- end

if enabled.xuaner then
	modimport("scripts/Xuaner_Myxl.lua")
end

if enabled.shugo then
	modimport("scripts/Shugo_Chara.lua")
end

-- 万物书桥接暂时停用
-- if enabled.book then
-- 	modimport("scripts/Book_of_All_Things.lua")
-- end

-- 魔法少女小樱桥接暂时停用
-- if enabled.ccs then
-- 	modimport("scripts/Cardcaptor_Sakura.lua")
-- end
