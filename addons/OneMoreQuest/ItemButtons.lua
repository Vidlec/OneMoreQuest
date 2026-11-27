local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Buttons that use a quest's item, hanging off the tracker's left side level with their quests. Using an item
-- needs a button of the game's protected kind, which may not be created, moved, shown or hidden during combat.
-- So the buttons belong to the screen, not to the tracker (anything a protected button is anchored to becomes
-- restricted too), they are placed by screen position, and during combat they stay as they were until the
-- fight ends.
local ItemButtons = {}
ns.ItemButtons = ItemButtons

local GAP = 10 -- between a button and the tracker's edge
local EDGE = { 0.54, 0.48, 0.29 }

local buttons = {}

local function showTooltip(button)
    if not button.item then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    if button.item.link:find("|H", 1, true) then
        GameTooltip:SetHyperlink(button.item.link)
    elseif button.item.itemId and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(button.item.itemId)
    else
        GameTooltip:AddLine(button.item.name or ns.L("Quest item"), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function createButton(index)
    local button = CreateFrame("Button", "OneMoreQuestItemButton" .. index, UIParent, "SecureActionButtonTemplate")
    button:SetFrameStrata("LOW") -- (with the tracker they stand beside: under every window)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type", "item")
    button.edge = button:CreateTexture(nil, "BACKGROUND")
    button.edge:SetAllPoints(button)
    button.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trims the icon's own border
    button.hover = button:CreateTexture(nil, "HIGHLIGHT")
    button.hover:SetAllPoints(button.icon)
    button.hover:SetColorTexture(1, 1, 1, 0.18)
    button.count = ns.Widgets.createFontString(button, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Hide()
    return button
end

---What may change at any time, combat or not: the picture, the count and the cooldown sweep.
local function updateLook(button, item)
    button.item = item
    -- As see-through as the tracker they stand beside (parented to the screen, they would not follow it)
    local opacity = ns.Tracker.getOpacity()
    if button.opacity ~= opacity then
        button.opacity = opacity
        button:SetAlpha(opacity)
    end
    button.icon:SetTexture(item.texture)
    button.count:SetText(item.count and item.count > 1 and item.count or "")
    local getCooldown = item.itemId and C_Item and C_Item.GetItemCooldown
    if getCooldown and button.cooldown.SetCooldown then
        local start, duration = getCooldown(item.itemId)
        if type(start) == "number" and type(duration) == "number" then
            button.cooldown:SetCooldown(start, duration)
        end
    end
end

---@class ItemPlacement
---@field item { link: string, texture: any, count: number?, itemId: number?, name: string? }
---@field offset number Distance of the quest's top below the tracker's top
---@field size number

---Places one button per quest that has an item. Outside combat the buttons are moved and shown to match;
---during combat only their look is refreshed and the layout waits.
---@param tracker table? The tracker frame; nil hides every button
---@param placements ItemPlacement[]
function ItemButtons.apply(tracker, placements)
    if InCombatLockdown() then
        for index, placement in ipairs(placements) do
            local button = buttons[index]
            if button and button.item and button.item.link == placement.item.link then
                updateLook(button, placement.item)
            end
        end
        return
    end
    local left, top = tracker and tracker:GetLeft(), tracker and tracker:GetTop()
    local usedCount = 0
    if type(left) == "number" and type(top) == "number" then
        for index, placement in ipairs(placements) do
            local button = buttons[index]
            if not button then
                button = createButton(index)
                buttons[index] = button
            end
            button:SetAttribute("item", placement.item.link)
            -- In the tracker's size, so it matches it and the place below is in the tracker's units
            button:SetScale(tracker:GetScale() or 1)
            button:SetSize(placement.size, placement.size)
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - GAP, top - placement.offset)
            updateLook(button, placement.item)
            button:Show()
            usedCount = index
        end
    end
    for index = usedCount + 1, #buttons do
        buttons[index]:Hide()
    end
end
