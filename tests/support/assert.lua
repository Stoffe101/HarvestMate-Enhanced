-- Tiny test helpers shared by every tests/test_*.lua file.

local passed, current = 0, "?"

function STEP(name)
    current = name
    REAL_PRINT("STEP " .. name)
end

function check(cond, msg)
    if not cond then error(("%s: %s"):format(current, tostring(msg)), 2) end
    passed = passed + 1
end

function eq(a, b, msg)
    if a ~= b then error(("%s: %s (got %s, wanted %s)"):format(current, msg or "", tostring(a), tostring(b)), 2) end
    passed = passed + 1
end

function near(a, b, tol, msg)
    if type(a) ~= "number" or math.abs(a - b) > tol then
        error(("%s: %s (got %s, wanted %s +- %s)"):format(current, msg or "", tostring(a), tostring(b), tostring(tol)), 2)
    end
    passed = passed + 1
end

function raises(fn, msg)
    local ok = pcall(fn)
    if ok then error(current .. ": expected an error: " .. tostring(msg), 2) end
    passed = passed + 1
end

function Passed() return passed end

-- Finds a printed chat line containing text (since the last ClearLog).
function Said(text)
    for _, l in ipairs(LOG) do if l:find(text, 1, true) then return l end end
    return nil
end
function ClearLog() for i = #LOG, 1, -1 do LOG[i] = nil end end
