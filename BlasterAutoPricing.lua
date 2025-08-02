-- BlasterAutoPricing.lua
-- This file contains the logic for the "Auto Pricing" scan feature.

-- MODIFIED HELPER FUNCTION: Now trims the top 20% of the chosen cluster for a more competitive price.
function AL:CalculateClusteredPrice(priceData)
    if not priceData or #priceData == 0 then return 0 end
    if #priceData == 1 then return priceData[1].price end

    local clusters = {}
    local currentCluster = nil

    for i, dataPoint in ipairs(priceData) do
        -- If this is the first item, or if the price jumped by more than 35%, create a new cluster.
        local lastPriceInCluster = (currentCluster and #currentCluster.dataPoints > 0) and currentCluster.dataPoints[#currentCluster.dataPoints].price or dataPoint.price
        if not currentCluster or dataPoint.price > (lastPriceInCluster * 1.35) then
            currentCluster = {
                dataPoints = {}, -- Store the actual data points now
                totalQuantity = 0,
            }
            table.insert(clusters, currentCluster)
        end
        
        table.insert(currentCluster.dataPoints, dataPoint)
        currentCluster.totalQuantity = currentCluster.totalQuantity + dataPoint.quantity
    end
    
    -- Find the best cluster, defined as the one with the highest total item quantity.
    local bestCluster = nil
    local maxQuantity = 0
    for _, cluster in ipairs(clusters) do
        if cluster.totalQuantity > maxQuantity then
            maxQuantity = cluster.totalQuantity
            bestCluster = cluster
        end
    end

    if not bestCluster or #bestCluster.dataPoints == 0 then return priceData[1].price end -- Fallback

    -- [[ BEGIN NEW LOGIC: Trim the TOP 20% of the BEST cluster ]]
    local itemsInCluster = bestCluster.dataPoints
    
    -- No need to sort if only one item, just return its price
    if #itemsInCluster <= 1 then
        return itemsInCluster[1] and itemsInCluster[1].price or 0
    end

    -- Sort items within the chosen cluster by price to identify the top end.
    table.sort(itemsInCluster, function(a, b) return a.price < b.price end)
    
    -- Calculate how many listings to trim from the top (most expensive).
    local auctionsToTrim = math.floor(#itemsInCluster * 0.20)
    local countForAverage = #itemsInCluster - auctionsToTrim

    -- Final calculation using only the bottom 80% of the cluster
    local weightedSum = 0
    local totalQuantity = 0
    for i = 1, countForAverage do
        local item = itemsInCluster[i]
        weightedSum = weightedSum + (item.price * item.quantity)
        totalQuantity = totalQuantity + item.quantity
    end

    if totalQuantity == 0 then
        -- Fallback in case of an issue, return the absolute lowest price in the cluster.
        return itemsInCluster[1] and itemsInCluster[1].price or 0
    end
    
    return math.floor(weightedSum / totalQuantity)
end

-- Processes the results of an Auto-Pricing scan
function AL:ProcessMarketScanResult(scannedItem, itemKey, eventName)
    if self.scanFailsafeTimer then self.scanFailsafeTimer:Cancel(); self.scanFailsafeTimer = nil; end
    if not scannedItem or not itemKey then return end

    local priceData = {}
    local isCommodityScan = (eventName == "COMMODITY_SEARCH_RESULTS_UPDATED")
    local numResults = isCommodityScan and C_AuctionHouse.GetNumCommoditySearchResults(itemKey.itemID) or C_AuctionHouse.GetNumItemSearchResults(itemKey)

    for i = 1, numResults do
        local resultInfo = isCommodityScan and C_AuctionHouse.GetCommoditySearchResultInfo(itemKey.itemID, i) or C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if resultInfo then
            local pricePerItem = isCommodityScan and resultInfo.unitPrice or (resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0 and resultInfo.quantity > 0 and (resultInfo.buyoutAmount / resultInfo.quantity))
            local quantity = resultInfo.quantity or 1
            if pricePerItem and pricePerItem > 0 then
                table.insert(priceData, { price = pricePerItem, quantity = quantity })
            end
        end
    end

    table.sort(priceData, function(a, b) return a.price < b.price end)

    local ALMarketPrice = 0
    local itemEntry = _G.AL_SavedData.Items[scannedItem.itemID]
    if not itemEntry then 
        self:ScanNextItem() -- Proceed immediately
        return
    end

    local last_known_price = 0
    for _, charData in pairs(itemEntry.characters) do
        if charData.marketData and charData.marketData.ALMarketPrice and charData.marketData.ALMarketPrice > 0 then
            last_known_price = charData.marketData.ALMarketPrice
            break
        end
    end

    if #priceData == 0 then
        ALMarketPrice = 0
    elseif last_known_price == 0 then
        ALMarketPrice = self:CalculateClusteredPrice(priceData)
    else
        local lowest_current_price = priceData[1].price
        if lowest_current_price > last_known_price then
            ALMarketPrice = lowest_current_price
        else
            ALMarketPrice = self:CalculateClusteredPrice(priceData)
        end
    end

    for cKey, charData in pairs(itemEntry.characters) do
        charData.marketData = charData.marketData or {}
        charData.marketData.ALMarketPrice = ALMarketPrice
        
        if charData.autoUpdateFromMarket then
            local newBuyout, newSafetyNet
            -- [[ BEGIN FIX ]]
            if ALMarketPrice == 0 then
                -- If there's no market price, we should not invent one.
                -- Set prices to 0 to indicate that manual intervention is needed.
                newBuyout = 0
                newSafetyNet = 0
            else
                -- If there is a market price, calculate the new buyout and safety net.
                newBuyout = math.ceil(ALMarketPrice / 100) * 100
                newSafetyNet = math.ceil((newBuyout * 0.70) / 100) * 100
            end
            -- [[ END FIX ]]

            -- Save the new values to update the ledger.
            self:SavePricingValue(scannedItem.itemID, charData.characterName, charData.characterRealm, "normalBuyoutPrice", newBuyout)
            self:SavePricingValue(scannedItem.itemID, charData.characterName, charData.characterRealm, "safetyNetBuyout", newSafetyNet)
        end
    end
    
    self:SetBlasterStatus(string.format("Updated %s: %s", scannedItem.itemName, self:FormatGoldWithIcons(ALMarketPrice)), {0.8, 1, 0.8, 1})
    
    -- SURGICAL CHANGE: Removed the C_Timer.After delay. The scan loop now proceeds
    -- immediately, relying on the throttle check in ScanNextItem for pacing.
    self:ScanNextItem()
end

function AL:StartMarketPriceScan()
    if self.isScanning then return end
    self:RegisterBlasterEvents()

    self.itemsToScan = {}
    for itemID, itemData in pairs(_G.AL_SavedData.Items or {}) do
        table.insert(self.itemsToScan, { itemID = tonumber(itemID), itemName = itemData.itemName, itemLink = itemData.itemLink })
    end

    if #self.itemsToScan == 0 then
        self:SetBlasterStatus("No items in Ledger to scan.", {1, 0.8, 0, 1})
        self:UnregisterBlasterEvents()
        return
    end

    self.isScanning = true
    self.isMarketScan = true
    self.BlasterWindow.ScanButton:Disable()
    self.BlasterWindow.BlastButton:Disable()
    -- [[ DIRECTIVE: Ensure Refresh button is always enabled ]]
    self.BlasterWindow.ReloadButton:Enable()
    self.BlasterWindow.AutoPricingButton:Disable()
    self:SetBlasterStatus("Updating market prices for " .. #self.itemsToScan .. " items...")
    self:ScanNextItem()
end
