-- Benchmarks (tools/bench.lua); asserts only generous upper bounds.
dofile("tools/bench.lua")
for k, v in pairs(BENCH) do check(v < 20000, k .. " took " .. v .. " ms") end
