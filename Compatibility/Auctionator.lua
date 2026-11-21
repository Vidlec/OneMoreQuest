local _, ns = ...

-- Auctionator: auction prices for what quests give and drop, through its public API (Prices.lua). Listed on the
-- About page.
ns.Compatibility.register({
    name = "Auctionator",
    label = "Auctionator",
    about = "Auction prices for rewards and drops, in the quests' worth (the Use auction prices setting).",
    detect = function()
        local auctionator = _G.Auctionator
        return type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1 ~= nil
    end,
})
