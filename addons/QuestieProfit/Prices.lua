local addonName, ns = ...

local Prices = {}
ns.Prices = Prices

local AUCTION_CUT = 0.05
local BIND_ON_PICKUP = 1

local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

---@return string? name, number? vendorPrice, number? bindType nil while the client has not loaded the item
local function getItemDetails(itemId)
    local name, _, _, _, _, _, _, _, _, _, vendorPrice, _, _, bindType = getItemInfo(itemId)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemId)
    end
    return name, vendorPrice, bindType
end

function Prices.getItemName(itemId)
    return getItemDetails(itemId) or ("item " .. itemId)
end

---@return number? price Lowest known auction price in copper, nil without Auctionator or without a scan
local function getAuctionPrice(itemId)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then
        return nil
    end
    local isSuccess, price = pcall(api.GetAuctionPriceByItemID, addonName, itemId)
    return isSuccess and price or nil
end

function Prices.hasAuctionData()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return (api and api.GetAuctionPriceByItemID) ~= nil
end

---Value of one item in copper: the auction price after the cut when it beats the vendor, else the vendor price.
---@return number value, boolean isPending True while item data is still loading, the value is then 0
function Prices.getItemValue(itemId)
    local name, vendorPrice, bindType = getItemDetails(itemId)
    if not name then
        return 0, true
    end
    vendorPrice = vendorPrice or 0
    if ns.settings.priceSource ~= "auction" or bindType == BIND_ON_PICKUP then
        return vendorPrice, false
    end
    local auctionPrice = getAuctionPrice(itemId)
    if not auctionPrice then
        return vendorPrice, false
    end
    return math.max(vendorPrice, auctionPrice * (1 - AUCTION_CUT)), false
end
