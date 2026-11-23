local _, ns = ...

-- The addon's own words in the player's language. The game has no Czech client, so the language is a setting of
-- the addon's own (ns.settings.language), English by default. Names from the game (quests, zones, NPCs, items)
-- stay as the game gives them.
--
-- A phrase is looked up by its English text, as written in the code: ns.L("Turn in to %s", name). Without a
-- translation the English shows, so a phrase not translated yet is never lost. Phrases are translated where they
-- are shown, not where they are written, so switching the language takes effect at the next drawing.
--
-- Counts: English has two forms and Czech three (1, 2 to 4, 5 and more), so a phrase with a count goes through
-- ns.Lp(count, "%d quest", "%d quests"); its Czech is a list of the three forms, kept under the English one.
local Locale = {
    -- Each language named in itself, as a player looking for theirs reads it
    LANGUAGES = {
        { value = "en", label = "English", note = "OneMoreQuest in English." },
        { value = "cs", label = "Čeština", note = "OneMoreQuest česky, slovy hráčů: questy, dropy, loot." },
    },
    tables = { cs = {} }, -- [language] = { [English] = translation, or { one, few, many } for counts }
    missing = {}, -- [English] = true: phrases shown in a language that has no translation for them (this session)
}
ns.Locale = Locale

---@return string language The language the addon speaks: "en" or "cs"
function Locale.getLanguage()
    return ns.settings and ns.settings.language or "en"
end

---Adds translations, from a Locales file: Locale.add("cs", { ["English"] = "Česky", ... }).
function Locale.add(language, phrases)
    local target = Locale.tables[language]
    for english, translation in pairs(phrases) do
        target[english] = translation
    end
end

---@return string|table? translation The phrase in the addon's language, nil in English or when there is none
local function find(english)
    local language = Locale.getLanguage()
    if language == "en" then
        return nil
    end
    local translation = Locale.tables[language] and Locale.tables[language][english]
    if translation == nil then
        Locale.missing[english] = true
    end
    return translation
end

---@return string text A phrase in the addon's language, filled in with the values given (as string.format)
function ns.L(english, ...)
    local translation = find(english)
    local text = type(translation) == "string" and translation or english
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

---@return number form Which Czech form a count takes: 1 for one, 2 for two to four, 3 for none and five or more
local function getCzechForm(count)
    count = math.abs(math.floor(count))
    if count == 1 then
        return 1
    elseif count >= 2 and count <= 4 then
        return 2
    end
    return 3
end

---A phrase with a count, in the form its count takes: ns.Lp(3, "%d quest", "%d quests") is "3 quests", in Czech
---"3 questy". Further values fill in after the count.
---@return string text
function ns.Lp(count, one, other, ...)
    local translation = find(one)
    local text
    if type(translation) == "table" then
        text = translation[getCzechForm(count)] or translation[#translation]
    else
        text = count == 1 and one or other
    end
    return string.format(text, count, ...)
end

-- The language everything was last told of: the one the settings were loaded with, then each one switched to. A
-- language set some other way (the settings' dropdown writes the setting, then asks for a redraw) is told at the next
-- redraw of everything at the latest: the first switch of a session was once never told, so the fonts, the
-- translation addons and the lists stayed in the old one.
local toldLanguage

---The settings were loaded: their language is the one everything starts in, nothing to tell.
function Locale.noteLoaded()
    toldLanguage = Locale.getLanguage()
end

---Switches the language and draws everything again in it.
function Locale.setLanguage(language)
    ns.settings.language = language
    toldLanguage = language
    -- Each part that speaks or draws in the language acts on it (the fonts, the translation addons, the lists that
    -- hold their reasons in words, the game's settings panel), then everything is drawn again
    ns.emit("LANGUAGE_CHANGED")
    ns.queueRefresh()
end

---Tells everything of a language set without Locale.setLanguage, if there is one.
---@return boolean isTold The language had changed and was told
function Locale.applyLanguage()
    local language = Locale.getLanguage()
    if toldLanguage == nil then
        toldLanguage = language -- (settings never loaded: nothing was told of any other)
        return false
    end
    if language == toldLanguage then
        return false
    end
    Locale.setLanguage(language)
    return true
end

-- Before every redraw of everything, ahead of the modules that draw (this file loads second): a language changed by
-- any way is told before anything is drawn in it
ns.registerModule({ name = "Locale", invalidate = function() Locale.applyLanguage() end })
