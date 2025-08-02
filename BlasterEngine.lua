-- BlasterEngine.lua
-- This file contains the core shared logic for the Blaster's scanning functionality.

-- Create a dedicated event frame for the Blaster to prevent conflicts with global handlers.
AL.BlasterEventFrame = CreateFrame("Frame", "AL_BlasterEventHandler_v" .. AL.VERSION:gsub("%.", "_"))
AL.BlasterEventFrame:SetScript("OnEvent", function(self, event, ...) AL:BlasterEventHandler(event, ...) end)

function AL:RegisterBlasterEvents()
    AL.BlasterEventFrame:UnregisterAllEvents()
    AL.BlasterEventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
    AL.BlasterEventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    AL.BlasterEventFrame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
    AL.BlasterEventFrame:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
end

function AL:UnregisterBlasterEvents()
    if AL.BlasterEventFrame then
        AL.BlasterEventFrame:UnregisterAllEvents()
    end
end

-- The Blaster's event handler
function AL:BlasterEventHandler(event, ...)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKeyFromEvent
        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
            itemKeyFromEvent = { itemID = select(1, ...) }
        else
            itemKeyFromEvent = select(1, ...)
        end

        if not itemKeyFromEvent then
            return
        end

        if self.isScanning and self.itemBeingScanned and itemKeyFromEvent.itemID == self.itemBeingScanned.itemID then
            if self.isMarketScan then
                self:ProcessMarketScanResult(self.itemBeingScanned, itemKeyFromEvent, event)
            else
                self:ProcessScanResult(self.itemBeingScanned, itemKeyFromEvent, event)
            end
            self.itemBeingScanned = nil
        -- SURGICAL FIX: Changed self.itemBeingCancelScanned.itemKey.itemID to self.itemBeingCancelScanned
        -- to correctly compare against the itemID, which is now a number, not a table.
        elseif self.isCancelScanning and self.itemBeingCancelScanned and itemKeyFromEvent.itemID == self.itemBeingCancelScanned then
            self:ProcessCancelScanResults(itemKeyFromEvent, event)
        end

    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        if self.isPosting and self.itemBeingPosted then
            self:HandlePostSuccess()
        end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if self.isPosting and self.itemBeingPosted then
            self:HandlePostFailure(...)
        end
    end
end

-- Failsafe timer for scans
function AL:FailsafeScanStep()
    self.scanFailsafeTimer = nil
    if self.isScanning and self.itemBeingScanned then
        AL:SetBlasterStatus(string.format("Scan timed out for %s", self.itemBeingScanned.itemName), AL.COLOR_LOSS)
        local itemToProcess = self.itemBeingScanned
        self.itemBeingScanned = nil

        -- Create a dummy itemKey so the processing function doesn't fail on a nil argument.
        -- This simulates receiving an empty search result.
        local dummyKey = { itemID = itemToProcess.itemID }
        
        if self.isMarketScan then
             -- When a market scan times out, we have no price data. This will correctly
             -- trigger the logic for when zero results are found.
             self:ProcessMarketScanResult(itemToProcess, dummyKey, "COMMODITY_SEARCH_RESULTS_UPDATED")
        else
             -- When a posting scan times out, we have no competitor data. This will correctly
             -- fall back to posting at the Normal Price from your Ledger.
             self:ProcessScanResult(itemToProcess, dummyKey, "COMMODITY_SEARCH_RESULTS_UPDATED")
        end
    end
end

-- Utility to check if an item is a commodity
function AL:IsItemACommodity(itemLocationOrID)
    if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus then
        local status
        if type(itemLocationOrID) == "number" then
            for bag = 0, NUM_BAG_SLOTS + 1 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    if C_Container.GetContainerItemID(bag, slot) == itemLocationOrID then
                        status = C_AuctionHouse.GetItemCommodityStatus(ItemLocation:CreateFromBagAndSlot(bag, slot))
                        break
                    end
                end
                if status then break end
            end
        else
            status = C_AuctionHouse.GetItemCommodityStatus(itemLocationOrID)
        end
        if status then return status == Enum.ItemCommodityStatus.Commodity end
    end
    return false -- Fallback
end

-- The core scan loop
function AL:ScanNextItem()
    if not self.isScanning then return end
    if not C_AuctionHouse or not C_AuctionHouse.IsThrottledMessageSystemReady() then
        AL:SetBlasterStatus("Waiting for AH throttle...", {1, 0.8, 0, 1})
        -- SURGICAL CHANGE: Further reduced throttle polling from 1.0s to 0.75s for maximum speed.
        C_Timer.After(0.75, function() if AL.isScanning then AL:ScanNextItem() end end)
        return
    end
    
    if #self.itemsToScan == 0 then
        self.isScanning = false
        self.itemBeingScanned = nil
        self.BlasterWindow.ScanButton:Enable()
        self.BlasterWindow.ReloadButton:Enable()
        self.BlasterWindow.AutoPricingButton:Enable()
        self:UnregisterBlasterEvents()
        
        if self.isMarketScan then
             self:SetBlasterStatus("Auto Pricing scan complete!", AL.COLOR_PROFIT)
             self:RefreshLedgerDisplay()
             StaticPopup_Show("AL_MARKET_SCAN_COMPLETE")
        else
            local queuedCount = 0; for _, item in ipairs(self.blasterQueue) do if not item.skipped then queuedCount = queuedCount + 1 end end
            self:SetBlasterStatus(string.format("Scan complete. %d queued.", queuedCount), AL.COLOR_PROFIT)
            if queuedCount > 0 then self:BlastNextItem() end
        end
        self.isMarketScan = false
        return
    end
    
    self.itemBeingScanned = table.remove(self.itemsToScan, 1)
    if self.scanFailsafeTimer then self.scanFailsafeTimer:Cancel() end
    -- SURGICAL CHANGE: Further reduced the per-item scan timeout from 2.0s to 1.5s.
    self.scanFailsafeTimer = C_Timer.After(1.5, function() AL:FailsafeScanStep() end)
    
    local itemToScan = self.itemBeingScanned
    local itemKey

    local itemLocation
    if itemToScan.bag and itemToScan.slot then
        itemLocation = ItemLocation:CreateFromBagAndSlot(itemToScan.bag, itemToScan.slot)
    end

    if itemLocation and itemLocation:IsValid() and C_AuctionHouse.GetItemKeyFromItem then
        itemKey = C_AuctionHouse.GetItemKeyFromItem(itemLocation)
    else
        if itemToScan.itemLink and string.find(itemToScan.itemLink, "item:") then
            local _, _, _, itemLevel, _, _, _, _, _, _, _, itemClassID = GetItemInfo(itemToScan.itemLink)
            
            local itemSuffixID = nil
            local linkContent = itemToScan.itemLink:match("item:([%d:]+)")
            if linkContent then
                local parts = {}
                for part in linkContent:gmatch("([^:]+)") do
                    table.insert(parts, part)
                end
                if #parts >= 8 then
                    itemSuffixID = tonumber(parts[8])
                end
            end

            if itemLevel and itemLevel > 0 and (itemClassID == 4 or itemClassID == 2) then
                if itemSuffixID and itemSuffixID ~= 0 then
                    itemKey = C_AuctionHouse.MakeItemKey(itemToScan.itemID, itemLevel, itemSuffixID)
                else
                    itemKey = C_AuctionHouse.MakeItemKey(itemToScan.itemID, itemLevel)
                end
            else
                itemKey = C_AuctionHouse.MakeItemKey(itemToScan.itemID)
            end
        else
            itemKey = C_AuctionHouse.MakeItemKey(itemToScan.itemID)
        end
    end
    
    if not itemKey then
        self:FailsafeScanStep()
        return
    end
    
    self:SetBlasterStatus(string.format("Searching for %s... (%d left)", itemToScan.itemName or "item", #self.itemsToScan), {0.7, 0.7, 1, 1})
    
    local _, _, _, _, _, _, _, _, _, _, itemClassID = GetItemInfo(itemToScan.itemLink or itemToScan.itemID)
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }

    if itemClassID and (itemClassID == 2 or itemClassID == 4) then
        C_AuctionHouse.SendSellSearchQuery(itemKey, sorts, false)
    else
        C_AuctionHouse.SendSearchQuery(itemKey, sorts, false)
    end
end
