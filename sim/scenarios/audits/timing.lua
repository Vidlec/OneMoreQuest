-- /omq timing prints a line for each opening of the map
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30)
for _, questId in ipairs({ 871, 867, 875, 899, 821, 903 }) do
    pcall(accept, questId)
end
wait(2)
slash("/omq timing")
key("M")
wait(2)
expectChat("map open #1")
key("M")
wait(1)
key("M")
wait(2)
expectChat("map open #2")
slash("/omq timing")

for _, line in ipairs(require("sim").chat) do
    if line.text:find("map open") or line.text:find("asked for") then
        io.write("CHAT: ", line.text, "\n")
    end
end
