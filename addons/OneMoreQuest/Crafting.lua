local _, ns = ...

-- Items players make with a profession (CraftedItems.lua, from the game's own data): a quest that asks for one cannot
-- send the player anywhere on the map, so it says how to get it instead: make it, with the profession and the skill
-- when the player has it, or get it from someone who does (a crafter, the Auction House).
local Crafting = {}
ns.Crafting = Crafting

-- The professions by their skill line, as the game names them (secondary skills and poisons among them)
Crafting.PROFESSION_NAMES = {
    [40] = "Poisons",
    [129] = "First Aid",
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [171] = "Alchemy",
    [182] = "Herbalism",
    [185] = "Cooking",
    [186] = "Mining",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting",
    [356] = "Fishing",
    [393] = "Skinning",
    [755] = "Jewelcrafting",
    [773] = "Inscription",
    [3012] = "Comprehension",
}

---@return string? name A profession's name in the addon's language, nil for a skill line that is not one
function Crafting.getProfessionName(skillLineId)
    local name = Crafting.PROFESSION_NAMES[skillLineId]
    return name and ns.L(name) or nil
end

---@return { skillLineId: number, rank: number? }? recipe What makes the item: its profession, and the skill the
---recipe needs when the game's data says (nil when it does not); nil for an item no profession makes
function Crafting.getRecipe(itemId)
    local row = itemId and ns.CraftedItems and ns.CraftedItems[itemId]
    if not row then
        return nil
    end
    return { skillLineId = row[1], rank = row[2] > 0 and row[2] or nil }
end

-- The recipes the character knows, read from the profession window whenever it opens (the game tells nothing of them
-- otherwise): [skillLineId] = { [itemId] = true }, per character. Only what the window listed is known; recipes it
-- did not list are simply not known yet, so nothing is ever said to be unknown.

local function getKnownRecipes()
    return ns.getCharacterRecords("knownRecipes")
end

---@return boolean isKnown The character's profession window has listed a recipe that makes the item
function Crafting.isRecipeKnown(itemId)
    local recipe = Crafting.getRecipe(itemId)
    local known = recipe and getKnownRecipes()[recipe.skillLineId]
    return known ~= nil and known[itemId] == true
end

---@return number[] itemIds What the open profession window's learnt recipes make: through C_TradeSkillUI where the client
---has it (WoW: Forever), else the older functions
local function readWindowItems()
    local itemIds = {}
    local ui = C_TradeSkillUI
    if ui and ui.GetAllRecipeIDs and ui.GetRecipeInfo then
        for _, recipeId in ipairs(ui.GetAllRecipeIDs() or {}) do
            local info = ui.GetRecipeInfo(recipeId)
            if info and info.learned then
                local schematic = ui.GetRecipeSchematic and ui.GetRecipeSchematic(recipeId, false)
                local output = not (schematic and schematic.outputItemID)
                    and ui.GetRecipeOutputItemData
                    and ui.GetRecipeOutputItemData(recipeId)
                itemIds[#itemIds + 1] = schematic and schematic.outputItemID or output and output.itemID or nil
            end
        end
    elseif GetNumTradeSkills and GetTradeSkillItemLink then
        for index = 1, GetNumTradeSkills() or 0 do
            local _, kind = GetTradeSkillInfo(index)
            local link = kind ~= "header" and GetTradeSkillItemLink(index)
            itemIds[#itemIds + 1] = link and tonumber(link:match("item:(%d+)")) or nil
        end
    end
    return itemIds
end

---Reads the open profession window's recipes into what the character knows. Each item is filed under the profession
---the game's data says makes it, so the window's own name for its profession does not matter.
---@return boolean hasLearned A recipe not known before was found
function Crafting.readProfessionWindow()
    local isRead, itemIds = pcall(readWindowItems)
    if not isRead then
        return false
    end
    local records, hasLearned = getKnownRecipes(), false
    for _, itemId in ipairs(itemIds) do
        local recipe = Crafting.getRecipe(itemId)
        if recipe then
            records[recipe.skillLineId] = records[recipe.skillLineId] or {}
            if not records[recipe.skillLineId][itemId] then
                records[recipe.skillLineId][itemId], hasLearned = true, true
            end
        end
    end
    return hasLearned
end

---@return number count How many of an item wait in the bank: known once the bank has been opened this session, else 0.
---A quest counts only what is in the bags.
function Crafting.getBankCount(itemId)
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount -- luacheck: ignore 113 (an older client's fallback)
    if not getCount then
        return 0
    end
    return math.max((getCount(itemId, true) or 0) - (getCount(itemId) or 0), 0)
end

---@param stillNeeded number? How many the quest still asks for (1 when not said)
---@return string? text How to get a crafted item, in words: "Made with Alchemy · you know the recipe · 2 in your bank";
---nil for an item no profession makes. With Auctionator's prices, what the ones still to get cost at the Auction House,
---to buy rather than make.
function Crafting.describe(itemId, stillNeeded)
    local recipe = Crafting.getRecipe(itemId)
    local profession = recipe and Crafting.getProfessionName(recipe.skillLineId)
    if not profession then
        return nil
    end
    local parts =
        { recipe.rank and ns.L("Made with %s %d", profession, recipe.rank) or ns.L("Made with %s", profession) }
    local playerRank = ns.Availability.getSkillRank(recipe.skillLineId)
    local inBank = Crafting.getBankCount(itemId)
    local toGet = math.max((stillNeeded or 1) - inBank, 0)
    local price = toGet > 0 and ns.Prices.getAuctionPrice(itemId)
    local priceText = price
        and (
            toGet > 1 and ns.L("about %s for %d at the Auction House", ns.Widgets.formatMoney(price * toGet), toGet)
            or ns.L("about %s at the Auction House", ns.Widgets.formatMoney(price))
        )
    if playerRank <= 0 then -- not learnt: from someone who makes it
        if toGet > 0 then
            parts[#parts + 1] = priceText and ns.L("get it from a crafter, or %s", priceText)
                or ns.L("get it from a crafter or the Auction House")
        end
    else
        if Crafting.isRecipeKnown(itemId) then
            parts[#parts + 1] = ns.L("you know the recipe")
        elseif recipe.rank and playerRank < recipe.rank then
            parts[#parts + 1] = ns.L("you have %d", playerRank)
        else
            parts[#parts + 1] = ns.L("you can make it if you know the recipe (skill %d)", playerRank)
        end
        parts[#parts + 1] = priceText or nil
    end
    if inBank > 0 then
        parts[#parts + 1] = ns.L("%d in your bank", inBank)
    end
    return table.concat(parts, " · ")
end

ns.registerModule({
    name = "Crafting",
    events = {
        -- The bank seen: what waits there changes what the crafting line says
        BANKFRAME_OPENED = function()
            ns.queueRefresh()
        end,
        PLAYERBANKSLOTS_CHANGED = function()
            ns.queueRefresh()
        end,
        TRADE_SKILL_SHOW = function()
            if Crafting.readProfessionWindow() then
                ns.queueRefresh()
            end
        end,
        -- Its recipes listed, or listed again (TRADE_SKILL_LIST_UPDATE in this client; TRADE_SKILL_UPDATE in older ones)
        TRADE_SKILL_LIST_UPDATE = function()
            if Crafting.readProfessionWindow() then
                ns.queueRefresh()
            end
        end,
        TRADE_SKILL_UPDATE = function()
            if Crafting.readProfessionWindow() then
                ns.queueRefresh()
            end
        end,
    },
    -- A profession given up takes its recipes with it
    prune = function()
        local records = getKnownRecipes()
        for skillLineId in pairs(records) do
            if ns.Availability.getSkillRank(skillLineId) <= 0 then
                records[skillLineId] = nil
            end
        end
    end,
})
