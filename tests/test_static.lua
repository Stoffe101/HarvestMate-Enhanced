-- Static checks: every file in the .toc exists and compiles under Lua 5.1;
-- vendored upstream files are identical to the originals except for the
-- declared patches (UPSTREAM.md); HME's own files create no accidental
-- globals while loading; the .toc's saved variables and frame names don't
-- collide with the replaced addons.

local function Read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

STEP("every .toc file exists and compiles")
for _, f in ipairs(TocFiles(ADDON_DIR)) do
    if f:match("%.lua$") then
        local chunk, err = loadfile(ADDON_DIR .. "/" .. f)
        check(chunk, f .. ": " .. tostring(err))
    else
        check(Read(ADDON_DIR .. "/" .. f), f .. " exists")
    end
end

STEP("vendored files match upstream, except declared patches")
local UP_GP = "upstream/Gatherpedia-1.0.1/"
for _, name in ipairs({ "Herbalism", "Mining", "Fishing", "Skinning", "HerbalismGuide", "MiningGuide", "FishingGuide",
    "SkinningGuide", "SkinningMobs", "NodeSpawns" }) do
    eq(Read(ADDON_DIR .. "/Data/Gatherpedia/" .. name .. ".lua"), Read(UP_GP .. "Data/" .. name .. ".lua"), name .. " unchanged")
end
for _, name in ipairs({ "Zones", "Trainers", "Guides" }) do
    eq(Read(ADDON_DIR .. "/Data/Gatherpedia/" .. name .. ".lua"), Read(UP_GP .. name .. ".lua"), name .. " unchanged")
end
local P1 = "local _, ns = ... local HG = ns.HG -- HME patch P1"
local UP_HM = "upstream/HarvestMate-2.0.13/"
for _, name in ipairs({ "Data", "Skill", "Resolve", "Prices", "Profit", "Extras", "Tooltip", "Learn", "Announce", "Stats",
    "Toast", "Gear", "Tracking", "Banner", "Bind", "Nearby" }) do
    local mine = Read(ADDON_DIR .. "/Gather/" .. name .. ".lua")
    local orig = Read(UP_HM .. name .. ".lua")
    orig = orig:gsub("^local _, HG = %.%.%.", P1)
    if name == "Bind" then   -- P3
        orig = orig:gsub('CreateFrame%("Frame", "HarvestMateKeyCapture"', 'CreateFrame("Frame", "HarvestMateEnhancedKeyCapture"')
    end
    eq(mine, orig, name .. ": only the declared patches")
end
local BS = string.char(92, 92)
local sp = Read(UP_GP .. "Sparkles.lua"):gsub("AddOns" .. BS .. "Gatherpedia" .. BS .. "Media" .. BS,
    "AddOns" .. BS .. "HarvestMateEnhanced" .. BS .. "Media" .. BS .. "GP_")
eq(Read(ADDON_DIR .. "/Glimmer/Sparkles.lua"), sp, "Sparkles: only patch P2")
eq(Read(ADDON_DIR .. "/Engine/Optimize.lua"), Read("upstream/GatherPath-1.12.1/Optimize.lua"), "GatherPath's solver unchanged")

STEP("loading creates only the globals HME means to")
local allowed = {
    HarvestMateEnhanced = true, HarvestMateEnhancedRoutePinMixin = true,
    HarvestMateEnhanced_OnCompartmentClick = true, HarvestMateEnhanced_OnCompartmentEnter = true,
    HarvestMateEnhanced_OnCompartmentLeave = true, HarvestMateEnhanced_ToggleWindow = true,
    HarvestMateEnhanced_ToggleRoute = true, HarvestMateEnhanced_CycleTab = true, HarvestMateEnhanced_ToggleSkinLevels = true,
    BINDING_NAME_HARVESTMATEENHANCED_SKINLEVELS = true,
    SLASH_HARVESTMATEENHANCED1 = true, SLASH_HARVESTMATEENHANCED2 = true,
    BINDING_HEADER_HARVESTMATEENHANCED = true, BINDING_NAME_HARVESTMATEENHANCED_TOGGLE = true,
    BINDING_NAME_HARVESTMATEENHANCED_ROUTE = true, BINDING_NAME_HARVESTMATEENHANCED_NEXTTAB = true,
    BINDING_NAME_HARVESTMATEENHANCED_PREVTAB = true,
}
local before = {}
for k in pairs(_G) do before[k] = true end
local ns, HME = LoadHME()
for k in pairs(_G) do
    if not before[k] then
        local named = type(k) == "string" and (k:find("^HarvestMateEnhanced") or k:find("^SLASH_HME"))
        check(allowed[k] or named, "unexpected global: " .. tostring(k))
    end
end

STEP("no collisions with the addons HME replaces")
local toc = Read(ADDON_DIR .. "/HarvestMateEnhanced.toc")
check(toc:find("## SavedVariables: HarvestMateEnhancedDB\n", 1, true), "own account saved variables only")
check(toc:find("## SavedVariablesPerCharacter: HarvestMateEnhancedCharDB\n", 1, true), "own character saved variables only")
for _, old in ipairs({ "HarvestMateDB", "GatherpediaDB", "GatherPathForeverDB" }) do
    check(not toc:find("SavedVariables:[^\n]*" .. old), "does not claim " .. old)
end
check(_G.GatherPathForever == nil and _G.GatherPathForeverPinMixin == nil, "no GatherPath globals")
check(SlashCmdList.GATHERPATHFOREVER == nil and SlashCmdList.HARVESTMATE == nil, "no other addon's command names")

STEP("texture paths keep their doubled backslashes")
for _, f in ipairs(TocFiles(ADDON_DIR)) do
    if f:match("%.lua$") then
        local src = Read(ADDON_DIR .. "/" .. f)
        check(not src:find("Interface\\%a"), f .. ": a texture path with a single backslash")
    end
end

STEP("no `local a, b = x and f()`: and/or keeps only f's first value")
-- Ported from Forever-GPS's static test. It caught /hme diag saying "no
-- position" and every character's class reading as UNKNOWN in the real client.
for _, f in ipairs(TocFiles(ADDON_DIR)) do
    if f:match("%.lua$") then
        local n = 0
        for line in ((Read(ADDON_DIR .. "/" .. f) or "") .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            local rhs = code:match("^%s*local%s+[%w_]+%s*,[%w_%s,]*=%s*(.+)$") or code:match("^%s*[%w_%.]+%s*,[%w_%s,%.]*=%s*(.+)$")
            if rhs then
                local top = rhs:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%b()", "()"):gsub("%b{}", "{}"):gsub("%b[]", "[]")
                local logic = top:find("%f[%w]and%f[%W]") or top:find("%f[%w]or%f[%W]")
                check(top:find(",", 1, true) or not logic, f .. ":" .. n .. ": several values from one and/or: " .. line:gsub("^%s+", ""))
            end
        end
    end
end
