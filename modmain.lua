local _G = GLOBAL

_G.setmetatable(env, {
	__index = function(_, key)
		return _G.rawget(_G, key)
	end,
})

modimport("scripts/Main.lua")
