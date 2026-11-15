-- HarvestMate Enhanced: Data/Leather.lua
-- Starting assumptions for what one successful skin yields, used only until
-- this account has skinned enough of a beast (or of beasts of that level) for
-- its own numbers to take over (Engine/Skinning.lua, Yield). Every value here
-- is labelled "estimate" wherever it is shown.
--
-- The level bands come from Gatherpedia's Skinning data (mobMin / mobMax per
-- leather and hide, classic rules). How much drops per skin is not published
-- for WoW Forever; the figures below are deliberately plain round numbers,
-- not claims, and the UI shows them as such:
--   PRIMARY     leather pieces per skin, split over the bands the level is in
--   HIDE        chance of a hide per skin, split the same way
--   SPECIAL     materials only some beasts give, by name, with a level range
-- Forever-only materials (Pristine Leather, Fel Leather...) are never assumed:
-- they appear only once you have skinned one.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local L = {}
HME.LeatherData = L

L.PRIMARY = 1.25
L.HIDE = 0.03

-- { name pattern (lower case), itemID, per skin, min level, max level }
L.SPECIAL = {
    { "devilsaur", 15417, 0.9, 50, 62 },
    { "chimaera", 15423, 0.6, 45, 62 },
    { "frostsaber", 15422, 0.6, 50, 62 },
    { "bear", 15419, 0.3, 48, 62 },
    { "scorpid", 8154, 0.4, 35, 49 },
    { "scorpid", 15408, 0.4, 50, 62 },
    { "scorpion", 8154, 0.4, 35, 49 },
    { "turtle", 8167, 0.3, 35, 55 },
    { "tortoise", 8167, 0.3, 35, 55 },
    { "whelp", 8165, 0.2, 35, 55 },
    { "dragonkin", 8165, 0.2, 35, 55 },
}

-- Gatherpedia ids of the ordinary leathers and hides (the level bands).
L.LEATHERS = { 2934, 2318, 2319, 4234, 4304, 8170 }
L.HIDES = { 783, 4232, 4235, 8169, 8171 }

L.RESPAWN_SECONDS = 300   -- assumed average respawn of an open-world beast
L.LOOT_SECONDS = 2.5      -- walking to the corpse and looting
L.SKIN_SECONDS = 2.5      -- the skinning cast and its loot window
L.PULL_YARDS = 22         -- you pull from this far, so travel to a mob stops short
L.PULL_SECONDS = 3        -- spotting, targeting and pulling
L.DOWNTIME = 0.12         -- eating, drinking, pet care, repairs: share added to the time
-- 0.4.0: the share of the modelled pace a real session keeps (finding the next
-- target, pathing round terrain, adds, bags, the odd look at chat). Without
-- it the model promised a perfect, uninterrupted circuit: 209 beasts and 175
-- skill-ups an hour at level 41 in Hillsbrad. Your measured sessions replace
-- the whole estimate as they come in (Engine/Learning.lua), this included.
L.PRACTICAL = 0.78
