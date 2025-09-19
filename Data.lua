-- Auctioneer's Ledger - Data
-- This file handles data management, retrieval, and saved variables.

function AL:InitializeSavedData()
    if not _G.AL_SavedData then _G.AL_SavedData = {} end
    if not _G.AL_SavedData.Transactions then _G.AL_SavedData.Transactions = {} end
    if not _G.AL_SavedData.Items then _G.AL_SavedData.Items = {} end
end

-- SURGICAL CHANGE: New function to centralize the logic for processing a cancellation.
-- This ensures history, finances, location flags, and pending auction lists are all updated correctly.
function AL:ProcessAuctionCancellation(auctionInfo)
    if not auctionInfo or not auctionInfo.itemKey or not auctionInfo.itemKey.itemID then
        return
    end

    local itemID = auctionInfo.itemKey.itemID
    local itemLink = auctionInfo.itemLink
    local quantity = auctionInfo.quantity
    local itemName = GetItemInfo(itemLink)
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    
    -- 1. Find the original deposit fee from the pending auctions list.
    -- This match is by necessity fuzzy (by itemID and quantity) because the AH API
    -- does not link a posted auction's ID back to the initial post event.
    local depositFee = 0
    local pendingAuctionIndexToRemove = nil
    local pendingAuctions = _G.AL_SavedData.PendingAuctions and _G.AL_SavedData.PendingAuctions[charKey]
    
    if pendingAuctions then
        for i = #pendingAuctions, 1, -1 do
            local pending = pendingAuctions[i]
            if self:GetItemIDFromLink(pending.itemLink) == itemID and pending.quantity == quantity then
                depositFee = pending.depositFee or 0
                pendingAuctionIndexToRemove = i
                break -- Found the best match, stop searching.
            end
        end
    end

    -- SURGICAL FIX: The call to RecordTransaction has been removed from this function.
    -- The deposit fee is already recorded as a loss when the item is initially posted in Hooks.lua.
    -- Calling it again here would cause the fee to be counted twice. This function is now only
    -- responsible for logging the cancellation event to history and updating the item's location.
    
    -- 3. Add the event to the "cancellations" history tab.
    self:AddToHistory("cancellations", {
        itemName = itemName or "Unknown",
        itemLink = itemLink,
        quantity = quantity,
        price = depositFee, -- "price" for history here means the lost deposit
        timestamp = time()
    })

    -- 4. Set the location flag so the ledger knows the item is in the mail.
    -- [[ DIRECTIVE #4 START: Update location on cancellation ]]
    local itemEntry = _G.AL_SavedData.Items and _G.AL_SavedData.Items[itemID]
    if itemEntry and itemEntry.characters and itemEntry.characters[charKey] then
        local charData = itemEntry.characters[charKey]
        charData.isExpectedInMail = true
        charData.expectedMailCount = (charData.expectedMailCount or 0) + quantity
    end
    -- [[ DIRECTIVE #4 END ]]

    -- 5. If we found a matching pending auction, remove it from the list.
    if pendingAuctionIndexToRemove and pendingAuctions then
        table.remove(pendingAuctions, pendingAuctionIndexToRemove)
    end

    -- 6. Refresh UI and caches to reflect the changes.
    self:RefreshBlasterHistory()
    self:BuildSalesCache()
end

-- [[ DIRECTIVE: New function to reconcile internal mail state with live mail data ]]
function AL:ReconcileLootedMail()
    local liveMailCounts = {}
    -- Step 1: Perform a safe, live scan of the current character's mailbox.
    if type(GetInboxNumItems) == "function" then
        for mailIndex = 1, GetInboxNumItems() do
            local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(mailIndex)
            if hasItem then
                for attachIndex = 1, AL.MAX_MAIL_ATTACHMENTS_TO_SCAN do
                    local mailItemLink = GetInboxItemLink(mailIndex, attachIndex)
                    if mailItemLink then
                        local itemID = self:GetItemIDFromLink(mailItemLink)
                        local _, _, mailItemCount = GetInboxItem(mailIndex, attachIndex)
                        -- Defensive check to prevent the "massive number" bug.
                        if itemID and type(mailItemCount) == "number" and mailItemCount > 0 then
                            liveMailCounts[itemID] = (liveMailCounts[itemID] or 0) + mailItemCount
                        end
                    end
                end
            end
        end
    end

    -- Step 2: Compare the live data against our internal "expected" state.
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    for itemID, itemData in pairs(_G.AL_SavedData.Items or {}) do
        if itemData.characters and itemData.characters[charKey] then
            local charData = itemData.characters[charKey]
            if charData.isExpectedInMail then
                local currentLiveCount = liveMailCounts[tonumber(itemID)] or 0
                -- If the number of items we expect is greater than what's actually
                -- in the mail, it means items have been looted.
                if charData.expectedMailCount > currentLiveCount then
                    charData.expectedMailCount = currentLiveCount
                end
                -- If the count is now zero, clear the flag entirely.
                if charData.expectedMailCount <= 0 then
                    charData.isExpectedInMail = false
                    charData.expectedMailCount = 0
                end
            end
        end
    end
end

function AL:ReconcileHistory(newItemID, newItemName)
    local finances = _G.AuctioneersLedgerFinances
    if not finances then return end
    
    local newItemIDNum = tonumber(newItemID)
    if not newItemIDNum then return end

    local function processHistoryTable(historyTable, transactionType, source)
        if not historyTable then return end
        for _, entry in ipairs(historyTable) do
            if entry.itemName == newItemName and not entry.itemLink then
                local correctLink = _G.AL_SavedData.Items[newItemIDNum] and _G.AL_SavedData.Items[newItemIDNum].itemLink
                if correctLink then
                    entry.itemLink = correctLink
                    self:RecordTransaction(transactionType, source, newItemIDNum, entry.price, entry.quantity)
                end
            end
        end
    end

    processHistoryTable(finances.purchases, "BUY", "AUCTION")
    processHistoryTable(finances.sales, "SELL", "AUCTION")
end

function AL:MigrateFinancialData()
    if not _G.AL_SavedData or not _G.AL_SavedData.Items then return end
    
    local itemIDLookup = {}
    for itemID, itemData in pairs(_G.AL_SavedData.Items) do
        if itemData.itemName then
            itemIDLookup[itemData.itemName] = tonumber(itemID)
        end
    end

    if _G.AuctioneersLedgerFinances and _G.AuctioneersLedgerFinances.purchases then
        for _, purchase in ipairs(_G.AuctioneersLedgerFinances.purchases) do
            local itemID = self:GetItemIDFromLink(purchase.itemLink) or itemIDLookup[purchase.itemName]
            if itemID then
                self:RecordTransaction("BUY", "AUCTION", itemID, purchase.price, purchase.quantity)
            end
        end
    end

    if _G.AuctioneersLedgerFinances and _G.AuctioneersLedgerFinances.sales then
        for _, sale in ipairs(_G.AuctioneersLedgerFinances.sales) do
            local itemID = self:GetItemIDFromLink(sale.itemLink) or itemIDLookup[sale.itemName]
            if itemID then
                self:RecordTransaction("SELL", "AUCTION", itemID, sale.price, sale.quantity)
            end
        end
    end
end

function AL:InitializeDB()
    if type(_G.AL_SavedData) ~= "table" then _G.AL_SavedData = {} end
    if type(_G.AL_SavedData.Settings) ~= "table" then _G.AL_SavedData.Settings = {} end

    if type(AL.InitializeFinancesDB) == "function" then
        AL:InitializeFinancesDB()
    end
    
    _G.AL_SavedData.Settings.dbVersion = _G.AL_SavedData.Settings.dbVersion or 1

    if _G.AL_SavedData.Settings.dbVersion < 9 then
        for _, itemData in pairs(_G.AL_SavedData.Items or {}) do
            for _, charData in pairs(itemData.characters or {}) do
                charData.totalAuctionBoughtQty = charData.totalAuctionBoughtQty or 0
                charData.totalAuctionSoldQty = charData.totalAuctionSoldQty or 0
                charData.totalAuctionProfit = charData.totalAuctionProfit or 0
                charData.totalAuctionLoss = charData.totalAuctionLoss or 0
                
                charData.totalVendorBoughtQty = charData.totalVendorBoughtQty or 0
                charData.totalVendorSoldQty = charData.totalVendorSoldQty or 0
                charData.totalVendorProfit = charData.totalVendorProfit or 0
                charData.totalVendorLoss = charData.totalVendorLoss or 0

                charData.totalAuctionBoughtValue = nil; charData.totalAuctionSoldValue = nil
                charData.lastAuctionBuyPrice = nil; charData.lastAuctionSellPrice = nil
                charData.lastAuctionBuyDate = nil; charData.lastAuctionSellDate = nil
                charData.totalVendorBoughtValue = nil; charData.totalVendorSoldValue = nil
                charData.lastVendorBuyPrice = nil; charData.lastVendorSellPrice = nil
                charData.lastVendorBuyDate = nil; charData.lastVendorSellDate = nil
            end
        end
        
        self:MigrateFinancialData()

        _G.AL_SavedData.Settings.dbVersion = 9
    end

    local defaultSettings = {
        window = {x=nil,y=nil,width=AL.DEFAULT_WINDOW_WIDTH,height=AL.DEFAULT_WINDOW_HEIGHT,visible=true},
        minimapIcon = {},
        itemExpansionStates = {},
        activeViewMode = AL.VIEW_WARBAND_STOCK,
        dbVersion = 9,
        showWelcomeWindow = true, -- SURGICAL ADDITION: Default setting for the new welcome window.
        autoAddNewItems = false, -- RETAIL CHANGE: Add new setting
        filterSettings = {
            [AL.VIEW_WARBAND_STOCK]     = { sort = AL.SORT_ALPHA, quality = nil, stack = nil, view = "GROUPED_BY_ITEM"},
            [AL.VIEW_AUCTION_FINANCES]  = { sort = AL.SORT_ITEM_NAME_FLAT, quality = nil, stack = nil, view = "FLAT_LIST"},
            [AL.VIEW_VENDOR_FINANCES]   = { sort = AL.SORT_ITEM_NAME_FLAT, quality = nil, stack = nil, view = "FLAT_LIST"},
            [AL.VIEW_AUCTION_PRICING]   = { sort = AL.SORT_ITEM_NAME_FLAT, quality = nil, stack = nil, view = "FLAT_LIST"},
            [AL.VIEW_AUCTION_SETTINGS]  = { sort = AL.SORT_ITEM_NAME_FLAT, quality = nil, stack = nil, view = "FLAT_LIST"},
        }
    }

    for k, v in pairs(defaultSettings) do
        if _G.AL_SavedData.Settings[k] == nil then
            _G.AL_SavedData.Settings[k] = v
        end
    end
	
    if type(_G.AL_SavedData.Settings.filterSettings) ~= "table" then
        _G.AL_SavedData.Settings.filterSettings = defaultSettings.filterSettings
    end
    for _, viewMode in ipairs({AL.VIEW_WARBAND_STOCK, AL.VIEW_AUCTION_FINANCES, AL.VIEW_VENDOR_FINANCES, AL.VIEW_AUCTION_PRICING, AL.VIEW_AUCTION_SETTINGS}) do
        if type(_G.AL_SavedData.Settings.filterSettings[viewMode]) ~= "table" then
            _G.AL_SavedData.Settings.filterSettings[viewMode] = defaultSettings.filterSettings[viewMode]
        end
    end

    if type(_G.AL_SavedData.Items) ~= "table" then _G.AL_SavedData.Items = {} end
    if type(_G.AL_SavedData.PendingAuctions) ~= "table" then _G.AL_SavedData.PendingAuctions = {} end
    if type(_G.AL_SavedData.TooltipCache) ~= "table" then _G.AL_SavedData.TooltipCache = {} end
    if type(_G.AL_SavedData.TooltipCache.recentlyViewedItems) ~= "table" then _G.AL_SavedData.TooltipCache.recentlyViewedItems = {} end
end

function AL:RecordTransaction(transactionType, source, itemID, value, quantity)
    if not itemID or not value or value < 0 then return end
    
    local numericItemID = tonumber(itemID)
    if not numericItemID then return end
    
    local itemEntry = _G.AL_SavedData and _G.AL_SavedData.Items and _G.AL_SavedData.Items[numericItemID]
    if not itemEntry then return end

    local charKey = UnitName("player") .. "-" .. GetRealmName()
    if not itemEntry.characters[charKey] then return end
    
    local charData = itemEntry.characters[charKey]
    local qty = quantity or 1
    local prefix = (source == "AUCTION") and "Auction" or "Vendor"

    if transactionType == "BUY" then
        charData["total" .. prefix .. "BoughtQty"] = (charData["total" .. prefix .. "BoughtQty"] or 0) + qty
        charData["total" .. prefix .. "Loss"] = (charData["total" .. prefix .. "Loss"] or 0) + value
    elseif transactionType == "SELL" then
        charData["total" .. prefix .. "SoldQty"] = (charData["total" .. prefix .. "SoldQty"] or 0) + qty
        charData["total" .. prefix .. "Profit"] = (charData["total" .. prefix .. "Profit"] or 0) + value
    elseif transactionType == "DEPOSIT" then
        charData["total" .. prefix .. "Loss"] = (charData["total" .. prefix .. "Loss"] or 0) + value
    end

    if (AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES or AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES) and AL.TriggerDebouncedRefresh then
        AL:TriggerDebouncedRefresh("FINANCE_UPDATE")
    end
end

function AL:InternalAddItem(itemLink, forCharName, forCharRealm)
    local itemName, realItemLink, itemRarity, _, _, _, _, maxStack, _, itemTexture = GetItemInfo(itemLink);
    
    if not itemName or not itemTexture or not realItemLink then
        return false, "Could not get item info from game client."
    end
    
    local itemID = self:GetItemIDFromLink(realItemLink);
    if not itemID then
        return false, "Could not get a valid item ID."
    end
    
    local charKey = forCharName .. "-" .. forCharRealm

    if _G.AL_SavedData.Items[itemID] and _G.AL_SavedData.Items[itemID].characters[charKey] then
        return false, "This item is already being tracked by this character."
    end
    
    if not _G.AL_SavedData.Items[itemID] then
        _G.AL_SavedData.Items[itemID] = {
            itemID = itemID, itemLink = realItemLink, itemName = itemName,
            itemTexture = itemTexture, itemRarity = itemRarity, characters = {}
        }
    end
	
    local isStackable = (tonumber(maxStack) or 1) > 1
    local defaultQuantity = isStackable and (tonumber(maxStack) or 100) or 1

    _G.AL_SavedData.Items[itemID].characters[charKey] = {
        characterName = forCharName, characterRealm = forCharRealm, itemLink = realItemLink, itemRarity = itemRarity,
        lastVerifiedLocation = nil, lastVerifiedCount = 0, lastVerifiedTimestamp = 0, 
        isExpectedInMail = false, expectedMailCount = 0,
        safetyNetBuyout = 0, normalBuyoutPrice = 0, undercutAmount = 0, autoUpdateFromMarket = true,
        auctionSettings = { duration = 720, quantity = defaultQuantity },
        marketData = { lastScan = 0, minBuyout = 0, marketValue = 0, numAuctions = 0, ALMarketPrice = 0 },

        totalAuctionBoughtQty = 0, totalAuctionSoldQty = 0, totalAuctionProfit = 0, totalAuctionLoss = 0,
        totalVendorBoughtQty = 0, totalVendorSoldQty = 0, totalVendorProfit = 0, totalVendorLoss = 0,
    }
    
    self:ReconcileHistory(itemID, itemName)
    self:BuildSalesCache()
    
    return true, "Item Added Successfully"
end

function AL:GetSafeContainerNumSlots(bagIndex)
    -- Mists of Pandaria uses C_Container
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        return C_Container.GetContainerNumSlots(bagIndex)
    end
    return 0
end

function AL:GetSafeContainerItemLink(bagIndex, slotIndex)
    -- Mists of Pandaria uses C_Container
    if C_Container and type(C_Container.GetContainerItemLink) == "function" then
        return C_Container.GetContainerItemLink(bagIndex, slotIndex)
    end
    return nil
end

function AL:GetSafeContainerItemInfo(bagIndex, slotIndex)
    -- Mists of Pandaria uses C_Container
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        return C_Container.GetContainerItemInfo(bagIndex, slotIndex)
    end
    return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
end

function AL:GetItemIDFromLink(itemLink) if not itemLink or type(itemLink) ~= "string" then return nil end return tonumber(string.match(itemLink, "item:(%d+)")) end
function AL:GetItemNameFromLink(itemLink) if not itemLink or type(itemLink) ~= "string" then return "Unknown Item" end local iN=GetItemInfo(itemLink) return iN or "Unknown Item" end

function AL:IsItemAuctionableByLocation(itemLocation)
    -- MoP Change: No C_AuctionHouse.IsSellItemValid, must use fallback
    return self:IsItemAuctionable_Fallback(GetContainerItemLink(itemLocation:GetBagAndSlot()))
end

function AL:IsItemAuctionable_Fallback(itemLink, bagID, slot)
    if not itemLink then return false end
    local itemName, _, _, _, _, itemType = GetItemInfo(itemLink)

    if not itemName then return false end
    if itemType == "Quest" then return false end

    local tooltip = AL.ScanTooltip 
    if not tooltip then return false end
    tooltip:ClearLines()
    
    if bagID and slot then
        tooltip:SetBagItem(bagID, slot)
    else
        tooltip:SetHyperlink(itemLink)
    end
    
    for i = 1, tooltip:NumLines() do
        local lineText = _G[tooltip:GetName() .. "TextLeft" .. i]:GetText()
        if lineText then
            local cleanLineText = string.gsub(lineText, "|c%x%x%x%x%x%x%x%x(.-)|r", "%1")
            if (string.find(cleanLineText, ITEM_SOULBOUND, 1, true) or string.find(cleanLineText, ITEM_BIND_ON_PICKUP, 1, true)) then
                return false
            end
        end
    end
    
    return true
end

function AL:TriggerDebouncedRefresh(reason)
    local debounceSeconds = tonumber(AL.EVENT_DEBOUNCE_TIME)
    if type(debounceSeconds) ~= "number" or debounceSeconds <= 0 then debounceSeconds = 0.75 end
    
    AL.eventDebounceCounter = (AL.eventDebounceCounter or 0) + 1
    
    if AL.eventRefreshTimer then 
        AL.eventRefreshTimer:SetScript("OnUpdate", nil) 
    end
    
    AL.eventRefreshTimer = CreateFrame("Frame")
    local elapsed = 0
    AL.eventRefreshTimer:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= debounceSeconds then
            AL.eventDebounceCounter = 0
            if AL.RefreshLedgerDisplay then AL:RefreshLedgerDisplay() end
            
            self:SetScript("OnUpdate", nil)
            AL.eventRefreshTimer = nil
        end
    end)
end

--[[ SURGICAL REWRITE: MULTI-LOCATION TRACKING & MAIL LOGIC ]]
function AL:GetItemOwnershipDetails(charData_in)
    local results = {}
    
    if not charData_in or not charData_in.characterName then 
        return results 
    end

    local itemID = self:GetItemIDFromLink(charData_in.itemLink)
    local itemCharacterName = charData_in.characterName
    local itemCharacterRealm = charData_in.characterRealm 
    
    local charKey = itemCharacterName .. "-" .. itemCharacterRealm
    local charData = _G.AL_SavedData.Items[itemID] and _G.AL_SavedData.Items[itemID].characters[charKey]
    if not charData then
        return results
    end

    local currentCharacter = UnitName("player")
    local currentRealm = GetRealmName()
    local isCurrentCharacterItemForPersonalCheck = (itemCharacterName == currentCharacter and itemCharacterRealm == currentRealm)
    
    local itemFoundLiveThisPass = false

    -- This helper function creates a standardized details table for a given location.
    local function createDetails(location, count, isStale, notes)
        local d = {
            liveLocation = location, liveCount = count,
            locationText = location, 
            displayText = string.format("%02d", count), 
            notesText = notes or "", 
            isStale = isStale or false, 
            isLink = (location == AL.LOCATION_BAGS)
        }

        if d.locationText == AL.LOCATION_BAGS then d.colorR, d.colorG, d.colorB = GetItemQualityColor(charData_in.itemRarity or 1); d.colorA = 1.0;
        elseif d.locationText == AL.LOCATION_BANK then d.colorR, d.colorG, d.colorB, d.colorA = unpack(AL.COLOR_BANK_GOLD);
        elseif d.locationText == AL.LOCATION_MAIL then d.colorR, d.colorG, d.colorB, d.colorA = unpack(AL.COLOR_MAIL_TAN);
        elseif d.locationText == AL.LOCATION_AUCTION_HOUSE then d.colorR, d.colorG, d.colorB, d.colorA = unpack(AL.COLOR_AH_BLUE);
        else d.colorR, d.colorG, d.colorB, d.colorA = unpack(AL.COLOR_LIMBO); end

        if d.isStale then
            d.colorR, d.colorG, d.colorB = d.colorR * AL.COLOR_STALE_MULTIPLIER, d.colorG * AL.COLOR_STALE_MULTIPLIER, d.colorB * AL.COLOR_STALE_MULTIPLIER;
        end
        
        return d
    end

    if isCurrentCharacterItemForPersonalCheck then
        -- 1. Check Auction House (Live API + Internal List)
        local ahCount = 0
        local isAHOpen = AuctionFrame and AuctionFrame:IsShown()
        if isAHOpen then
            local numOwnedAuctions = GetNumAuctionItems("owner")
            for i = 1, numOwnedAuctions do
                local _, _, count, _, _, _, _, _, _, _, _, _, _, _, auctionItemID = GetAuctionItemInfo("owner", i)
                if auctionItemID and tonumber(auctionItemID) == itemID then
                    ahCount = ahCount + (count or 0)
                end
            end
        end
        -- Also check our pending list for items posted but not yet reflected in the API
        local pendingAuctions = _G.AL_SavedData.PendingAuctions and _G.AL_SavedData.PendingAuctions[charKey]
        if pendingAuctions then
            for _, pending in ipairs(pendingAuctions) do
                if self:GetItemIDFromLink(pending.itemLink) == itemID then
                    ahCount = ahCount + (pending.quantity or 0)
                end
            end
        end
        if ahCount > 0 then
            table.insert(results, createDetails(AL.LOCATION_AUCTION_HOUSE, ahCount, false))
            itemFoundLiveThisPass = true
        end

        -- 2. Check Mail (Internal State Only)
        -- The live mail scan has been removed to fix the bug and follow the new directive.
        -- We now ONLY show mail items if our internal tracker says they should be there.
        if charData.isExpectedInMail and (charData.expectedMailCount or 0) > 0 then
            -- The note is now blank, and it's not considered "stale" because it's an intentional state.
            table.insert(results, createDetails(AL.LOCATION_MAIL, charData.expectedMailCount, false, ""))
            itemFoundLiveThisPass = true
        end

        -- 3. Check Bank & Bags
        local bagsCount = GetItemCount(itemID, false)
        local totalInBagsAndBank = GetItemCount(itemID, true)
        local bankCount = totalInBagsAndBank - bagsCount

        if bankCount > 0 then
            table.insert(results, createDetails(AL.LOCATION_BANK, bankCount, false))
            itemFoundLiveThisPass = true
        end
        if bagsCount > 0 then
            table.insert(results, createDetails(AL.LOCATION_BAGS, bagsCount, false))
            itemFoundLiveThisPass = true
        end
        
        -- Update the "last known" data if we found anything live
        if itemFoundLiveThisPass then
            charData.lastVerifiedTimestamp = GetTime()
            -- We no longer store a single location/count, this is now handled by the multiple rows.
            charData.lastVerifiedLocation = nil 
            charData.lastVerifiedCount = 0
        end
    end

    -- If we are not on the correct character OR if no live items were found, use stale data.
    if not itemFoundLiveThisPass then
        local lastLocation = charData.lastVerifiedLocation
        -- Show expected mail for alts as well, but mark it as stale.
        if charData.isExpectedInMail and (charData.expectedMailCount or 0) > 0 then
             table.insert(results, createDetails(AL.LOCATION_MAIL, charData.expectedMailCount, true, ""))
        elseif lastLocation and charData.lastVerifiedCount > 0 then
            local notes = ""
            if lastLocation == AL.LOCATION_MAIL then notes = "Inside mailbox."
            elseif lastLocation == AL.LOCATION_AUCTION_HOUSE then notes = "Being auctioned." end
            table.insert(results, createDetails(lastLocation, charData.lastVerifiedCount, true, notes))
        end
    end

    -- If after all checks there are no results, the item is in Limbo.
    if #results == 0 then
        table.insert(results, createDetails(AL.LOCATION_LIMBO, 0, false))
        if isCurrentCharacterItemForPersonalCheck then
            charData.lastVerifiedLocation = AL.LOCATION_LIMBO
            charData.lastVerifiedCount = 0
            charData.lastVerifiedTimestamp = GetTime()
            charData.isExpectedInMail = false
            charData.expectedMailCount = 0
        end
    end
    
    return results
end

function AL:ProcessAndStoreItem(itemLink)
    local charName = UnitName("player")
    local charRealm = GetRealmName()
    local success, resultOrMsg = self:InternalAddItem(itemLink, charName, charRealm)

    if success then
        self:SetReminderPopupFeedback(resultOrMsg, true)
        self:RefreshLedgerDisplay()
    else
        self:SetReminderPopupFeedback(resultOrMsg, false)
    end
end

function AL:AttemptAddAllEligibleItemsFromBags()
    if not AL.gameFullyInitialized then
        self:SetReminderPopupFeedback("Game systems are still loading. Please wait a moment and try again.", false)
        return
    end

    local charName = UnitName("player")
    local charRealm = GetRealmName()
    local charKey = charName .. "-" .. charRealm
    local addedCount = 0
    local skippedAlreadyTracked = 0
    local skippedIneligible = 0

    local bagIDs = {}
    for i = 0, 3 do table.insert(bagIDs, i) end
    
    for _, bagID in ipairs(bagIDs) do
        if bagID and type(bagID) == "number" then
            local numSlots = self:GetSafeContainerNumSlots(bagID)
            for slot = 1, numSlots do
                local itemLink = self:GetSafeContainerItemLink(bagID, slot)
                if itemLink then
                    local itemID = self:GetItemIDFromLink(itemLink)
                    if itemID then
                        local isTracked = _G.AL_SavedData.Items[itemID] and _G.AL_SavedData.Items[itemID].characters[charKey]
                        if isTracked then 
                            skippedAlreadyTracked = skippedAlreadyTracked + 1
                        elseif not self:IsItemAuctionable_Fallback(itemLink, bagID, slot) then 
                            skippedIneligible = skippedIneligible + 1
                        else
                            local success, _ = self:InternalAddItem(itemLink, charName, charRealm)
                            if success then 
                                addedCount = addedCount + 1
                            else 
                                skippedAlreadyTracked = skippedAlreadyTracked + 1 
                            end
                        end
                    else
                        skippedIneligible = skippedIneligible + 1
                    end
                end
            end
        end
    end

    if addedCount > 0 then
        self:SetReminderPopupFeedback("Added " .. addedCount .. " new item(s).", true)
        self:BuildSalesCache()
        self:RefreshLedgerDisplay()
    else
        if skippedAlreadyTracked > 0 and skippedIneligible == 0 then
            self:SetReminderPopupFeedback("No new items to add. All eligible items are already tracked.", false)
        else
            self:SetReminderPopupFeedback("No new auctionable items found in your bags.", false)
        end
    end
end

function AL:RemoveTrackedItem(itemIDToRemove, charNameToRemove, realmNameToRemove)
    local charKey = charNameToRemove .. "-" .. realmNameToRemove
    if _G.AL_SavedData.Items[itemIDToRemove] and _G.AL_SavedData.Items[itemIDToRemove].characters[charKey] then
        _G.AL_SavedData.Items[itemIDToRemove].characters[charKey] = nil
        
        if not next(_G.AL_SavedData.Items[itemIDToRemove].characters) then
            _G.AL_SavedData.Items[itemIDToRemove] = nil
        end
        self:BuildSalesCache()
        self:RefreshLedgerDisplay()
    end
end

function AL:RemoveAllInstancesOfItem(itemIDToRemove)
    if _G.AL_SavedData.Items[itemIDToRemove] then
        local itemName = _G.AL_SavedData.Items[itemIDToRemove].itemName or "Unknown Item"
        _G.AL_SavedData.Items[itemIDToRemove] = nil
        if _G.AL_SavedData.Settings.itemExpansionStates then
            _G.AL_SavedData.Settings.itemExpansionStates[itemIDToRemove] = nil
        end
        self:BuildSalesCache()
        self:RefreshLedgerDisplay()
    end
end
