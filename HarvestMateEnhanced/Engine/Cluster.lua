-- HarvestMate Enhanced: Engine/Cluster.lua
-- Grouping points in yards, in linear time with a grid.
--   Cluster.Groups   density clusters (DBSCAN-like): beasts that spawn
--                    together become one hunting area
--   Cluster.Regions  the best compact region of a zone for a weighted set of
--                    sites: where to farm, not the whole zone
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local C = {}
HME.Cluster = C

local floor = math.floor

local function Grid(points, cell)
    local grid = {}
    for i, p in ipairs(points) do
        local k = floor(p[1] / cell) .. ":" .. floor(p[2] / cell)
        local list = grid[k]
        if not list then
            list = {}
            grid[k] = list
        end
        list[#list + 1] = i
    end
    return grid
end

local function Around(grid, cell, p, fn)
    local gx, gy = floor(p[1] / cell), floor(p[2] / cell)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local list = grid[(gx + dx) .. ":" .. (gy + dy)]
            if list then for _, j in ipairs(list) do fn(j) end end
        end
    end
end

-- points: { {x, y, w = weight?}, ... } in yards. eps: neighbour distance.
-- minPts: neighbours (weight) needed to start a cluster.
-- Returns clusters { members = {i...}, cx, cy, radius, weight } sorted by
-- weight, and the noise count.
function C.Groups(points, eps, minPts)
    local n = #points
    local label = {}
    local grid = Grid(points, eps)
    local clusters = {}
    local function neighbours(i)
        local out = {}
        local p = points[i]
        Around(grid, eps, p, function(j)
            local q = points[j]
            if U.Dist(p[1], p[2], q[1], q[2]) <= eps then out[#out + 1] = j end
        end)
        return out
    end
    local function weight(list)
        local w = 0
        for _, j in ipairs(list) do w = w + (points[j].w or 1) end
        return w
    end
    for i = 1, n do
        if not label[i] then
            local nb = neighbours(i)
            if weight(nb) < minPts then
                label[i] = -1
            else
                local c = { members = {} }
                clusters[#clusters + 1] = c
                local id = #clusters
                local queue, head = nb, 1
                label[i] = id
                c.members[#c.members + 1] = i
                while head <= #queue do
                    local j = queue[head]
                    head = head + 1
                    if label[j] == -1 then
                        label[j] = id
                        c.members[#c.members + 1] = j
                    elseif not label[j] then
                        label[j] = id
                        c.members[#c.members + 1] = j
                        local nb2 = neighbours(j)
                        if weight(nb2) >= minPts then
                            for _, k in ipairs(nb2) do
                                if not label[k] or label[k] == -1 then queue[#queue + 1] = k end
                            end
                        end
                    end
                end
            end
        end
        if i % 400 == 0 then HME.Yield() end
    end
    local noise = 0
    for i = 1, n do if label[i] == -1 then noise = noise + 1 end end
    for _, c in ipairs(clusters) do
        local sx, sy, w = 0, 0, 0
        for _, j in ipairs(c.members) do
            local p = points[j]
            local pw = p.w or 1
            sx, sy, w = sx + p[1] * pw, sy + p[2] * pw, w + pw
        end
        c.cx, c.cy, c.weight = sx / w, sy / w, w
        local r = 0
        for _, j in ipairs(c.members) do
            local p = points[j]
            local d = U.Dist(p[1], p[2], c.cx, c.cy)
            if d > r then r = d end
        end
        c.radius = r
    end
    table.sort(clusters, function(a, b) return a.weight > b.weight end)
    return clusters, noise
end

-- Splits a big cluster into pieces about `size` yards across (k-means style
-- seeding on a grid, two refinement passes). For hunting patterns inside a
-- large area. Returns { {cx, cy, members, weight}, ... }.
function C.Split(points, members, size)
    local cells = {}
    for _, j in ipairs(members) do
        local p = points[j]
        local k = floor(p[1] / size) .. ":" .. floor(p[2] / size)
        local c = cells[k]
        if not c then
            c = { members = {}, sx = 0, sy = 0, w = 0 }
            cells[k] = c
        end
        local w = p.w or 1
        c.members[#c.members + 1] = j
        c.sx, c.sy, c.w = c.sx + p[1] * w, c.sy + p[2] * w, c.w + w
    end
    local out = {}
    for _, c in pairs(cells) do
        out[#out + 1] = { cx = c.sx / c.w, cy = c.sy / c.w, members = c.members, weight = c.w }
    end
    -- Two Lloyd passes so the pieces sit on their points, not on the grid.
    for _ = 1, 2 do
        local acc = {}
        for i = 1, #out do acc[i] = { members = {}, sx = 0, sy = 0, w = 0 } end
        for _, j in ipairs(members) do
            local p = points[j]
            local best, bd = 1, math.huge
            for i, c in ipairs(out) do
                local d = U.Dist(p[1], p[2], c.cx, c.cy)
                if d < bd then best, bd = i, d end
            end
            local a = acc[best]
            local w = p.w or 1
            a.members[#a.members + 1] = j
            a.sx, a.sy, a.w = a.sx + p[1] * w, a.sy + p[2] * w, a.w + w
        end
        local next_ = {}
        for _, a in ipairs(acc) do
            if a.w > 0 then next_[#next_ + 1] = { cx = a.sx / a.w, cy = a.sy / a.w, members = a.members, weight = a.w } end
        end
        out = next_
    end
    table.sort(out, function(a, b) return a.weight > b.weight end)
    return out
end

-- The best region for weighted sites: grid cells of `cell` yards scored by
-- weight; the best cell grows into neighbouring cells while they hold at
-- least `keep` (0-1) of the best cell's weight, up to `maxCells`.
-- sites: { {x, y, w}, ... } in yards. Returns { cells = n, weight, members =
-- {i...}, cx, cy } or nil.
function C.Region(sites, cell, keep, maxCells)
    local cells = {}
    for i, s in ipairs(sites) do
        if (s.w or 1) > 0 then
            local gx, gy = floor(s[1] / cell), floor(s[2] / cell)
            local k = gx .. ":" .. gy
            local c = cells[k]
            if not c then
                c = { gx = gx, gy = gy, w = 0, members = {} }
                cells[k] = c
            end
            c.w = c.w + (s.w or 1)
            c.members[#c.members + 1] = i
        end
    end
    -- Smooth: a cell's score counts half of its neighbours, so a dense area
    -- beats one lucky cell.
    local best, bestScore
    for _, c in pairs(cells) do
        local score = c.w
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    local nb = cells[(c.gx + dx) .. ":" .. (c.gy + dy)]
                    if nb then score = score + nb.w * 0.5 end
                end
            end
        end
        c.score = score
        if not bestScore or score > bestScore then best, bestScore = c, score end
    end
    if not best then return nil end
    local taken = { [best.gx .. ":" .. best.gy] = best }
    local region = { best }
    local floorW = best.w * (keep or 0.35)
    while #region < (maxCells or 6) do
        local pick, pickW
        for _, c in ipairs(region) do
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local k = (c.gx + dx) .. ":" .. (c.gy + dy)
                    local nb = cells[k]
                    if nb and not taken[k] and nb.w >= floorW and (not pickW or nb.w > pickW) then pick, pickW = nb, nb.w end
                end
            end
        end
        if not pick then break end
        taken[pick.gx .. ":" .. pick.gy] = pick
        region[#region + 1] = pick
    end
    local out = { cells = #region, weight = 0, members = {} }
    local sx, sy = 0, 0
    for _, c in ipairs(region) do
        out.weight = out.weight + c.w
        for _, i in ipairs(c.members) do
            out.members[#out.members + 1] = i
            local s = sites[i]
            sx, sy = sx + s[1] * (s.w or 1), sy + s[2] * (s.w or 1)
        end
    end
    out.cx, out.cy = sx / out.weight, sy / out.weight
    return out
end
