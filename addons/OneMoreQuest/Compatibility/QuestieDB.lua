local _, ns = ...

-- QuestieDB: the quest database OneMoreQuest is built on (Database.lua reads it, through its public API). Its
-- documentation asks two things of addons using it, done here: check that the installed QuestieDB supports the
-- API contract the addon is written against (RequireContract), and show players when it reads its raw source data
-- instead of the built data (slower; meant for development).
local function getStatus()
    local isSupported, problem = ns.Database.checkContract()
    if not isSupported then
        return ns.L(
            "Too old for OneMoreQuest (%s): update QuestieDB; quests for other races and classes may show.",
            problem or "?"
        )
    end
    local notice = ns.Database.getReadModeNotice()
    return notice and ns.L("%s: it reads its raw data, which is slower. Install a QuestieDB release.", notice) or nil
end

ns.Compatibility.register({
    name = "QuestieDB",
    label = "QuestieDB",
    about = "The quest database: where quests start, what they ask, where their mobs and items are.",
    getStatus = getStatus,
    -- Once a session, in the chat, when something needs the player's attention
    onLoginSettled = function()
        local status = getStatus()
        if status and ns.print then
            ns.print("QuestieDB: " .. status)
        end
    end,
})
