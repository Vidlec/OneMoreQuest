-- Tests: the Spoilers settings: the presets' cards and the nine kinds by hand, read from and set in Spoilers.

local function findSpoilersSection(ns)
    for index, section in ipairs(ns.SettingsPage.SECTIONS) do
        if section.title == "Spoilers" then
            return section, index
        end
    end
end

---The canvas buttons of the page drawn last, by what a click on each carries.
local function findPageButton(ns, isWanted)
    for _, button in ipairs(ns.LogState.detail.pools.buttons) do
        local data = rawget(button, "data")
        if rawget(button, "handleClick") and data ~= nil and isWanted(data) then
            return button
        end
    end
end

test("the Spoilers settings: near the top, the presets' cards, then a row for each kind with its choices", function()
    local ns = createAddon()
    ns.Spoilers.create()
    local section, index = findSpoilersSection(ns)
    expectEqual(section ~= nil, true, "a Spoilers section")
    expectEqual(index, 2, "right after At a glance")
    local options = ns.SettingsPage.getOptions(section)
    expectEqual(options[1].isSpoilerPresets, true, "the presets first")
    expectEqual(#options, 1 + #ns.Spoilers.CATEGORIES, "and one row a kind")
    for row, category in ipairs(ns.Spoilers.CATEGORIES) do
        local option = options[row + 1]
        expectEqual(option.spoilerCategory, category.key, "in the order Spoilers gives them")
        expectEqual(option.choiceKey, nil, "no saved setting of its own: Spoilers keeps it, per character")
        expectEqual(#option.choices, #category.choices, "every choice of " .. category.key)
        for choiceIndex, choice in ipairs(option.choices) do
            expectEqual(choice.value, category.choices[choiceIndex], "its value")
            expectEqual(type(choice.label), "string", "and words for it: " .. category.key .. " " .. choice.value)
        end
        expectEqual(option.getValue(), ns.Spoilers.getChoice(category.key), "reads the choice")
        expectEqual(ns.SettingsPage.isAvailable(option), true, "always to be changed")
    end
    for _, preset in ipairs(ns.Spoilers.PRESET_ORDER) do
        expectEqual(type(ns.SettingsPage.SPOILER_PRESET_NOTES[preset]), "string", "what " .. preset .. " shows")
    end
    -- A row's choice sets the kind by hand: the preset becomes Custom; set back, the preset again
    local objectives = options[3]
    objectives.setValue("rough")
    expectEqual(ns.Spoilers.getChoice("objectives"), "rough", "the kind set")
    expectEqual(objectives.getValue(), "rough", "and read back")
    expectEqual(ns.Spoilers.getPreset(), "custom", "changed by hand")
    objectives.setValue("exact")
    expectEqual(ns.Spoilers.getPreset(), "guide", "set back: the preset again")
end)

test("the Spoilers page draws its cards and buttons, and a click on either sets the spoilers", function()
    local ns, state = createAddon()
    ns.Spoilers.create()
    setQuest(state, 301, false, { killObjective(5, 12) })
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    local _, index = findSpoilersSection(ns)
    for _, language in ipairs({ "en", "cs" }) do
        ns.settings.language = language
        ns.Log.openSettings(index)
        ns.Log.refresh()
    end
    ns.settings.language = "en"
    ns.Log.refresh()
    local card = findPageButton(ns, function(data) return data == "explorer" end)
    expectEqual(card ~= nil, true, "Explorer's card takes a click")
    card.handleClick(card.data)
    expectEqual(ns.Spoilers.getPreset(), "explorer", "the card picks the preset")
    -- Each kind's buttons (or its dropdown, where the words do not fit a row of buttons)
    local hidden = findPageButton(ns, function(data)
        return type(data) == "table" and data.option and data.option.spoilerCategory == "rewards" and data.value == "hidden"
    end)
    expectEqual(hidden ~= nil, true, "Rewards and numbers: Hidden takes a click")
    hidden.handleClick(hidden.data)
    expectEqual(ns.Spoilers.getChoice("rewards"), "hidden", "the button sets the kind")
    expectEqual(ns.Spoilers.getPreset(), "custom", "and the cards say Custom")
    ns.Log.refresh()
    expectEqual(findPageButton(ns, function(data) return data == "custom" end), nil, "no card for Custom: it is said under them")
end)
