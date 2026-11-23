-- /omq cpu prints what the game's profiler measures (the simulator may not have it: then it says so)
slash("/omq cpu")
for _, line in ipairs(require("sim").chat) do
    if line.text:find("CPU") or line.text:find("ms/frame") or line.text:find("C_AddOnProfiler") then
        io.write("CHAT: ", line.text, "\n")
    end
end
