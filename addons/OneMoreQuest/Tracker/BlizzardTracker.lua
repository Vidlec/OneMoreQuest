local _, ns = ...

-- Hides or restores the game's own objective tracker. A protected frame cannot be hidden in combat, so the
-- change waits until combat ends (Core calls apply again on PLAYER_REGEN_ENABLED).
local BlizzardTracker = {}
ns.BlizzardTracker = BlizzardTracker

local isHooked = false

local function isBlocked(frame)
    return InCombatLockdown() and frame:IsProtected()
end

local function handleShow(frame)
    if ns.settings.shouldHideBuiltInTracker and not isBlocked(frame) then
        frame:Hide()
    end
end

---Hides the game's tracker (and keeps it hidden as the game shows it again), or shows it once more, as the setting
---says; left as it is in a fight.
function BlizzardTracker.apply()
    local frame = ObjectiveTrackerFrame
    if not frame or isBlocked(frame) then
        return
    end
    if ns.settings.shouldHideBuiltInTracker then
        if not isHooked then
            isHooked = true
            frame:HookScript("OnShow", handleShow)
        end
        frame:Hide()
    elseif isHooked then
        frame:Show()
    end
end

-- The game's own tracker, hidden or shown; it cannot be touched in combat, so again once a fight is over
ns.registerModule({ name = "BlizzardTracker", create = BlizzardTracker.apply, afterCombat = BlizzardTracker.apply })
