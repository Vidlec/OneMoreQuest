local _, ns = ...

-- Quest texts (titles, objectives, stories) in the player's language, from a translation addon they have
-- installed: the game has no Czech client, so the game's quest texts are English and only such an addon knows
-- them in Czech. Each addon OneMoreQuest can read is a provider, in its own file under Translators\, registered
-- with QuestText.register. At login every provider whose addon is loaded is started; each text then comes
-- from the first of them that translates at that moment (an addon loaded but switched off in its own settings
-- passes to the next one). With none, every text stays as the game and the database give it.
--
-- A provider is for one language: it is used only while OneMoreQuest speaks that language (Locale.getLanguage),
-- so a Czech one never puts Czech in an English OneMoreQuest. It may offer quest texts, a narration (voice), or
-- both: one with a narration only (an English voice pack, say) leaves the texts to the others.
--
-- What is asked for is shown only: the quests' English titles and objectives stay in the quest records for
-- everything that compares, matches or saves them (the database's names, chat links, the chronicle's saved data).
--
---@class QuestTextProvider
---@field name string The addon's folder name: "AzerothCesky"
---@field label string The addon's name as players know it: "Azeroth česky"
---@field language string The language it gives, as OneMoreQuest's setting names it: "cs", "en"
---@field about string What it brings to OneMoreQuest, in English (translated where shown), for the About page
---@field detect fun(): boolean The addon is loaded and offers what OneMoreQuest reads
---@field start (fun(onChange: fun()))? Starts listening; onChange when the addon's settings or readiness change
---@field isOn (fun(): boolean)? The addon translates now (turned on, ready, its quest texts not switched off);
---only with getTitle
---@field getTitle (fun(questId: number, english: string, isInLog: boolean): string?)? Without it, no quest texts
---@field getObjective fun(questId: number, text: string, fulfilled: number, required: number, kind: string?, objectiveCount: number): string?
---The objective's line as the game writes it ("Kraul Guano: 3/12"), translated the same way; kind is the game's
---objective type ("monster", "item"...), objectiveCount how many objectives the quest has
---@field getObjectives fun(questId: number, english: string): string? The quest's "what it asks" text
---@field getDescription (fun(questId: number, english: string): string?)? The quest's story, when the addon has it
---@field voice QuestVoice? The addon's quest narration, when it has one
---@field getSettingsKey (fun(): string)? For an addon that announces no changes: its settings in a word, read
---on every question, so a change of them is noticed at once

---@class QuestVoice A translation addon's narration of quests, played by the addon itself (its queue, its player)
---@field isOn fun(): boolean Its narration is turned on
---@field start fun(onChange: fun()) Starts listening; onChange when something starts, stops or joins the queue
---@field hasRecording fun(questId: number): boolean
---@field getState fun(questId: number): string, number? "idle", "playing", "paused" or "queued" and its place
---@field play fun(questId: number) Plays it now, interrupting what plays; the queue waits
---@field queue fun(questId: number) Adds it to the end of the queue
---@field stop fun(questId: number) Stops it, or takes it off the queue

local MAX_CACHED = 4000 -- answers kept: a quest's title and its objectives' lines; more starts over

local QuestText = {
    providers = {}, ---@type QuestTextProvider[]
    started = {}, ---@type QuestTextProvider[] Those whose addon is loaded, in the order registered
    active = nil, ---@type QuestTextProvider? The one whose answers are kept now
    cache = {}, -- [field:questId:what was asked] = the translation, or false for none
    cachedCount = 0,
    settingsKeys = {}, -- [provider] = its settings when its answers were kept
}
ns.QuestText = QuestText

---@param provider QuestTextProvider
function QuestText.register(provider)
    QuestText.providers[#QuestText.providers + 1] = provider
end

---Forgets every answer and draws again: the addon's settings changed, so its answers may have.
function QuestText.handleChange()
    QuestText.cache, QuestText.cachedCount = {}, 0
    -- What holds quest titles worked out (the Available lists) works them out again; then everything is drawn again
    ns.emit("QUEST_TEXT_CHANGED")
    if ns.queueRefresh then
        ns.queueRefresh()
    end
end

---@return boolean isForLanguage The provider gives the language OneMoreQuest speaks now
function QuestText.isForLanguage(provider)
    return provider.language == (ns.Locale and ns.Locale.getLanguage() or "en")
end

---Starts over when the provider's settings changed since its answers were kept (for one that does not say).
local function checkSettings(provider)
    if not provider.getSettingsKey then
        return
    end
    local isFine, settingsKey = pcall(provider.getSettingsKey)
    local known = QuestText.settingsKeys[provider]
    if isFine and settingsKey ~= known then
        QuestText.settingsKeys[provider] = settingsKey
        if known ~= nil then
            QuestText.handleChange()
        end
    end
end

---Starts every provider whose addon is loaded, once every addon has loaded. One that fails to start is passed over.
function QuestText.start()
    QuestText.started = {}
    for _, provider in ipairs(QuestText.providers) do
        local isFound, isDetected = pcall(provider.detect)
        if isFound and isDetected and (not provider.start or pcall(provider.start, QuestText.handleChange)) then
            QuestText.started[#QuestText.started + 1] = provider
            checkSettings(provider) -- known from the start, so the first lists drawn are not started over
            if provider.voice then
                -- Something started, stopped or joined the queue: the buttons show it at the next drawing
                pcall(provider.voice.start, function()
                    if ns.queueRefresh then
                        ns.queueRefresh()
                    end
                end)
            end
        end
    end
    QuestText.active = QuestText.getActive()
    QuestText.handleChange()
end

---@return QuestTextProvider? provider The provider that translates now: the first started one that is on; nil when
---quest texts stay English
function QuestText.getActive()
    for _, provider in ipairs(QuestText.started) do
        local isFine, isOn = false, false
        if provider.getTitle and provider.isOn and QuestText.isForLanguage(provider) then
            isFine, isOn = pcall(provider.isOn)
        end
        if isFine and isOn then
            return provider
        end
    end
    return nil
end

---@return string? translation An answer of the provider, kept until its settings change; nil when it has none
local function ask(key, method, ...)
    for _, started in ipairs(QuestText.started) do
        checkSettings(started) -- an addon that announces nothing: its switch is noticed here
    end
    local provider = QuestText.getActive()
    if provider ~= QuestText.active then
        -- Another addon translates now (one switched off or on): the answers kept were the other's
        QuestText.active = provider
        QuestText.handleChange()
    end
    if not provider or not provider[method] then
        return nil
    end
    local known = QuestText.cache[key]
    if known == nil then
        local isFine, answer = pcall(provider[method], ...)
        known = isFine and type(answer) == "string" and answer ~= "" and answer or false
        if QuestText.cachedCount >= MAX_CACHED then
            QuestText.cache, QuestText.cachedCount = {}, 0
        end
        QuestText.cache[key], QuestText.cachedCount = known, QuestText.cachedCount + 1
    end
    return known or nil
end

---@param isInLog boolean? The quest is in the player's log (the addon may read it from the game then)
---@return string title The quest's title in the player's language, else the English one given
function QuestText.getTitle(questId, english, isInLog)
    if type(english) ~= "string" or not questId then
        return english
    end
    -- (whether it is in the log is part of the asking: the addon may read a quest in the log from the game, so one
    -- asked before it was taken may have another answer once it is)
    return ask(
        "title:" .. questId .. (isInLog and ":log:" or ":") .. english,
        "getTitle",
        questId,
        english,
        isInLog == true
    ) or english
end

---@return string? name A quest's name from the database as shown: translated when a translation addon has it
function QuestText.getQuestName(questId)
    local english = ns.Database.getQuestField(questId, "name")
    return english and QuestText.getTitle(questId, english, ns.QuestState.isInLog(questId)) or nil
end

---@param text string? The objective's line as the game writes it: "Kraul Guano: 3/12"
---@param kind string? The game's objective type: "monster", "item", "object", "event"...
---@param objectiveCount number? How many objectives the quest has
---@return string? line The line in the player's language, else the one given
function QuestText.getObjective(questId, text, fulfilled, required, kind, objectiveCount)
    if type(text) ~= "string" or text == "" or not questId then
        return text
    end
    -- (the quest's number set apart from the line: quest 1's "28/30 ..." and quest 12's "8/30 ..." were one key)
    local key = "objective:" .. questId .. ":" .. text .. ":" .. (fulfilled or 0) .. "/" .. (required or 0)
    return ask(key, "getObjective", questId, text, fulfilled or 0, required or 0, kind, objectiveCount or 1) or text
end

---@return string text The quest's "what it asks" text in the player's language, else the English one given
function QuestText.getObjectives(questId, english)
    if type(english) ~= "string" or english == "" or not questId then
        return english
    end
    return ask("objectives:" .. questId .. ":" .. english, "getObjectives", questId, english) or english
end

---@return string? story The quest's story in the player's language, else the English one given
function QuestText.getDescription(questId, english)
    if type(english) ~= "string" or english == "" or not questId then
        return english
    end
    return ask("description:" .. questId .. ":" .. english, "getDescription", questId, english) or english
end

---@return boolean isTranslating Quest texts come from a translation addon now, so they may need Czech letters
function QuestText.isTranslating()
    return QuestText.getActive() ~= nil
end

-- Narration: a translation addon that has recordings of quests plays them in its own player and queue;
-- OneMoreQuest only asks and shows. Chosen apart from the texts: the first started addon whose narration is on.

---@return QuestVoice? voice
---@return QuestTextProvider? provider The addon it belongs to
function QuestText.getVoice()
    for _, provider in ipairs(QuestText.started) do
        local voice = provider.voice
        if voice and QuestText.isForLanguage(provider) then
            local isFine, isOn = pcall(voice.isOn)
            if isFine and isOn then
                return voice, provider
            end
        end
    end
    return nil
end

---@return string? state Nil when the quest has no recording (or no addon narrates); else "idle", "playing",
---"paused" or "queued"
---@return number? position Its place in the queue, when queued
function QuestText.getVoiceState(questId)
    local voice = questId and QuestText.getVoice()
    if not voice then
        return nil
    end
    local isFine, hasRecording = pcall(voice.hasRecording, questId)
    if not (isFine and hasRecording) then
        return nil
    end
    local isRead, state, position = pcall(voice.getState, questId)
    return isRead and state or "idle", isRead and position or nil
end

---The narration button's click: plays the quest now, or stops it while it plays.
---@return boolean isDone
function QuestText.toggleVoice(questId)
    local voice, state = QuestText.getVoice(), QuestText.getVoiceState(questId)
    if not (voice and state) then
        return false
    end
    return pcall(state == "playing" and voice.stop or voice.play, questId) == true
end

---The other click: adds the quest to the end of the queue, or takes it off.
---@return boolean isDone
function QuestText.toggleVoiceQueue(questId)
    local voice, state = QuestText.getVoice(), QuestText.getVoiceState(questId)
    if not (voice and state) then
        return false
    end
    return pcall(state == "queued" and voice.stop or voice.queue, questId) == true
end
---Adds the narration's entries to a quest's right-click menu, when the quest has a recording: play it now (or stop
---it), and add it to the queue (or take it off).
function QuestText.addVoiceMenuItems(root, questId)
    local state = QuestText.getVoiceState(questId)
    if not state then
        return
    end
    root:CreateDivider()
    local isPlaying = state == "playing"
    root:CreateButton(ns.L(isPlaying and "Stop the narration" or "Play the narration"), function()
        QuestText.toggleVoice(questId)
    end)
    if not isPlaying then
        root:CreateButton(
            ns.L(state == "queued" and "Take the narration off the queue" or "Queue the narration"),
            function()
                QuestText.toggleVoiceQueue(questId)
            end
        )
    end
end
-- The narration's mark, in the colours the narrating addon's own buttons use: gold while it plays or waits paused,
-- blue while it waits in the queue
QuestText.VOICE_ICON = "Interface\\Common\\VoiceChat-Speaker"
QuestText.VOICE_COLORS =
    { playing = { 1, 0.82, 0 }, paused = { 0.8, 0.66, 0.2 }, queued = { 0.55, 0.72, 1 }, idle = { 0.7, 0.7, 0.7 } }

---The narration mark's tooltip: where the quest's narration is, and what the clicks do.
function QuestText.showVoiceTooltip(owner, questId)
    local state, position = QuestText.getVoiceState(questId)
    if not state then
        return
    end
    local _, provider = QuestText.getVoice()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L("Narration by %s", provider and provider.label or "?"), 1, 0.82, 0)
    if state == "playing" then
        GameTooltip:AddLine(ns.L("Playing now. Click to stop it; the queue goes on."), 1, 1, 1, true)
    elseif state == "queued" then
        GameTooltip:AddLine(ns.L("Number %d in the queue. Click to play it now.", position or 1), 1, 1, 1, true)
        GameTooltip:AddLine(ns.L("Right-click to take it off the queue"), 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine(ns.L("Click to play it now"), 1, 1, 1, true)
    end
    GameTooltip:Show()
end
---@return string? languageName A language as the About page's choice names it ("Čeština"), nil when unknown
local function getLanguageName(language)
    for _, choice in ipairs(ns.Locale and ns.Locale.LANGUAGES or {}) do
        if choice.value == language then
            return choice.label
        end
    end
    return nil
end

---@return boolean isOn The provider's quest texts or its narration are on in its own settings
local function isProviderOn(provider)
    local isTextOn = false
    if provider.getTitle and provider.isOn then
        local isFine, isOn = pcall(provider.isOn)
        isTextOn = isFine and isOn == true
    end
    local isVoiceOn = false
    if provider.voice then
        local isFine, isOn = pcall(provider.voice.isOn)
        isVoiceOn = isFine and isOn == true
    end
    return isTextOn or isVoiceOn
end

---The translation addons loaded, for the About page: what each brings, and whether it is used now.
---@return { label: string, text: string, isInUse: boolean }[] integrations
function QuestText.getIntegrations()
    local integrations = {}
    for _, provider in ipairs(QuestText.started) do
        local status, isInUse
        if not QuestText.isForLanguage(provider) then
            status = ns.L("Used while OneMoreQuest is in %s.", getLanguageName(provider.language) or provider.language)
        elseif not isProviderOn(provider) then
            status = ns.L("Switched off in its own settings.")
        else
            status, isInUse = ns.L("In use."), true
        end
        integrations[#integrations + 1] = {
            label = provider.label,
            text = ns.L(provider.about or "") .. " " .. status,
            isInUse = isInUse == true,
        }
    end
    return integrations
end

-- Translation addons are for one language each: those of the new one take over, their answers asked afresh
ns.on("LANGUAGE_CHANGED", function()
    QuestText.active = QuestText.getActive()
    QuestText.handleChange()
end)
-- Every addon has loaded by login: the translation addons that are installed and on are found then
ns.registerModule({ name = "QuestText", create = QuestText.start })
