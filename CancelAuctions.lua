-- CancelAuctions.lua
-- This file contains the logic for the "Cancel Undercut Auctions" feature.
-- This version uses a robust, auctionID-based check to correctly identify competitors.

AL = _G.AL or {}

-- State Management
AL.auctionsToCancel = {}
AL.isCancelScanning = false
AL.isCancelling = false
AL.itemBeingCancelScanned = nil
AL.myAuctionsByItemID = {}
AL.itemsToScanForCancel = {}
AL.currentScanIndex = 0
AL.totalItemsToScan = 0

-- Throttle constants
-- SURGICAL CHANGE: Reduced throttle delay by 50% for a much faster scan.
local SCAN_THROTTLE_DELAY = 0.5
local CANCEL_THROTTLE_DELAY = 0.8
-- SURGICAL CHANGE: Reduced failsafe timeout by 50% to avoid getting stuck.
local SCAN_FAILSAFE_TIMEOUT = 5 -- seconds

local scanFailsafeTimer = nil

-- ============================================================================
-- == EVENT HANDLING
-- ============================================================================
-- Create a dedicated frame to handle AH events securely.
local eventFrame = CreateFrame("Frame", "ALCancelScanEventFrame")

function AL:RegisterCancelScanEvents()
    if not self.eventsRegistered then
        eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
        eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
        eventFrame:SetScript("OnEvent", function(self, event, data)
            local itemKeyObject
            if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
                itemKeyObject = { itemID = data }
            else
                itemKeyObject = data
            end
            AL:ProcessCancelScanResults(itemKeyObject, event)
        end)
        self.eventsRegistered = true
    end
end

function AL:UnregisterCancelScanEvents()
    if self.eventsRegistered then
        eventFrame:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
        eventFrame:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
        eventFrame:SetScript("OnEvent", nil)
        self.eventsRegistered = false
    end
end

-- ============================================================================
-- == UI AND REPORTING
-- ============================================================================
function AL:UpdateCancelStatus(text, color)
    if AL.SetBlasterStatus then
        AL:SetBlasterStatus(text, color or {1, 1, 1, 1})
    else
        DEFAULT_CHAT_FRAME:AddMessage("AL Cancel Scan: " .. (text or ""))
    end
end

-- SURGICAL CHANGE: This new function manages the state of the cancel buttons.
function AL:UpdateCancelUIState()
    if not self.BlasterWindow then return end
    
    local numToCancel = #self.auctionsToCancel
    
    if numToCancel > 0 then
        self.BlasterWindow.CancelUndercutButton:Hide()
        self.BlasterWindow.CancelNextButton:Show()
        self.BlasterWindow.CancelNextButton:Enable()
        self.BlasterWindow.CancelNextButton:SetText(string.format("Cancel Next (%d)", numToCancel))
    else
        -- Scan is done and queue is empty, reset to default state.
        self.BlasterWindow.CancelUndercutButton:Show()
        self.BlasterWindow.CancelNextButton:Hide()
        self.BlasterWindow.CancelNextButton:Disable()
        self.BlasterWindow.CancelNextButton:SetText("Cancel Next (0)")
        self:UpdateCancelStatus("Ready to scan for undercuts.", {1,1,1,1})
    end
end

function AL:PrintCancelScanReport()
    local numFound = #self.auctionsToCancel
    if numFound == 0 then
        self:UpdateCancelStatus("Scan complete. No undercuts found.", {0.2, 1.0, 0.2, 1.0})
        return
    end

    print("|cffeda55f[Auctioneer's Ledger]: Cancel Scan Report - " .. numFound .. " auctions found to be undercut.|r")
    print("|cffcccccc--------------------------------------------------|r")

    for _, data in ipairs(self.auctionsToCancel) do
        local auction = data.auction
        local myPriceStr = GetCoinTextureString(data.myPrice)
        local competitorPriceStr = GetCoinTextureString(data.competitorPrice)
        
        local reportLine = string.format("> %s (%dx @ %s) - %s by: %s",
            auction.itemLink,
            auction.quantity,
            myPriceStr,
            data.undercutType == "price" and "Undercut" or "Position",
            competitorPriceStr
        )
        print(reportLine)
    end
    print("|cffcccccc--------------------------------------------------|r")
end

-- ============================================================================
-- == CORE SCANNING LOGIC (v6 - AuctionID-Based Ownership)
-- ============================================================================
-- This logic remains unchanged as per the directive.
function AL:ProcessCancelScanResults(itemKeyFromEvent, eventName)
    if not self.itemBeingCancelScanned or not itemKeyFromEvent or not itemKeyFromEvent.itemID or itemKeyFromEvent.itemID ~= self.itemBeingCancelScanned then
        return
    end

    if scanFailsafeTimer then
        scanFailsafeTimer:Cancel()
        scanFailsafeTimer = nil
    end

    local itemID = self.itemBeingCancelScanned
    self.itemBeingCancelScanned = nil

    local isCommodity = (eventName == "COMMODITY_SEARCH_RESULTS_UPDATED")
    local numResults = isCommodity and C_AuctionHouse.GetNumCommoditySearchResults(itemID) or C_AuctionHouse.GetNumItemSearchResults(itemKeyFromEvent)
    
    if numResults == 0 then
        self:ScanNextCancelItemType()
        return
    end

    local myAuctionsForThisItem = self.myAuctionsByItemID[itemID] or {}
    
    local myAuctionIDLookup = {}
    
    for i, myAuction in ipairs(myAuctionsForThisItem) do
        myAuctionIDLookup[myAuction.auctionID] = myAuction
    end

    local lowestCompetitorPricePerUnit = nil
    local myCurrentAuctionData = {}
    
    if isCommodity then
        for i = 1, numResults do
            local resultInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
            if resultInfo and resultInfo.auctionID then
                local myAuction = myAuctionIDLookup[resultInfo.auctionID]
                local pricePerUnit = resultInfo.unitPrice or 0
                if pricePerUnit <= 0 and resultInfo.buyoutAmount and resultInfo.quantity and resultInfo.quantity > 0 then
                    pricePerUnit = resultInfo.buyoutAmount / resultInfo.quantity
                end
                if myAuction then
                    myCurrentAuctionData[resultInfo.auctionID] = { pricePerUnit = pricePerUnit, totalPrice = resultInfo.buyoutAmount or (pricePerUnit * (resultInfo.quantity or 1)), quantity = resultInfo.quantity or myAuction.quantity }
                elseif pricePerUnit > 0 then
                    if not lowestCompetitorPricePerUnit or pricePerUnit < lowestCompetitorPricePerUnit then lowestCompetitorPricePerUnit = pricePerUnit end
                end
            end
        end
    else
        for i = 1, numResults do
            local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(itemKeyFromEvent, i)
            if resultInfo and resultInfo.auctionID then
                local myAuction = myAuctionIDLookup[resultInfo.auctionID]
                local pricePerUnit = (resultInfo.buyoutAmount and resultInfo.quantity and resultInfo.quantity > 0) and (resultInfo.buyoutAmount / resultInfo.quantity) or 0
                if myAuction then
                    myCurrentAuctionData[resultInfo.auctionID] = { pricePerUnit = pricePerUnit, totalPrice = resultInfo.buyoutAmount or 0, quantity = resultInfo.quantity or myAuction.quantity }
                elseif pricePerUnit > 0 then
                    if not lowestCompetitorPricePerUnit or pricePerUnit < lowestCompetitorPricePerUnit then lowestCompetitorPricePerUnit = pricePerUnit end
                end
            end
        end
    end

    if not lowestCompetitorPricePerUnit then
        self:ScanNextCancelItemType()
        return
    end

    local undercutsDetected = 0
    for _, myStoredAuction in ipairs(myAuctionsForThisItem) do
        local currentData = myCurrentAuctionData[myStoredAuction.auctionID]
        if currentData then
            -- Only process auctions that still exist in search results
            local myPricePerUnit = currentData.pricePerUnit
            local priceDiff = myPricePerUnit - lowestCompetitorPricePerUnit

            local undercutFound, undercutType = false, ""
            if priceDiff > 0.01 then
                undercutFound, undercutType = true, "price"
            elseif math.abs(priceDiff) <= 0.01 then
                local competitorFoundBeforeUs = false
                if isCommodity then
                    for j = 1, numResults do
                        local checkResult = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, j)
                        if checkResult and checkResult.auctionID then
                            if checkResult.auctionID == myStoredAuction.auctionID then break end
                            if not myAuctionIDLookup[checkResult.auctionID] then
                                local competitorPrice = checkResult.unitPrice or 0
                                if competitorPrice > 0 and math.abs(competitorPrice - myPricePerUnit) <= 0.01 then competitorFoundBeforeUs = true; break end
                            end
                        end
                    end
                else
                    for j = 1, numResults do
                        local checkResult = C_AuctionHouse.GetItemSearchResultInfo(itemKeyFromEvent, j)
                        if checkResult and checkResult.auctionID then
                            if checkResult.auctionID == myStoredAuction.auctionID then break end
                            if not myAuctionIDLookup[checkResult.auctionID] then
                                local competitorPrice = (checkResult.buyoutAmount and checkResult.quantity and checkResult.quantity > 0) and (checkResult.buyoutAmount / checkResult.quantity) or 0
                                if competitorPrice > 0 and math.abs(competitorPrice - myPricePerUnit) <= 0.01 then competitorFoundBeforeUs = true; break end
                            end
                        end
                    end
                end
                if competitorFoundBeforeUs then
                    undercutFound, undercutType = true, "position"
                end
            end

            if undercutFound then
                undercutsDetected = undercutsDetected + 1
                local myTotalPrice = currentData.totalPrice
                local competitorTotalForSameQuantity = lowestCompetitorPricePerUnit * currentData.quantity
                table.insert(self.auctionsToCancel, { auction = myStoredAuction, competitorPrice = competitorTotalForSameQuantity, myPrice = myTotalPrice, undercutType = undercutType })
            end
        end
    end
    
    self:ScanNextCancelItemType()
end


-- ============================================================================
-- == SCAN DRIVER AND INITIALIZER
-- ============================================================================
function AL:ScanNextCancelItemType()
    if scanFailsafeTimer then
        scanFailsafeTimer:Cancel()
        scanFailsafeTimer = nil
    end

    if #self.itemsToScanForCancel == 0 then
        self.isCancelScanning = false
        self.currentScanIndex = 0
        AL:UpdateCancelStatus(string.format("Scan complete. Found %d undercut auctions.", #self.auctionsToCancel), {0, 1, 0, 1})
        self:PrintCancelScanReport()
        self:UnregisterCancelScanEvents() -- Clean up listeners
        -- SURGICAL CHANGE: Update the UI state after the scan finishes.
        self:UpdateCancelUIState()
        return
    end

    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        AL:UpdateCancelStatus("Waiting for AH throttle...", {1, 0.8, 0, 1})
        C_Timer.After(SCAN_THROTTLE_DELAY, function() self:ScanNextCancelItemType() end)
        return
    end

    local itemID = table.remove(self.itemsToScanForCancel, 1)
    if not itemID then
        self:UnregisterCancelScanEvents()
        return
    end

    self.itemBeingCancelScanned = itemID
    self.currentScanIndex = self.currentScanIndex + 1
    
    local itemData = self.myAuctionsByItemID[itemID] and self.myAuctionsByItemID[itemID][1]
    if not itemData then
        self:ScanNextCancelItemType()
        return
    end
    
    local progress = string.format("(%d/%d)", self.currentScanIndex, self.totalItemsToScan)
    AL:UpdateCancelStatus(string.format("Scanning %s... %s", itemData.itemLink, progress), {0.7, 0.7, 1, 1})

    scanFailsafeTimer = C_Timer.NewTimer(SCAN_FAILSAFE_TIMEOUT, function()
        scanFailsafeTimer = nil
        self.itemBeingCancelScanned = nil
        self:ScanNextCancelItemType()
    end)

    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    C_AuctionHouse.SendSearchQuery(itemData.itemKey, sorts, true)
end

function AL:StartCancelScan()
    if self.isCancelScanning or self.isCancelling then return end
    
    self:RegisterCancelScanEvents() -- Activate our listener

    self.isCancelScanning = true
    self.auctionsToCancel = {}
    self.myAuctionsByItemID = {}
    self.itemsToScanForCancel = {}
    self.currentScanIndex = 0
    
    local allOwnedAuctions = C_AuctionHouse.GetOwnedAuctions()
    if not allOwnedAuctions or #allOwnedAuctions == 0 then
        AL:UpdateCancelStatus("You have no auctions to scan.", {1, 0.8, 0, 1})
        self.isCancelScanning = false
        self:UnregisterCancelScanEvents()
        return
    end
    
    for _, auction in ipairs(allOwnedAuctions) do
        -- Enhanced sold auction filtering
        local isValidAuction = auction and 
                              auction.auctionID and 
                              auction.itemKey and 
                              auction.itemKey.itemID and 
                              auction.buyoutAmount and 
                              auction.buyoutAmount > 0
        
        -- Check multiple indicators that an auction has sold
        local isSold = false
        if auction.status == 2 then -- Status 2 = sold
            isSold = true
        end
        
        -- Additional check: if the auction exists in our recent sales
        if isValidAuction and not isSold then
            local itemID = auction.itemKey.itemID
            if self:IsRecentlySold(itemID) then
                isSold = true
            end
        end
        
        -- Only include auctions that are definitely still active
        if isValidAuction and not isSold then
            local itemID = auction.itemKey.itemID
            
            if not self.myAuctionsByItemID[itemID] then
                self.myAuctionsByItemID[itemID] = {}
                table.insert(self.itemsToScanForCancel, itemID)
            end
            
            if not auction.itemLink then
                local _, link = GetItemInfo(itemID)
                auction.itemLink = link or ("|cffff0000Unknown Item|r")
            end
            
            table.insert(self.myAuctionsByItemID[itemID], auction)
        end
    end

    self.totalItemsToScan = #self.itemsToScanForCancel
    if self.totalItemsToScan == 0 then
        AL:UpdateCancelStatus("You have no scannable auctions.", {1, 0.8, 0, 1})
        self.isCancelScanning = false
        self:UnregisterCancelScanEvents()
        return
    end

    AL:UpdateCancelStatus(string.format("Starting scan of %d item types...", self.totalItemsToScan))
    C_Timer.After(0.5, function() self:ScanNextCancelItemType() end)
end

-- ============================================================================
-- == UTILITY & CANCELLATION FUNCTIONS
-- ============================================================================

-- SURGICAL CHANGE: This function now handles the entire cancellation process,
-- including history logging and updating the item's location status. This was
-- necessary to ensure data accuracy, as the previous hook-based method was
-- unreliable for MoP.
function AL:CancelSingleUndercutAuction()
    if self.isCancelling or self.isCancelScanning or #self.auctionsToCancel == 0 then return end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(CANCEL_THROTTLE_DELAY, function() self:CancelSingleUndercutAuction() end)
        return
    end
    
    self.isCancelling = true
    
    local auctionToCancelData = table.remove(self.auctionsToCancel, 1)
    if not auctionToCancelData or not auctionToCancelData.auction then
        self.isCancelling = false
        self:UpdateCancelUIState()
        return
    end
    
    local auctionInfo = auctionToCancelData.auction
    
    -- Process the cancellation data BEFORE calling the API
    self:ProcessAuctionCancellation(auctionInfo)
    
    -- SURGICAL ADDITION: Flag this ID so the secure hook ignores it.
    AL.cancellationProcessedForID = auctionInfo.auctionID
    
    -- Now, actually cancel the auction on the server
    C_AuctionHouse.CancelAuction(auctionInfo.auctionID)
    
    -- Update the UI with the new queue count
    self:UpdateCancelUIState()
    
    C_Timer.After(CANCEL_THROTTLE_DELAY, function() 
        self.isCancelling = false 
        -- If there are more items, keep the button enabled.
        if #self.auctionsToCancel > 0 then
            if self.BlasterWindow and self.BlasterWindow.CancelNextButton then
                self.BlasterWindow.CancelNextButton:Enable()
            end
        end
    end)
end

function AL:IsRecentlySold(itemID)
    if not _G.AuctioneersLedgerFinances or not _G.AuctioneersLedgerFinances.sales then return false end
    local recentThreshold = 300
    local currentTime = time()
    for i = #_G.AuctioneersLedgerFinances.sales, 1, -1 do
        local sale = _G.AuctioneersLedgerFinances.sales[i]
        if sale.timestamp < (currentTime - (recentThreshold + 60)) then break end
        local soldItemID = self:GetItemIDFromLink(sale.itemLink)
        if soldItemID and soldItemID == itemID and (currentTime - sale.timestamp) <= recentThreshold then
            return true
        end
    end
    return false
end

function AL:GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    return tonumber(itemLink:match("item:(%d+)"))
end
