local G = GLOBAL
local kind, pairs, ipairs = G.type, G.pairs, G.ipairs
local read, write, attempt = G.rawget, G.rawset, G.pcall
local dbg = read(G, "debug")
local original_require = read(G, "require")
local TARGET_ID = "3014076942"
local TARGET_VERSION = "6.2.2"
local states = G.setmetatable({}, {__mode = "k"})

local function noop()
end

local function reject()
    return false
end

local function pack(...)
    return {n = G.select("#", ...), ...}
end

local unpack = G.unpack or G.table.unpack

local function normalize(path)
    if kind(path) ~= "string" then
        return ""
    end
    return path:gsub("\\", "/"):gsub("%.lua$", ""):gsub("^scripts/", ""):lower()
end

local function is_target_env(modenv)
    if kind(modenv) ~= "table" then
        return false
    end
    local name = G.tostring(read(modenv, "modname") or "")
    local root = G.tostring(read(modenv, "MODROOT") or ""):gsub("\\", "/")
    return name == "workshop-" .. TARGET_ID
        or name == TARGET_ID
        or root:find("/" .. TARGET_ID .. "/", 1, true) ~= nil
        or name == "MYXL"
        or name:find("2199027653598532975", 1, true) ~= nil
end

local function protected(name)
    return name == "moyuxuanli_nill" or name == "moyuxuanli_nill_tmp"
end

local function target_name(name, data, base)
    if kind(name) ~= "string" or protected(name) then
        return false
    end
    base = base or kind(data) == "table" and data.base_prefab or nil
    return name == "moyuxuanli"
        or name:find("^moyuxuanli_") ~= nil
        or name:find("^myxl_") ~= nil
        or base == "moyuxuanli"
        or kind(base) == "string" and base:find("^myxl_") ~= nil
end

local function is_skin_endpoint(url)
    if kind(url) ~= "string" then
        return false
    end
    local host, path = url:lower():match("^https?://([^/]+)(/.*)$")
    if host == "127.0.0.1:3150" or host == "8.140.236.29:3150" then
        return path == "/useropen" or path:match("^/useropen[/?&]") ~= nil
    end
    if host == "xuaner.flapi.cn" or host == "127.0.0.1" then
        return path == "/api/dst" or path:match("^/api/dst[/?&]") ~= nil
    end
    return false
end

local function install(modenv)
    if states[modenv] ~= nil then
        return states[modenv].finish
    end
    local state = {
        registry = {},
        constructors = {},
        ui = nil,
        active_import = "",
    }
    states[modenv] = state
    local original_import = read(modenv, "modimport")
    local report_once = {}

    local function report(key)
        if not report_once[key] then
            report_once[key] = true
            G.print("[SKIN_BRIDGE_XUANER] " .. key)
        end
    end

    local function registries()
        local getter = read(modenv, "GetAllSkin")
        if kind(getter) ~= "function" then
            return {}, {}
        end
        local ok, characters, items = attempt(getter)
        if not ok then
            return {}, {}
        end
        return kind(characters) == "table" and characters or {}, kind(items) == "table" and items or {}
    end

    local function skin_data(name)
        if kind(name) ~= "string" or protected(name) then
            return nil
        end
        local characters, items = registries()
        local data = read(characters, name) or read(items, name)
        return target_name(name, data) and data or nil
    end

    local function owns(_, name)
        if name == nil and kind(_) == "string" then
            name = _
        end
        return skin_data(name) ~= nil
    end

    local function client_owns(_, userid, name)
        if name == nil and kind(userid) == "string" then
            name = userid
        end
        return owns(nil, name)
    end

    local function server_owns(_, name)
        return owns(nil, name)
    end

    local function all_skins(_, filter)
        local names, seen = {}, {}
        local characters, items = registries()
        for _, list in ipairs({characters, items}) do
            for name, data in pairs(list) do
                if target_name(name, data) and not seen[name] then
                    if kind(filter) ~= "function" or filter(name, false) then
                        names[#names + 1] = name
                        seen[name] = true
                    end
                end
            end
        end
        G.table.sort(names)
        return names
    end

    local function offline_data()
        return {
            id = "myxl_local_skins",
            items = all_skins(),
            temps = {},
            gameTime = 0,
            jiFen = 0,
        }
    end

    local function offline_api(_, callback, _, error_callback)
        local fn = kind(callback) == "function" and callback or error_callback
        if kind(fn) == "function" then
            fn(2001, "local skins", offline_data())
        end
        return true
    end

    local function query_reply(callback)
        if kind(callback) == "function" then
            local json = read(G, "json")
            local body
            if kind(json) == "table" and kind(json.encode) == "function" then
                body = json.encode({
                    success = true,
                    code = 2001,
                    msg = "local skins",
                    data = offline_data(),
                })
            else
                body = '{"success":true,"code":2001,"data":{"id":"myxl_local_skins","items":[],"temps":{},"gameTime":0,"jiFen":0}}'
            end
            callback(body, true, 200)
        end
        return true
    end

    local sim = read(modenv, "TheSim") or read(G, "TheSim")
    if sim ~= nil then
        local methods = {}
        G.setmetatable(methods, {
            __index = function(t, name)
                local value = sim[name]
                if kind(value) == "function" then
                    value = function(_, ...)
                        return sim[name](sim, ...)
                    end
                end
                write(t, name, value)
                return value
            end,
        })

        methods.QueryServer = function(_, url, callback, ...)
            if is_skin_endpoint(url) then
                return query_reply(callback)
            end
            return sim:QueryServer(url, callback, ...)
        end

        methods.Quit, methods.Shutdown, methods.Reset = noop, noop, noop
        write(modenv, "TheSim", G.setmetatable({}, {__index = methods}))
    end
    local query = read(modenv, "QueryServer") or read(G, "QueryServer")
    write(modenv, "QueryServer", function(url, callback, ...)
        if is_skin_endpoint(url) then
            return query_reply(callback)
        end
        if kind(query) == "function" then
            return query(url, callback, ...)
        end
        if sim ~= nil then
            return sim:QueryServer(url, callback, ...)
        end
    end)
    write(modenv, "DoRestart", function()
        report("target_restart=blocked")
    end)

    local function patch_data(name, data, base)
        if kind(data) ~= "table" then
            return
        end
        if protected(name) then
            data.checkfn, data.checkclientfn = reject, reject
        elseif target_name(name, data, base) then
            data.checkfn, data.checkclientfn = owns, client_owns
            data.is_restricted, data.unlock = false, true
            state.registry[name] = data
        end
    end

    local replacements = {
        AddSkinViolation = reject,
        RunClientSkinIntegrityCheck = noop,
        IsClientSkinStateCompromised = reject,
        ServerPlayerOwnsSkin = server_owns,
        RecheckPlayerSkin = noop,
        SchedulePlayerSkinRecheck = noop,
        SkinApiGet = offline_api,
        _pd5 = noop,
        _pd4 = reject,
    }

    local function protect_callback(fn, depth, seen)
        if
            kind(fn) ~= "function"
            or kind(dbg) ~= "table"
            or kind(dbg.getupvalue) ~= "function"
            or kind(dbg.setupvalue) ~= "function"
        then
            return
        end
        depth, seen = depth or 0, seen or {}
        if seen[fn] or depth > 8 then
            return
        end
        seen[fn] = true
        for index = 1, 80 do
            local name, value = dbg.getupvalue(fn, index)
            if name == nil then
                break
            end
            if replacements[name] ~= nil then
                dbg.setupvalue(fn, index, replacements[name])
            elseif kind(value) == "function" then
                local ok, details = attempt(dbg.getinfo, value, "S")
                local source = ok and details and normalize(details.source or "") or ""
                if source:find("myxl_skins", 1, true) or source:find("myxl_skinplayer", 1, true) then
                    protect_callback(value, depth + 1, seen)
                end
            end
        end
    end

    local function patch_ui()
        local ui = state.ui
        local fn = kind(ui) == "table" and ui.UpdateSkin or nil
        if kind(fn) ~= "function" or kind(dbg) ~= "table" or kind(dbg.getupvalue) ~= "function" then
            return
        end
        for index = 1, 32 do
            local name, list = dbg.getupvalue(fn, index)
            if name == nil then
                break
            end
            if name == "skin_list" and kind(list) == "table" then
                local have = {}
                for _, entry in pairs(list) do
                    if kind(entry) == "table" then
                        have[entry.name] = true
                    end
                end
                for _, name in ipairs(all_skins()) do
                    if not have[name] and not name:find("_tmp$") and name ~= "moyuxuanli_none" then
                        local data = skin_data(name)
                        local character = data.ischaracterskins or data.base_prefab == "moyuxuanli"
                        list[#list + 1] = {
                            name = name,
                            filter = character and "人物" or "物品",
                            isitem = not character,
                            build = data.build_name_override or data.build or name,
                            bank = data.bank,
                            anim = data.anim or "idle",
                        }
                    end
                end
            end
        end
    end

    local function refresh()
        for name, replacement in pairs({
            myxlSkinCheckFn = owns,
            myxlSkinCheckClientFn = client_owns,
            myxlGetAllSkinCheckFn = all_skins,
        }) do
            if kind(read(modenv, name)) == "function" then
                write(modenv, name, replacement)
                write(G, name, replacement)
            end
        end
        for _, name in ipairs({"MakeCharacterSkin", "MakeItemSkin"}) do
            local current = read(modenv, name)
            if kind(current) == "function" and state.constructors[name] ~= current then
                local original = current

                local wrapper = function(base, skin, data, ...)
                    patch_data(skin, data, base)
                    return original(base, skin, data, ...)
                end

                state.constructors[name] = wrapper
                write(modenv, name, wrapper)
            end
        end
        local characters, items = registries()
        for _, list in ipairs({characters, items}) do
            for name, data in pairs(list) do
                patch_data(name, data)
            end
        end
        patch_ui()
    end

    for _, api in ipairs({
        "AddSimPostInit",
        "AddPlayerPostInit",
        "AddPrefabPostInit",
        "AddClassPostConstruct",
        "AddComponentPostInit",
    }) do
        local original = read(modenv, api) or read(G, api)
        if kind(original) == "function" then
            write(modenv, api, function(...)
                local args = pack(...)
                if state.active_import == "myxlmain/myxl_skins" or state.active_import == "myxlmain/myxl_skinplayer" then
                    for index = 1, args.n do
                        if kind(args[index]) == "function" then
                            protect_callback(args[index])
                        end
                    end
                end
                return original(unpack(args, 1, args.n))
            end)
        end
    end
    for _, api in ipairs({"AddModRPCHandler", "AddClientModRPCHandler"}) do
        local original = read(modenv, api) or read(G, api)
        if kind(original) == "function" then
            write(modenv, api, function(namespace, name, fn, ...)
                if namespace == "myxl_skin_security" and (name == "force_quit" or name == "report_integrity") then
                    report("skin_security_rpc=disabled")
                    fn = noop
                elseif state.active_import == "myxlmain/myxl_skins" then
                    protect_callback(fn)
                end
                return original(namespace, name, fn, ...)
            end)
        end
    end
    local userdata_facades = G.setmetatable({}, {__mode = "k"})

    state.after_require = function(name, value)
        name = normalize(name)
        if state.active_import == "" then
            return value
        end
        if name == "widgets/myxl_skinunlockui" then
            state.ui = value
        end
        if
            name == "utils/myxl_userdatahook"
            and state.active_import == "myxlmain/myxl_skins"
            and kind(value) == "table"
            and kind(value.MakeHook) == "function"
        then
            local facade = userdata_facades[value]
            if facade == nil then
                facade = G.setmetatable({}, {__index = value})

                facade.MakeHook = function(object, method, fn, ...)
                    if
                        state.active_import == "myxlmain/myxl_skins"
                        and object == "AnimState"
                        and (method == "SetBuild" or method == "SetSkin" or method == "AddOverrideBuild" or method == "OverrideSkinSymbol" or method == "OverrideSymbol")
                    then
                        fn = reject
                    end
                    return value.MakeHook(object, method, fn, ...)
                end

                userdata_facades[value] = facade
            end
            return facade
        end
        refresh()
        return value
    end

    if kind(original_import) == "function" then
        write(modenv, "modimport", function(path, ...)
            local name = normalize(path)
            if name == "myxlmain/myxl_ban" then
                report("ban_cpu_memory_tasks=disabled")
                return nil
            end
            refresh()
            local previous = state.active_import
            state.active_import = name
            local result = pack(attempt(original_import, path, ...))
            state.active_import = previous
            if not result[1] then
                G.error(result[2], 0)
            end
            refresh()
            if name == "myxlmain/myxl_skin" then
                local original = read(G, "SetSkinnedOvalPortraitTexture")
                if kind(original) == "function" then
                    write(G, "SetSkinnedOvalPortraitTexture", function(widget, character, skin, ...)
                        if
                            character == "moyuxuanli"
                            and (skin == nil or skin == "moyuxuanli_none" or protected(skin))
                            and widget ~= nil
                            and kind(widget.SetTexture) == "function"
                        then
                            widget:SetTexture("bigportraits/moyuxuanli_none.xml", "moyuxuanli_none.tex", "moyuxuanli_none.tex")
                            return true
                        end
                        return original(widget, character, skin, ...)
                    end)
                end
            end
            return unpack(result, 2, result.n)
        end)
    end

    state.finish = function()
        refresh()
        report("version=" .. TARGET_VERSION .. " skins=" .. #all_skins() .. " source_bootstrap=ready")
    end

    refresh()
    report("skinwatch=disabled_before_execution")
    return state.finish
end

if kind(original_require) == "function" then
    write(G, "require", function(name, ...)
        if normalize(name) == "myxlmain/myxl_skinwatch" then
            return function(modenv)
                if is_target_env(modenv) then
                    return install(modenv)
                end
                return original_require(name)(modenv)
            end
        end
        local result = original_require(name, ...)
        for _, state in pairs(states) do
            if state.after_require ~= nil then
                result = state.after_require(name, result)
            end
        end
        return result
    end)
    local known = read(G, "KnownModIndex")
    local manager = read(G, "ModManager")
    if known ~= nil and manager ~= nil then
        local ok, names = attempt(function()
            return known:GetModsToLoad(true)
        end)
        if ok and kind(names) == "table" then
            for _, name in pairs(names) do
                if G.tostring(name):find(TARGET_ID, 1, true) then
                    local found, modenv = attempt(function()
                        return manager:GetMod(name)
                    end)
                    if found and kind(modenv) == "table" then
                        write(modenv, "require", read(G, "require"))
                    end
                end
            end
        end
    end
    G.print("[SKIN_BRIDGE_XUANER] version=" .. TARGET_VERSION .. " source_bootstrap=installed")
end
