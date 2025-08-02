-- BlasterInventoryScan.lua
-- This file contains the logic for scanning the player's inventory to build a post queue.

function AL:LoadPricingData()
    AL.PricingData = {}
    if not _G.AL_SavedData or not _G.AL_SavedData.Items then return end
    for itemID, entry in pairs(_G.AL_SavedData.Items) do
        local id = tonumber(itemID)
        if id then
            for charKey, data in pairs(entry.characters or {}) do
                local normalPrice = tonumber(data.normalBuyoutPrice) or 0
                local safetyNetPrice = tonumber(data.safetyNetBuyout) or 0
                AL.PricingData[id] = { buyout = normalPrice, safetynet = safetyNetPrice, undercut = tonumber(data.undercutAmount) or 0, settings = data.auctionSettings or {duration=720, quantity=1}, charKey = charKey }
                break
            end
        end
    end
end

function AL:LoadItemsToScan()
    local itemsToScan = {}
    self:LoadPricingData()
    local processedItemIDs = {}

    local bagIDs = {}
    -- FIX: Loop from 0 to 3 for Backpack + 3 bag slots, totaling 4 bags for MoP.
    for i = 0, 3 do
        table.insert(bagIDs, i)
    end

    for _, bagID in ipairs(bagIDs) do
        if bagID and type(bagID) == "number" then
            local numSlots = AL:GetSafeContainerNumSlots(bagID)
            for slot = 1, numSlots do
                local itemLink = AL:GetSafeContainerItemLink(bagID, slot)
                if itemLink then
                    local itemID = self:GetItemIDFromLink(itemLink)
                    if itemID and self.PricingData[itemID] and not processedItemIDs[itemID] then
                        processedItemIDs[itemID] = true
                        
                        local itemName, _, _ = GetItemInfo(itemLink)
                        table.insert(itemsToScan, { itemLink = itemLink, itemID = itemID, itemName = itemName, bag = bagID, slot = slot })
                    end
                end
            end
        end
    end
    return itemsToScan
end

function AL:ProcessScanResult(scannedItem, itemKey, eventName)
    if self.scanFailsafeTimer then self.scanFailsafeTimer:Cancel(); self.scanFailsafeTimer = nil; end
    if not scannedItem or not itemKey then return end
    
    local itemPricing = self.PricingData[scannedItem.itemID]
    if not itemPricing then
        self:SetBlasterStatus(string.format("No pricing data for %s", scannedItem.itemName or "item"), AL.COLOR_LOSS)
        self:ScanNextItem()
        return
    end
    
    local competitorAuctions, myAuctions = {}, {}
    local isCommodity = (eventName == "COMMODITY_SEARCH_RESULTS_UPDATED")
    local numResults = isCommodity and C_AuctionHouse.GetNumCommoditySearchResults(itemKey.itemID) or C_AuctionHouse.GetNumItemSearchResults(itemKey)
    local playerName = UnitName("player")
    
    for i = 1, numResults do
        local resultInfo = isCommodity and C_AuctionHouse.GetCommoditySearchResultInfo(itemKey.itemID, i) or C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if resultInfo then
            local priceToConsider
            
            if isCommodity then
                priceToConsider = resultInfo.unitPrice
            else
                if resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0 then
                    priceToConsider = resultInfo.buyoutAmount
                elseif resultInfo.bidAmount and resultInfo.bidAmount > 0 and resultInfo.quantity and resultInfo.quantity > 0 then
                    priceToConsider = (resultInfo.bidAmount * 1.2) / resultInfo.quantity
                end
            end
            
            if priceToConsider and priceToConsider > 0 then
                local isMyAuction = resultInfo.containsOwnerItem or (resultInfo.ownerName and resultInfo.ownerName == playerName)
                
                local hasBuyout = false
                if isCommodity then
                    hasBuyout = true
                else
                    hasBuyout = (resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0)
                end

                local auctionData = { 
                    pricePerItem = priceToConsider,
                    quantity = resultInfo.quantity or 1,
                    timeLeft = resultInfo.timeLeft,
                    bidAmount = resultInfo.bidAmount,
                    buyoutAmount = resultInfo.buyoutAmount,
                    hasValidBuyout = hasBuyout
                }

                if isMyAuction then 
                    table.insert(myAuctions, auctionData)
                else 
                    table.insert(competitorAuctions, auctionData)
                end
            end
        end
    end
    
    table.sort(competitorAuctions, function(a, b) return a.pricePerItem < b.pricePerItem end)
    
    local buyoutAuctions = {}
    for i, auction in ipairs(competitorAuctions) do
        if auction.hasValidBuyout then
            table.insert(buyoutAuctions, auction)
        end
    end
    
    if #buyoutAuctions > 0 then
        competitorAuctions = buyoutAuctions
    end
    
    local charKey = itemPricing.charKey
    if charKey and _G.AL_SavedData.Items[scannedItem.itemID] and _G.AL_SavedData.Items[scannedItem.itemID].characters[charKey] then
        local marketCache = _G.AL_SavedData.Items[scannedItem.itemID].characters[charKey].marketData
        if marketCache then
            marketCache.lastScan = time()
            marketCache.numAuctions = #competitorAuctions + #myAuctions
            marketCache.minBuyout = #competitorAuctions > 0 and competitorAuctions[1].pricePerItem or 0
            marketCache.marketValue = marketCache.minBuyout
        end
    end
    
    self:SetBlasterStatus(string.format("Found %d competitors for %s", #competitorAuctions, scannedItem.itemName or "item"), {0.8, 1, 0.8, 1})
    
    local safetyNetPrice = itemPricing.safetynet or 0
    local undercutAmount = itemPricing.undercut or 0
    local normalBuyoutPrice = itemPricing.buyout or 0
    local lowestCompetitorPrice = (#competitorAuctions > 0) and competitorAuctions[1].pricePerItem or nil
    
    if not lowestCompetitorPrice then
        if normalBuyoutPrice > 0 then
            self:SetBlasterStatus(string.format("Posting %s at Normal Price (no competition)", scannedItem.itemName or "item"), AL.COLOR_PROFIT)
            self:AddScannedItemToQueue(scannedItem.itemID, normalBuyoutPrice, false, "Posting at Normal Price", nil)
        else
            -- SURGICAL CHANGE: Updated skip reason text.
            local skipReason = "No pricing data found. Right-click to set a price."
            self:SetBlasterStatus(string.format("Skipping %s (No price info)", scannedItem.itemName or "item"), {1, 0.8, 0, 1})
            self:AddScannedItemToQueue(scannedItem.itemID, 0, true, skipReason, nil)
        end
        self:ScanNextItem()
        return
    end
    
    if lowestCompetitorPrice <= safetyNetPrice then
        self:AddScannedItemToQueue(scannedItem.itemID, 0, true, string.format("Market price (%s) is below safety net (%s)", 
            AL:FormatGoldWithIcons(lowestCompetitorPrice), AL:FormatGoldWithIcons(safetyNetPrice)), nil)
        self:ScanNextItem()
        return
    end
    
    local postPrice = lowestCompetitorPrice - undercutAmount
    
    if postPrice <= safetyNetPrice then 
        postPrice = safetyNetPrice + 1 
    end
    
    postPrice = math.max(1, math.floor(postPrice))
    
    local undercutInfo = { 
        undercuttingPrice = lowestCompetitorPrice, 
        undercutAmount = undercutAmount, 
        finalPrice = postPrice 
    }
    
    self:AddScannedItemToQueue(scannedItem.itemID, postPrice, false, nil, undercutInfo)
    self:ScanNextItem()
end

function AL:StartScan()
    if self.isScanning then return end
    self:RegisterBlasterEvents()
    self:InitializeBlasterSession()
    self.itemsToScan = self:LoadItemsToScan()
    self.blasterQueue = {}
    self:RenderBlasterQueueUI()

    if #self.itemsToScan == 0 then
        self:SetBlasterStatus("No items with pricing data found in bags.", {1, 0.8, 0, 1})
        self:UnregisterBlasterEvents()
        return
    end

    self.isScanning = true
    self.isMarketScan = false
    self.BlasterWindow.ScanButton:Disable()
    self.BlasterWindow.BlastButton:Disable()
    self.BlasterWindow.ReloadButton:Disable()
    self.BlasterWindow.AutoPricingButton:Disable()
    self:SetBlasterStatus("Scanning " .. #self.itemsToScan .. " items...")
    self:ScanNextItem()
end
