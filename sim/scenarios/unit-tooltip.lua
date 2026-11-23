-- A creature's tooltip says what it gives towards your quests: hovering a Plainstrider names Plainstrider
-- Menace with its beaks, their count and drop chance; a kill quest's creature its kills; a creature worth
-- nothing to your quests adds nothing. The same on the target's tooltip. Off in the settings, and when the game
-- keeps creatures' identities secret, nothing is added and nothing breaks.
setProfile({ level = 14, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844) -- Plainstrider Menace: Plainstrider Beaks
accept(871) -- Disrupt the Attacks: kills
wait(1)
local addon = require("addons").byName["onemorequest"].private
local D = G.LibQuestieDB
local killNpcId = D.Quest.Get(871, "objectives")[1][1][1]
local killName = D.Npc.Get(killNpcId, "name")

local function tooltipText()
    local lines = {}
    for index = 1, G.GameTooltip:NumLines() do
        local left = G["GameTooltipTextLeft" .. index]
        local right = G["GameTooltipTextRight" .. index]
        lines[#lines + 1] = (left and left:GetText() or "") .. " | " .. (right and right:IsShown() and right:GetText() or "")
    end
    return table.concat(lines, "\n")
end

hoverCreature(3244) -- a Plainstrider
wait(0.1)
local text = tooltipText()
print(text)
expect(text:find("Plainstrider Menace", 1, true), "hovering a Plainstrider names the quest it helps")
expect(text:find("Plainstrider Beak", 1, true) and text:find("%d+/%d+") and text:find("%d+%%"), "with the beaks, their count and the drop chance")

hoverCreature(killNpcId)
wait(0.1)
text = tooltipText()
expect(text:find("Disrupt the Attacks", 1, true) and text:find(killName, 1, true), "a kill quest's creature shows the kills it counts for")

hoverCreature(3255) -- a Sunscale Screecher: nothing for these quests
wait(0.1)
expect(not tooltipText():find("Plainstrider Menace", 1, true) and not tooltipText():find("Disrupt", 1, true), "a creature worth nothing to your quests adds nothing")

targetCreature(3244)
G.GameTooltip:SetOwner(G.UIParent, "ANCHOR_CURSOR")
G.GameTooltip:SetUnit("target") -- hovering the target's portrait
wait(0.1)
expect(tooltipText():find("Plainstrider Menace", 1, true), "the target's tooltip says the same")

addon.settings.shouldShowUnitQuests = false
hoverCreature(3244)
wait(0.1)
expect(not tooltipText():find("Plainstrider Menace", 1, true), "switched off in the settings, nothing is added")
addon.settings.shouldShowUnitQuests = true

restrict({ identity = true })
hoverCreature(3244)
wait(0.1)
expect(not tooltipText():find("Plainstrider Menace", 1, true), "with creatures' identities kept secret, nothing is added")
restrict({ identity = false })

-- The game can run the post-call twice for one tooltip: the lines go in once
hoverCreature(3244)
local data = { type = 2, guid = G.UnitGUID("mouseover") }
for _, handler in ipairs(require("ui").tooltipPostCalls[2] or {}) do handler(G.GameTooltip, data) end
local _, count = tooltipText():gsub("Plainstrider Menace", "")
expect(count == 1, "run again for the same tooltip, the quest is listed once (" .. count .. ")")

-- Questie running with its own quest lines on tooltips: ours step aside rather than repeat them
local isLoaded = G.C_AddOns.IsAddOnLoaded
G.C_AddOns.IsAddOnLoaded = function(name) return name == "Questie" or isLoaded(name) end
G.Questie = { db = { profile = { enableTooltips = true } } }
hoverCreature(3244)
expect(not tooltipText():find("Plainstrider Menace", 1, true), "with Questie's tooltips on, OneMoreQuest adds nothing")
G.Questie.db.profile.enableTooltips = false
hoverCreature(3244)
expect(tooltipText():find("Plainstrider Menace", 1, true), "with them switched off in Questie, OneMoreQuest's lines are back")
G.C_AddOns.IsAddOnLoaded, G.Questie = isLoaded, nil
