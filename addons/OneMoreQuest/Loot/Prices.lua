local addonName, ns = ...

-- What an item is worth when sold: to a vendor, or on the auction house when the Auctionator addon is
-- installed and has seen the item.
local Prices = {}
ns.Prices = Prices

local AUCTION_CUT = 0.05
local BIND_ON_PICKUP = 1

-- [itemId] = true while the game is asked for an item's details, "missing" once it said it has no such item.
-- Each item is asked once: the answer redraws, and asking again on that redraw would never stop for an item the game
-- lacks (the database holds items from other versions of the game).
local askedItems = {}

---Asks the game for an item's details, once; its answer (GET_ITEM_INFO_RECEIVED) redraws what shows it.
function Prices.requestItem(itemId)
    if not itemId or askedItems[itemId] or not (C_Item and C_Item.RequestLoadItemDataByID) then
        return
    end
    askedItems[itemId] = true
    pcall(C_Item.RequestLoadItemDataByID, itemId)
end

---@return boolean isMissing The game said it has no such item (the database holds items from other versions of
---the game): it will never load
function Prices.isItemMissing(itemId)
    return itemId ~= nil and askedItems[itemId] == "missing"
end

---@return boolean changed The game answered for an item this addon asked about and has it: a redraw shows it.
---The game answers for every addon's and its own asking, often many times a second; those change nothing here.
function Prices.handleItemLoaded(itemId, isLoaded)
    if askedItems[itemId] ~= true then
        return false
    end
    if isLoaded == false then
        -- The game has no such item: nothing waits for it any more (getItemValue), settled at the next redraw
        askedItems[itemId] = "missing"
        return false
    end
    askedItems[itemId] = nil -- loaded: should the game forget it later, it may be asked again
    return true
end

---@return string? name, number? vendorPrice, number? bindType nil while the game has not loaded the item
local function getItemDetails(itemId)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo -- luacheck: ignore 113 (an older client's fallback)
    if not getItemInfo then
        return nil
    end
    local name, _, _, _, _, _, _, _, _, _, vendorPrice, _, _, bindType = getItemInfo(itemId)
    if not name then
        Prices.requestItem(itemId)
    end
    return name, vendorPrice, bindType
end

function Prices.getItemName(itemId)
    return getItemDetails(itemId) or ns.Database.getItemField(itemId, "name") or ("Item " .. itemId)
end

---@return boolean hasAuctionData Auctionator is installed and can be asked for prices
function Prices.hasAuctionData()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return (api and api.GetAuctionPriceByItemID) ~= nil
end

---@return number? price Lowest known auction price in copper, nil without Auctionator or without a scan
function Prices.getAuctionPrice(itemId)
    if not Prices.hasAuctionData() then
        return nil
    end
    local isSuccess, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, addonName, itemId)
    return isSuccess and type(price) == "number" and price or nil
end

---Value of one item in copper: the auction price after the house's cut when it beats the vendor, else the
---vendor price. An item that binds when picked up can only go to a vendor.
---@return number value
---@return boolean isPending True while the game is still loading the item; the value is then 0. An item the game
---said it does not have is worth nothing, and not waited for
---@return boolean isAuctionPrice The value is what the auction house pays, not a vendor
function Prices.getItemValue(itemId)
    local name, vendorPrice, bindType = getItemDetails(itemId)
    if not name then
        return 0, not Prices.isItemMissing(itemId), false
    end
    vendorPrice = vendorPrice or 0
    if not ns.settings.shouldUseAuctionPrices or bindType == BIND_ON_PICKUP then
        return vendorPrice, false, false
    end
    local auctionPrice = Prices.getAuctionPrice(itemId)
    if not auctionPrice or auctionPrice * (1 - AUCTION_CUT) <= vendorPrice then
        return vendorPrice, false, false
    end
    return auctionPrice * (1 - AUCTION_CUT), false, true
end

ns.registerModule({
    name = "Prices",
    -- Redrawn for the items this addon asked about, not for every item any addon or the game loads
    changes = { GET_ITEM_INFO_RECEIVED = Prices.handleItemLoaded },
})
