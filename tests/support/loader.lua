-- Loads HarvestMate Enhanced the way the game does: every file in .toc order
-- with (addon name, shared table), then the load events. Returns the private
-- table. Missing files fail loudly (the .toc and the tree must agree).

ADDON_DIR = ADDON_DIR or "HarvestMateEnhanced"

function TocFiles(dir)
    local list = {}
    for line in io.lines(dir .. "/HarvestMateEnhanced.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            list[#list + 1] = (line:gsub("\\", "/"))
        end
    end
    return list
end

-- What Routes/Pin.xml declares, done here since the tests do not read XML.
local function Xml(path) end

function LoadHME(opts)
    opts = opts or {}
    local ns = {}
    for _, f in ipairs(TocFiles(ADDON_DIR)) do
        if f:match("%.xml$") then
            Xml(f)
        else
            local chunk, err = loadfile(ADDON_DIR .. "/" .. f)
            if not chunk and opts.skipMissing and tostring(err):find("No such file", 1, true) then
                chunk = function() end
            end
            if not chunk then error("could not load " .. f .. ": " .. tostring(err)) end
            local ok, e = pcall(chunk, "HarvestMateEnhanced", ns)
            if not ok then error("error running " .. f .. ": " .. tostring(e)) end
        end
    end
    if not opts.noEvents then
        FireEvent("ADDON_LOADED", "HarvestMateEnhanced")
        FireEvent("PLAYER_LOGIN")
        FireEvent("PLAYER_ENTERING_WORLD", true, false)
        RunTimers(5)
    end
    return ns, ns.HME
end
