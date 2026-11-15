-- HarvestMate Enhanced: Data/Index.lua
-- Runs once every data file is loaded: builds Gatherpedia's item index and
-- checks the bundled spawn data is the shape HME expects (a corrupted or
-- missing file disables only the features that need it).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

ns:BuildIndex()

local problems = {}
if type(ns.NodeSpawns) ~= "table" then problems[#problems + 1] = "NodeSpawns missing" end
if type(ns.SkinningMobs) ~= "table" then problems[#problems + 1] = "SkinningMobs missing" end
for prof, maps in pairs(ns.NodeSpawns or {}) do
    for mapID, list in pairs(maps) do
        for _, e in ipairs(list) do
            if type(e[1]) ~= "string" or type(e[4]) ~= "string" or #e[4] % 4 ~= 0 then
                problems[#problems + 1] = ("bad %s entry on map %s"):format(prof, tostring(mapID))
                break
            end
        end
    end
end
HME.dataProblems = problems
HME.dataReady = #problems == 0
