local addonName, ns = ...

local DEFAULT_SETTINGS = {
    priceSource = "auction", -- "auction" (Auctionator, vendor as fallback) or "vendor"
    minForeverKills = 20, -- recorded kills needed before Forever data replaces the Classic estimate
    shouldShowInTooltip = true,
}

ns.addonName = addonName
ns.settings = DEFAULT_SETTINGS
ns.isReady = false

local settingsListeners = {}

---Calls the callback whenever a setting changes.
function ns.addSettingsListener(callback)
    settingsListeners[#settingsListeners + 1] = callback
end

function ns.setSetting(key, value)
    ns.settings[key] = value
    for _, callback in ipairs(settingsListeners) do
        callback(key, value)
    end
end

function ns.print(message)
    print("|cff8fe08aQuestie Profit|r: " .. message)
end

---Formats copper as a coin string with gold, silver and copper icons.
function ns.formatMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    if copper <= 0 then
        return "0"
    end
    local getCoinText = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if getCoinText then
        return getCoinText(copper)
    end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function handleAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    QuestieProfitDB = QuestieProfitDB or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if QuestieProfitDB[key] == nil then
            QuestieProfitDB[key] = value
        end
    end
    ns.settings = QuestieProfitDB
end

local function handlePlayerLogin()
    if not (Questie and Questie.API and Questie.API.RegisterOnReady) then
        ns.print("this Questie version has no public API, so the addon stays inactive.")
        return
    end
    Questie.API.RegisterOnReady(function()
        ns.isReady = true
        ns.Tooltip.addHook()
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        handleAddonLoaded(...)
    else
        handlePlayerLogin()
    end
end)

SLASH_QUESTIEPROFIT1 = "/qprofit"
SlashCmdList.QUESTIEPROFIT = function(input)
    local command = (input or ""):lower():match("^(%S*)")
    if command == "vendor" or command == "auction" then
        ns.setSetting("priceSource", command)
        ns.print("prices now come from " .. (command == "auction" and "Auctionator" or "vendors") .. ".")
    elseif command == "tooltip" then
        ns.setSetting("shouldShowInTooltip", not ns.settings.shouldShowInTooltip)
        ns.print("tooltip lines " .. (ns.settings.shouldShowInTooltip and "shown" or "hidden") .. ".")
    elseif command == "" then
        ns.Window.toggle()
    else
        ns.print("commands: /qprofit, /qprofit vendor, /qprofit auction, /qprofit tooltip")
    end
end
