-- Auctioneer's Ledger - GUI Utilities
-- This file contains general UI helper functions used across the addon's GUI.

-- Manually searches the player's bags for an item matching the given link.
-- This is a fallback for when GetCursorInfo() fails to provide location data.
function AL:FindItemLocationInBags(targetItemLink)
    if not targetItemLink then return nil, nil end
    local bagIDs = {}
    -- MoP Change: Loop from 0 to 3 for Backpack + 3 bag slots.
    for i = 0, 3 do table.insert(bagIDs, i) end
    
    for _, bagID in ipairs(bagIDs) do
        if bagID and type(bagID) == "number" then
            local numSlots = self:GetSafeContainerNumSlots(bagID)
            for slot = 1, numSlots do
                local currentItemLink = self:GetSafeContainerItemLink(bagID, slot)
                if currentItemLink == targetItemLink then
                    -- Found it. Return the location.
                    return bagID, slot
                end
            end
        end
    end
    -- Item not found in bags.
    return nil, nil
end

-- Helper to split a copper value into gold, silver, and copper components
function AL:SplitCoinToGSCTable(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperVal = copper % 100
    return {gold = gold, silver = silver, copper = copperVal}
end

-- Helper to combine gold, silver, and copper strings into a single copper value
function AL:CombineGSCToCopper(goldStr, silverStr, copperStr)
    local g = tonumber(goldStr) or 0
    local s = tonumber(silverStr) or 0
    local c = tonumber(copperStr) or 0
    return (g * 10000) + (s * 100) + c
end

-- Formats a copper value into a human-readable string (e.g., "50g 25s 10c")
function AL:FormatGoldForChat(copper)
    if type(copper) ~= "number" or copper == 0 then return "0c" end
    local gsc = AL:SplitCoinToGSCTable(copper)
    local parts = {}
    if gsc.gold > 0 then table.insert(parts, gsc.gold .. "g") end
    if gsc.silver > 0 then table.insert(parts, gsc.silver .. "s") end
    if gsc.copper > 0 then table.insert(parts, gsc.copper .. "c") end
    return table.concat(parts, " ")
end

-- NEW: Helper function to parse a formatted money string (e.g., "50g 25s 10c") into copper
function AL:ParseMoneyString(moneyStr)
    if not moneyStr or type(moneyStr) ~= "string" then return 0 end
    local g, s, c = 0, 0, 0
    local gMatch = string.match(moneyStr, "(%d+)g")
    local sMatch = string.match(moneyStr, "(%d+)s")
    local cMatch = string.match(moneyStr, "(%d+)c")
    g = tonumber(gMatch) or 0
    s = tonumber(sMatch) or 0
    c = tonumber(cMatch) or 0
    return (g * 10000) + (s * 100) + c
end

function AL:SavePricingValue(itemID, charName, realmName, priceType, value, silverValue, copperValue)
    local charKey = charName .. "-" .. realmName
    local itemEntry = _G.AL_SavedData.Items[itemID]

    if not itemEntry or not itemEntry.characters[charKey] then return end

    local charData = itemEntry.characters[charKey]
    local newCopperValue

    if silverValue == nil and copperValue == nil then
        newCopperValue = tonumber(value) or 0
    else
        newCopperValue = AL:CombineGSCToCopper(value, silverValue, copperValue)
    end
    
    if charData[priceType] ~= newCopperValue then
        charData[priceType] = newCopperValue
        AL.dataHasChanged = true
    end
end

function AL:SaveAuctionSetting(itemID, charName, realmName, settingType, value)
    local charKey = charName .. "-" .. realmName
    local itemEntry = _G.AL_SavedData.Items[itemID]

    if not itemEntry or not itemEntry.characters[charKey] then return end
    
    if settingType == "quantity" then
        local _,_,_,_,_,_,_, maxStack = GetItemInfo(itemEntry.itemLink)
        if (tonumber(maxStack) or 1) <= 1 then value = 1 end
    end
    
    local auctionSettings = itemEntry.characters[charKey].auctionSettings
    if not auctionSettings then
        auctionSettings = { duration = 720, quantity = 1 }
        itemEntry.characters[charKey].auctionSettings = auctionSettings
    end

    if auctionSettings[settingType] ~= value then
        auctionSettings[settingType] = value
        AL.dataHasChanged = true
    end
end

function AL:SaveCharacterItemSetting(itemID, charName, realmName, key, value)
    local charKey = charName .. "-" .. realmName
    local itemEntry = _G.AL_SavedData.Items[itemID]

    if not itemEntry or not itemEntry.characters[charKey] then return end

    local charData = itemEntry.characters[charKey]
    if charData[key] ~= value then
        charData[key] = value
        AL.dataHasChanged = true
    end
end

function AL:FormatGoldWithIcons(copper)
    if type(copper) ~= "number" or copper ~= copper then 
        return "0|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
    end
    return C_CurrencyInfo.GetCoinTextureString(copper, nil, true)
end

function AL:FormatGoldAndSilverRoundedUp(copper)
    if type(copper) ~= "number" or copper ~= copper then
        copper = 0
    end

    if copper <= 0 then return "0|TInterface\\MoneyFrame\\UI-SilverIcon:0|t" end

    local gsc = self:SplitCoinToGSCTable(copper)
    local g, s, c = gsc.gold, gsc.silver, gsc.copper

    if c > 0 then
        s = s + 1
    end

    if s >= 100 then
        g = g + math.floor(s / 100)
        s = s % 100
    end

    local parts = {}
    if g > 0 then
        table.insert(parts, g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t")
    end
    if s > 0 or g == 0 then
        table.insert(parts, s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t")
    end
    
    if #parts == 0 then
        return "0|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
    end

    return table.concat(parts, " ")
end
