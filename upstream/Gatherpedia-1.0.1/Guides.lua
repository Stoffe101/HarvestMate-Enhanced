-- Gatherpedia: Guides.lua
-- Leveling-guide data for each gathering profession: brackets, train,
-- gear, what to gather, tips, spots, and rank-up checklists. Spots and
-- checklist rows with coordinates open the world map and drop our own
-- pin through MapLink; spots without coordinates still open the zone.
-- Recorded routes use Gatherpedia's own arrow and map overlay, not a
-- Blizzard user waypoint.

local ADDON_NAME, ns = ...

local Guides = {}
ns.Guides = Guides

local KEYS = { Herbalism = "HerbalismGuide", Mining = "MiningGuide",
               Fishing = "FishingGuide", Skinning = "SkinningGuide" }

local GATHER_LABEL = {
    Fishing = "Catches",
    Herbalism = "Gather",
    Mining = "Mine",
    Skinning = "Skin",
}

function Guides:Data(prof)
    local key = KEYS[prof]
    return key and ns[key] or nil
end

function Guides:Brackets(prof)
    local data = self:Data(prof)
    return (data and data.brackets) or {}
end

function Guides:Intro(prof)
    local data = self:Data(prof)
    return data and data.intro or ""
end

function Guides:GatherLabel(prof)
    return GATHER_LABEL[prof] or "Gather"
end

function Guides:Bracket(prof, key)
    for _, b in ipairs(self:Brackets(prof)) do
        if b.key == key then return b end
    end
end

-- The bracket that covers the player's current skill. Event-style
-- brackets (min 0 and a key like "event") are skipped unless no
-- numbered bracket matches. Unlearned characters get the first one.
function Guides:DefaultKey(prof, skill)
    local brackets = self:Brackets(prof)
    if #brackets == 0 then return nil end
    if not skill or skill < 1 then
        for _, b in ipairs(brackets) do
            if b.key ~= "event" then return b.key end
        end
        return brackets[1].key
    end
    local fallback
    for _, b in ipairs(brackets) do
        if b.key ~= "event" and b.min and b.max and skill >= b.min and skill <= b.max then
            return b.key
        end
        if not fallback and b.key ~= "event" then fallback = b.key end
    end
    return fallback or brackets[1].key
end

-- Title, one-line subtitle, and compact sections for the Guides page.
function Guides:Get(prof, key)
    local b = self:Bracket(prof, key)
    if not b then return nil end
    local sections = {}
    local function add(heading, body)
        body = self:Display(body)
        if body and body ~= "" then
            sections[#sections + 1] = { heading = heading, body = body }
        end
    end
    add("Train", b.train)
    add("Gear", b.gear)
    add(self:GatherLabel(prof), b.catches)
    add("Tips", b.tips)
    return {
        title = b.title or "",
        blurb = b.short or "",
        sections = sections,
        bracket = b,
        train = self:Display(b.train),
        gear = self:Display(b.gear),
        catches = self:Display(b.catches),
        tips = self:Display(b.tips),
    }
end

-- First learned gathering profession, or Herbalism if none yet.
function Guides:DefaultProfession()
    if ns.learnedList and #ns.learnedList > 0 then
        return ns.learnedList[1]
    end
    return "Herbalism"
end

function Guides:PlayerFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Alliance" or f == "Horde" then return f end
    return "Alliance"
end

-- The starting bracket (min skill 1) is the only place Alliance and Horde
-- lists differ. Every later bracket shows the same combined zone list;
-- the faction argument is ignored for spots there.
function Guides:IsStartingBracket(bracket)
    return bracket and tonumber(bracket.min) == 1 or false
end

-- Spots for this character's faction, plus "Both". On non-starting
-- brackets, every listed zone is returned for both factions.
function Guides:Spots(bracket, faction)
    if not bracket or not bracket.spots then return {} end
    faction = faction or self:PlayerFaction()
    local filter = self:IsStartingBracket(bracket)
    local out = {}
    for _, s in ipairs(bracket.spots) do
        -- only = "Horde" / "Alliance" hides a spot from the other side in every range.
        if s.only and s.only ~= faction then
            -- skip
        elseif not filter or not s.faction or s.faction == "Both" or s.faction == faction then
            out[#out + 1] = s
        end
    end
    return out
end

-- Map pin coordinates: a spot's own x,y, the first stop of a route, or
-- the first point of the first cave.
function Guides:PinCoords(spot)
    if not spot then return end
    if type(spot.x) == "number" and type(spot.y) == "number" then
        return spot.x, spot.y
    end
    local pts = self:RoutePoints(spot)
    if pts and pts[1] then return pts[1].x, pts[1].y end
    local loops = self:CaveLoops(spot)
    if loops and loops[1] and loops[1][1] then return loops[1][1].x, loops[1][1].y end
end

function Guides:HasCoords(spot)
    local x, y = self:PinCoords(spot)
    return x ~= nil and y ~= nil
end

-- Ordered stops from spot.route = {{x, y}, ...} (or {x=..., y=...}).
-- Nil unless there are at least two points.
function Guides:RoutePoints(spot)
    if not spot or type(spot.route) ~= "table" then return nil end
    local out = {}
    for _, p in ipairs(spot.route) do
        local x, y
        if type(p) == "table" then
            x, y = tonumber(p.x or p[1]), tonumber(p.y or p[2])
        end
        if x and y then
            out[#out + 1] = { x = x, y = y }
        end
    end
    if #out < 2 then return nil end
    return out
end

-- Cave outlines from spot.caves = { { {x, y}, ... }, ... }. Each outline
-- needs at least three points. Nil when the spot has no caves.
function Guides:CaveLoops(spot)
    if not spot or type(spot.caves) ~= "table" then return nil end
    local loops = {}
    for _, cave in ipairs(spot.caves) do
        local loop = {}
        if type(cave) == "table" then
            for _, p in ipairs(cave) do
                local x, y
                if type(p) == "table" then
                    x, y = tonumber(p.x or p[1]), tonumber(p.y or p[2])
                end
                if x and y then loop[#loop + 1] = { x = x, y = y } end
            end
        end
        if #loop >= 3 then loops[#loops + 1] = loop end
    end
    if #loops == 0 then return nil end
    return loops
end

function Guides:HasRoute(spot)
    return self:RoutePoints(spot) ~= nil or self:CaveLoops(spot) ~= nil
end

function Guides:RouteType(spot)
    if not spot then return "loop" end
    local t = spot.routeType or spot.kind
    if t == "backforth" or t == "back-and-forth" or t == "out-and-back" then
        return "backforth"
    end
    if t == "cave" or (spot.caves and not spot.route) then
        return "cave"
    end
    return "loop"
end

-- The best recorded farm route for this character in a zone.
-- Herbalism, Mining and Skinning only (Fishing has map spots, not routes).
-- When several match, prefer a profession whose current skill sits in that
-- route's bracket; if more than one still fits, use the last-used profession.
function Guides:BestRouteForPlayer(zone, faction)
    if not zone or zone == "" then return nil end
    faction = faction or self:PlayerFaction()
    local candidates = {}
    for _, rec in ipairs(self:RoutesInZone(zone, faction)) do
        if rec.prof and rec.prof ~= "Fishing" and rec.spot then
            candidates[#candidates + 1] = rec
        end
    end
    if #candidates == 0 then return nil end

    local fitting = {}
    for _, rec in ipairs(candidates) do
        local rank = ns.GetPlayerSkill and ns.GetPlayerSkill(rec.prof)
        local b = rec.key and self:Bracket(rec.prof, rec.key)
        if rank and b and b.min and b.max and rank >= b.min and rank <= b.max then
            fitting[#fitting + 1] = rec
        end
    end
    local pool = #fitting > 0 and fitting or candidates

    local last = ns.charDB and ns.charDB.lastRouteProf
    if last then
        for _, rec in ipairs(pool) do
            if rec.prof == last then return rec.spot, rec.prof, rec.key end
        end
    end

    local order = {}
    if ns.learnedList then
        for i, key in ipairs(ns.learnedList) do order[key] = i end
    end
    table.sort(pool, function(a, b)
        local oa, ob = order[a.prof] or 99, order[b.prof] or 99
        if oa ~= ob then return oa < ob end
        if a.prof ~= b.prof then return a.prof < b.prof end
        return (a.key or "") < (b.key or "")
    end)
    local rec = pool[1]
    return rec.spot, rec.prof, rec.key
end

-- Recorded farm routes in a zone for the selected faction.
function Guides:RoutesInZone(zone, faction)
    local out = {}
    if not zone or zone == "" then return out end
    for _, prof in ipairs({ "Herbalism", "Mining", "Fishing", "Skinning" }) do
        for _, b in ipairs(self:Brackets(prof)) do
            for _, s in ipairs(self:Spots(b, faction)) do
                if s.zone == zone and self:HasRoute(s) then
                    out[#out + 1] = { prof = prof, spot = s, key = b.key }
                end
            end
        end
    end
    return out
end

local PROF_SHORT = { Herbalism = "herbs", Mining = "mining", Skinning = "skinning" }
local FARM_PROFS = { "Herbalism", "Mining", "Skinning" }
local NEARBY_LIMIT = 6

-- Compact "Elwynn Forest herbs (1-70)" label so the player can see what will start.
function Guides:SuggestLabel(spot, prof, key)
    if not spot then return nil end
    local zone = spot.zone or ""
    local short = PROF_SHORT[prof] or (prof and string.lower(prof)) or "route"
    local range = key
    if (not range or range == "") and prof then
        for _, b in ipairs(self:Brackets(prof)) do
            for _, s in ipairs(self:Spots(b)) do
                if s == spot then range = b.key; break end
            end
            if range and range ~= "" then break end
        end
    end
    if zone ~= "" and range and range ~= "" then
        return zone .. " " .. short .. " (" .. range .. ")"
    end
    if zone ~= "" then return zone .. " " .. short end
    return short
end

function Guides:RouteName(spot)
    if not spot then return nil end
    return spot.label or spot.zone
end

-- Suggested farm route text for the player's current zone, or nil.
function Guides:SuggestText(zone, faction)
    local spot, prof, key = self:BestRouteForPlayer(zone, faction)
    if not spot then return nil end
    return self:SuggestLabel(spot, prof, key), spot, prof, key
end

function Guides:FarmRoutesInZone(zone, faction)
    local out = {}
    for _, rec in ipairs(self:RoutesInZone(zone, faction)) do
        if rec.prof and rec.prof ~= "Fishing" and rec.spot then
            out[#out + 1] = rec
        end
    end
    return out
end

local function WorldCenter(zone)
    if not zone or not ns.Zones or not ns.Zones.MapID then return end
    if not (C_Map and C_Map.GetWorldPosFromMapPos) then return end
    local mapID = ns.Zones:MapID(zone)
    if not mapID then return end
    local vec
    if CreateVector2D then
        vec = CreateVector2D(0.5, 0.5)
    else
        vec = { x = 0.5, y = 0.5 }
    end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, vec)
    if not ok or not world then return end
    local wx, wy
    if world.GetXY then
        local wok, a, b = pcall(world.GetXY, world)
        if wok then wx, wy = a, b end
    end
    if not wx and world.x then wx, wy = world.x, world.y end
    if wx and wy then return continent, wx, wy end
end

function Guides:ZonesWithFarmRoutes(faction)
    local seen, out = {}, {}
    for _, prof in ipairs(FARM_PROFS) do
        for _, b in ipairs(self:Brackets(prof)) do
            for _, s in ipairs(self:Spots(b, faction)) do
                if s.zone and self:HasRoute(s) and not seen[s.zone] then
                    seen[s.zone] = true
                    out[#out + 1] = s.zone
                end
            end
        end
    end
    return out
end

-- Other zones that have a recorded farm route, closest first (same
-- continent, then world-map distance from the current zone's center).
function Guides:NearbyZonesWithRoutes(zone, faction, limit)
    limit = limit or NEARBY_LIMIT
    local c0, x0, y0 = WorldCenter(zone)
    local rows = {}
    for _, other in ipairs(self:ZonesWithFarmRoutes(faction)) do
        if other ~= zone then
            local c, x, y = WorldCenter(other)
            local same = (c0 ~= nil and c ~= nil and c == c0)
            local dist
            if same and x0 and x then
                local dx, dy = x0 - x, y0 - y
                dist = math.sqrt(dx * dx + dy * dy)
            end
            rows[#rows + 1] = { zone = other, sameCont = same or false, dist = dist }
        end
    end
    table.sort(rows, function(a, b)
        if a.sameCont ~= b.sameCont then return a.sameCont end
        if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
        if a.dist and not b.dist then return true end
        if b.dist and not a.dist then return false end
        return (a.zone or "") < (b.zone or "")
    end)
    local out = {}
    for i = 1, math.min(limit, #rows) do
        out[i] = rows[i].zone
    end
    return out
end

local function GroupByProf(recs)
    local groups, index = {}, {}
    for _, rec in ipairs(recs) do
        local p = rec.prof
        if not index[p] then
            index[p] = { prof = p, recs = {} }
            groups[#groups + 1] = index[p]
        end
        index[p].recs[#index[p].recs + 1] = rec
    end
    local order = {}
    for i, p in ipairs(FARM_PROFS) do order[p] = i end
    table.sort(groups, function(a, b)
        return (order[a.prof] or 99) < (order[b.prof] or 99)
    end)
    return groups
end

local function StopsText(spot)
    local loops = Guides:CaveLoops(spot)
    if loops and not spot.route then
        return (#loops == 1) and "cave" or (#loops .. " caves")
    end
    local pts = Guides:RoutePoints(spot)
    local n = pts and #pts or 0
    if n == 1 then return "1 stop" end
    return n .. " stops"
end

local function PickerRow(rec)
    local label = (rec.spot and (rec.spot.label or rec.spot.zone)) or "Route"
    local parts = { label }
    if rec.key and rec.key ~= "" then parts[#parts + 1] = rec.key end
    parts[#parts + 1] = StopsText(rec.spot)
    return {
        text = table.concat(parts, "  ·  "),
        kind = "button",
        func = function()
            if ns.StartChosenRoute then ns.StartChosenRoute(rec.spot, rec.prof) end
        end,
    }
end

-- Menu items: current-zone routes grouped by profession (skill range and
-- stop count on each row), then the same for nearby zones.
function Guides:RoutePickerItems(zone, faction)
    local items = {}
    if not zone or zone == "" then
        items[#items + 1] = { kind = "info", text = "No route for this zone yet" }
        return items
    end
    local here = self:FarmRoutesInZone(zone, faction)
    if #here == 0 then
        items[#items + 1] = { kind = "info", text = "No route for " .. zone .. " yet" }
    else
        items[#items + 1] = { kind = "title", text = zone }
        for _, g in ipairs(GroupByProf(here)) do
            items[#items + 1] = { kind = "title", text = g.prof }
            for _, rec in ipairs(g.recs) do
                items[#items + 1] = PickerRow(rec)
            end
        end
    end
    local nearby = self:NearbyZonesWithRoutes(zone, faction, NEARBY_LIMIT)
    if #nearby > 0 then
        items[#items + 1] = { kind = "title", text = "Nearby" }
        for _, z in ipairs(nearby) do
            local recs = self:FarmRoutesInZone(z, faction)
            if #recs > 0 then
                items[#items + 1] = { kind = "title", text = z }
                for _, g in ipairs(GroupByProf(recs)) do
                    items[#items + 1] = { kind = "title", text = g.prof }
                    for _, rec in ipairs(g.recs) do
                        items[#items + 1] = PickerRow(rec)
                    end
                end
            end
        end
    end
    return items
end

-- Trainer rows for this skill range and faction (from the rank-up checklist).
function Guides:BracketTrainers(prof, key, faction)
    local seen, out = {}, {}
    for _, g in ipairs(self:RankSteps(prof, key, faction) or {}) do
        for _, r in ipairs(g.rows or {}) do
            local name = r.who
            if name and not seen[name] then
                seen[name] = true
                out[#out + 1] = r
            end
        end
    end
    return out
end

-- First guide page that lists this trainer for the given faction.
function Guides:FindTrainerGuide(name, faction)
    if not name or name == "" then return end
    for _, prof in ipairs({ "Herbalism", "Mining", "Fishing", "Skinning" }) do
        for _, b in ipairs(self:Brackets(prof)) do
            for _, r in ipairs(self:BracketTrainers(prof, b.key, faction)) do
                if r.who == name then
                    return prof, b.key, r
                end
            end
        end
    end
end

function Guides:ZoneFaction(zone)
    if not zone or not ns.Zones or not ns.Zones.FACTION then return "Both" end
    return ns.Zones.FACTION[zone] or "Both"
end

function Guides:IsTrainSpot(spot)
    if not spot then return false end
    if spot.kind == "train" then return true end
    local label = spot.label or ""
    return label:find("%(train%)") and true or false
end

-- Player-facing section text: never leak "-- verify" comments that
-- might have been left in a string.
function Guides:Display(text)
    if not text or text == "" then return "" end
    text = text:gsub("%s*%-%-%s*verify[^\n]*", "")
    return text
end

-- Spots that have a zone but no coordinates, for the missing-coords report.
function Guides:MissingCoords(prof)
    local missing = {}
    for _, b in ipairs(self:Brackets(prof)) do
        for _, s in ipairs(b.spots or {}) do
            if not self:HasCoords(s) then
                missing[#missing + 1] = {
                    bracket = b.key, zone = s.zone, label = s.label, faction = s.faction,
                }
            end
        end
    end
    return missing
end

-- Farm spots (not trainers) that still need a recorded route.
function Guides:MissingRoutes(prof)
    local missing = {}
    for _, b in ipairs(self:Brackets(prof)) do
        for _, s in ipairs(b.spots or {}) do
            if not self:IsTrainSpot(s) and not self:HasRoute(s) then
                missing[#missing + 1] = {
                    bracket = b.key, zone = s.zone, label = s.label, faction = s.faction,
                }
            end
        end
    end
    return missing
end

---------------------------------------------------------------------------
-- Rank-up checklists
---------------------------------------------------------------------------

local RANK_LEVEL = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }

local CAPITALS = {
    Alliance = { "Stormwind City", "Ironforge", "Darnassus" },
    Horde    = { "Orgrimmar", "Thunder Bluff", "Undercity" },
}

local CAPITAL_ORDER = {
    ["Stormwind City"] = 1, Ironforge = 2, Darnassus = 3,
    Orgrimmar = 1, ["Thunder Bluff"] = 2, Undercity = 3,
}

-- Which rank-up belongs on each skill-range page.
local STEPS_FOR = {
    Herbalism = {
        ["1-70"]    = { { rank = "Journeyman", skill = 50 } },
        ["115-170"] = { { rank = "Expert",     skill = 125 } },
        ["170-205"] = { { rank = "Artisan",    skill = 200, level = 35 } },
    },
    Mining = {
        ["1-65"]    = { { rank = "Journeyman", skill = 50 } },
        ["65-125"]  = { { rank = "Expert",     skill = 125 } },
        ["175-245"] = { { rank = "Artisan",    skill = 200, level = 35 } },
    },
    Skinning = {
        ["1-75"]    = { { rank = "Journeyman", skill = 50 } },
        ["75-150"]  = { { rank = "Expert",     skill = 125 } },
        ["150-225"] = { { rank = "Artisan",    skill = 200, level = 35 } },
    },
    Fishing = {
        ["1-75"]    = { { rank = "Journeyman", skill = 50, level = 10 } },
        ["75-150"]  = { { rank = "Expert",     skill = 125, level = 20, special = "heming" } },
        ["225-300"] = { { rank = "Artisan",    skill = 225, level = 35, special = "pagle" } },
    },
}

local function IsCapital(zone, faction)
    for _, z in ipairs(CAPITALS[faction] or {}) do
        if z == zone then return true end
    end
    return false
end

function Guides:CanTeach(entry, rank)
    if not entry or not rank then return false end
    if entry.kind == "vendor" or entry.kind == "quest" then
        return entry.rank == rank
    end
    local have, want = RANK_LEVEL[entry.rank], RANK_LEVEL[rank]
    if not have or not want then return false end
    return have >= want
end

function Guides:ProfessionHasRanks(prof)
    local T = ns.Trainers
    if not T or not T.All then return false end
    for _, e in ipairs(T:All()) do
        if e.prof == prof and e.rank then return true end
    end
    return false
end

-- Capital-city trainers for this faction who can teach `rank`. If our
-- data has no ranks at all, any capital trainer for the profession is
-- listed instead. Neutral and starting-area (Apprentice-only) NPCs are
-- not included; unique book/quest NPCs are handled separately.
function Guides:CapitalTrainers(prof, rank, faction)
    local T = ns.Trainers
    if not T or not T.Filtered then return {} end
    faction = faction or self:PlayerFaction()
    local hasRank = self:ProfessionHasRanks(prof)
    local list = T:Filtered({ prof = prof, faction = faction })
    local out = {}
    for _, e in ipairs(list) do
        if e.kind ~= "vendor" and e.kind ~= "quest"
            and e.faction ~= "Neutral" and IsCapital(e.zone, faction) then
            local ok
            if hasRank then
                ok = self:CanTeach(e, rank)
            else
                ok = true
            end
            if ok then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        local ao, bo = CAPITAL_ORDER[a.zone] or 9, CAPITAL_ORDER[b.zone] or 9
        if ao ~= bo then return ao < bo end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- First matching farm/train spot in this profession's guide. `needles`
-- are lowercase fragments that must appear in the label when given, so
-- a Booty Bay dock is not used as the Savage Coast pin.
function Guides:FindSpot(prof, zone, needles)
    local found
    for _, b in ipairs(self:Brackets(prof)) do
        for _, s in ipairs(b.spots or {}) do
            if s.zone == zone then
                if needles and #needles > 0 then
                    local label = (s.label or ""):lower()
                    local hit = false
                    for i = 1, #needles do
                        if label:find(needles[i], 1, true) then
                            hit = true
                            break
                        end
                    end
                    if hit then return s end
                elseif not found then
                    found = s
                end
            end
        end
    end
    return found
end

local function TrainerRow(e)
    local T = ns.Trainers
    local where = (T and T.WhereText and T:WhereText(e)) or e.zone or ""
    local xy
    if type(e.x) == "number" and type(e.y) == "number" then
        xy = string.format("%.1f, %.1f", e.x, e.y)
        where = where .. " (" .. xy .. ")"
    end
    return {
        who = e.name,
        where = where,
        zone = e.zone,
        x = e.x, y = e.y,
        label = e.name,
        needed = not (type(e.x) == "number" and type(e.y) == "number"),
    }
end

local function SpotRow(spot, title, fallbackZone, fallbackWhere)
    local zone = (spot and spot.zone) or fallbackZone
    local x, y
    if spot then
        x, y = Guides:PinCoords(spot)
    end
    local where
    if spot and spot.label and zone and not (spot.label:find(zone, 1, true)) then
        where = zone .. ", " .. spot.label
    else
        where = (spot and spot.label) or fallbackWhere or zone or ""
    end
    if type(x) == "number" and type(y) == "number" then
        where = where .. string.format(" (%.1f, %.1f)", x, y)
    end
    return {
        title = title,
        where = where,
        zone = zone,
        x = x, y = y,
        label = (spot and spot.label) or title,
        needed = not (type(x) == "number" and type(y) == "number"),
    }
end

local function HemingGroup()
    local T = ns.Trainers
    local e = T and T.Find and T:Find("Old Man Heming")
    local rows
    if e then
        rows = { TrainerRow(e) }
    else
        local s = Guides:FindSpot("Fishing", "Stranglethorn Vale", { "heming", "booty bay" })
        rows = { SpotRow(s, "Old Man Heming", "Stranglethorn Vale", "Booty Bay docks") }
    end
    return {
        heading = "Expert",
        sub = "At skill 125 (character level 20), buy Expert Fishing — The Bass and You from Old Man Heming in Booty Bay.",
        rows = rows,
    }
end

local function PagleGroup()
    local T = ns.Trainers
    local nat = T and T.Find and T:Find("Nat Pagle")
    local natSpot = Guides:FindSpot("Fishing", "Dustwallow Marsh", { "pagle", "island" })
    local talk
    if nat then
        talk = TrainerRow(nat)
        talk.title = "Talk to Nat Pagle in Tidefury Cove, Dustwallow Marsh."
        talk.label = nat.name
    else
        talk = SpotRow(natSpot, "Talk to Nat Pagle in Tidefury Cove, Dustwallow Marsh.",
            "Dustwallow Marsh", "Nat Pagle's island")
    end
    local turn
    if nat then
        turn = TrainerRow(nat)
        turn.title = "Turn the four fish in to Nat Pagle."
        turn.label = nat.name
    else
        turn = SpotRow(natSpot, "Turn the four fish in to Nat Pagle.",
            "Dustwallow Marsh", "Nat Pagle's island")
    end
    local fish = {
        { zone = "Stranglethorn Vale", needles = { "sailfin", "savage coast" },
          title = "Catch Savage Coast Blue Sailfin in Stranglethorn Vale.",
          where = "Savage Coast, Stranglethorn Vale" },
        { zone = "Feralas", needles = { "ahi", "verdantis" },
          title = "Catch Feralas Ahi at the Verdantis River in Feralas.",
          where = "Verdantis River, Feralas" },
        { zone = "Desolace", needles = { "striker", "sar'theris", "sartheris" },
          title = "Catch Sar'theris Striker at Sar'theris Strand in Desolace.",
          where = "Sar'theris Strand, Desolace" },
        { zone = "Swamp of Sorrows", needles = { "misty reed", "mahi" },
          title = "Catch Misty Reed Mahi Mahi at Misty Reed Strand in the Swamp of Sorrows.",
          where = "Misty Reed Strand, Swamp of Sorrows" },
    }
    local rows = { talk }
    for _, f in ipairs(fish) do
        local s = Guides:FindSpot("Fishing", f.zone, f.needles)
        rows[#rows + 1] = SpotRow(s, f.title, f.zone, f.where)
    end
    rows[#rows + 1] = turn
    return {
        heading = "Artisan",
        sub = "At skill 225 (character level 35), take Nat Pagle, Angler Extreme in Tidefury Cove, Dustwallow Marsh. Catch one fish in each of four zones and bring them back.",
        rows = rows,
    }
end

-- Trainers who can teach this rank, nearest first. Journeyman can come
-- from any trainer of the faction (or a neutral one) whose data says it
-- teaches that rank; Expert and Artisan stay with the capital trainers.
function Guides:RankTrainers(prof, rank, faction)
    faction = faction or self:PlayerFaction()
    local list
    if rank == "Journeyman" and self:ProfessionHasRanks(prof) then
        list = {}
        local T = ns.Trainers
        for _, e in ipairs((T and T.Filtered and T:Filtered({ prof = prof, faction = faction })) or {}) do
            if e.kind ~= "vendor" and e.kind ~= "quest" and self:CanTeach(e, rank) then
                list[#list + 1] = e
            end
        end
    else
        list = self:CapitalTrainers(prof, rank, faction)
    end
    local T = ns.Trainers
    local pos = T and T.PlayerPosition and T:PlayerPosition()
    local key = {}
    for i, e in ipairs(list) do
        local tier, yards = 3, math.huge
        if pos and T.Distance then
            local y, sameZone, sameCont = T:Distance(pos, e)
            tier = sameZone and 0 or (sameCont and 1 or 2)
            yards = y or math.huge
        end
        local cap = IsCapital(e.zone, faction) and 0 or 1
        key[e] = { tier, yards, cap, CAPITAL_ORDER[e.zone] or 9, i }
    end
    table.sort(list, function(a, b)
        local ka, kb = key[a], key[b]
        for j = 1, 5 do
            if ka[j] ~= kb[j] then return ka[j] < kb[j] end
        end
        return false
    end)
    return list, pos ~= nil
end

local function TrainerGroup(prof, spec, faction)
    local rows = {}
    local list, located = Guides:RankTrainers(prof, spec.rank, faction)
    for _, e in ipairs(list) do
        rows[#rows + 1] = TrainerRow(e)
    end
    local sub
    if spec.level then
        sub = string.format("Train at skill %d (character level %d).", spec.skill, spec.level)
    else
        sub = string.format("Train at skill %d.", spec.skill)
    end
    return {
        heading = spec.rank,
        sub = sub,
        rows = rows,
        collapsible = true,   -- the page shows the nearest one; the rest on request
        located = located,
    }
end

-- Numbered rank-up groups for this profession, skill range, and faction.
-- Empty when the bracket has no rank-up (for example 225-300 after Artisan,
-- or the weekly fishing contest).
function Guides:RankSteps(prof, key, faction)
    local list = STEPS_FOR[prof] and STEPS_FOR[prof][key]
    if not list then return {} end
    faction = faction or self:PlayerFaction()
    local groups = {}
    for _, spec in ipairs(list) do
        local g
        if spec.special == "heming" then
            g = HemingGroup()
        elseif spec.special == "pagle" then
            g = PagleGroup()
        else
            g = TrainerGroup(prof, spec, faction)
        end
        if g then groups[#groups + 1] = g end
    end
    return groups
end

-- Rows in the checklists that still have no coordinates, for the pin report.
function Guides:MissingStepPins(prof)
    local missing = {}
    for _, faction in ipairs({ "Alliance", "Horde" }) do
        for _, b in ipairs(self:Brackets(prof)) do
            for _, g in ipairs(self:RankSteps(prof, b.key, faction)) do
                for i, row in ipairs(g.rows or {}) do
                    if row.needed then
                        missing[#missing + 1] = {
                            faction = faction,
                            bracket = b.key,
                            heading = g.heading,
                            step = i,
                            title = row.title or row.who,
                            zone = row.zone,
                        }
                    end
                end
            end
        end
    end
    return missing
end

-- The rank-up that falls in this range, for the skill track labels.
-- Returns rank name and skill, or nil.
function Guides:RankMilestone(prof, key)
    local list = STEPS_FOR[prof] and STEPS_FOR[prof][key]
    if list and list[1] then return list[1].rank, list[1].skill end
end
