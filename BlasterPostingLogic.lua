-- BlasterPostingLogic.lua
-- This file contains the logic for posting items and managing the blaster queue.

-- ============================================================================
-- BLASTER DATA AND LOGIC
-- ============================================================================

function AL:SetPostFailureTimer()
    if self.postFailureTimer then self.postFailureTimer:Cancel() end
    self.postFailureTimer = C_Timer.After(10.0, function()
        if AL.itemBeingPosted and AL.isPosting then
            AL:HandlePostFailure("Timeout")
        end
    end)
end

function AL:CancelPostFailureTimer()
    if self.postFailureTimer then
        self.postFailureTimer:Cancel()
        self.postFailureTimer = nil
    end
end

function AL:HandlePostFailure(reason)
    if not AL.itemBeingPosted then return end
    AL:SetBlasterStatus(string.format("✗ Failed: %s (%s)", AL.itemBeingPosted.itemName, reason or "Unknown"), AL.COLOR_LOSS)
    AL:TrackPostResult(AL.itemBeingPosted, false, reason)
    AL:CancelPostFailureTimer()
    AL.isPosting = false
    AL.itemBeingPosted = nil
    if AL.blasterQueue and #AL.blasterQueue > 0 then
        table.remove(AL.blasterQueue, 1)
        AL:RenderBlasterQueueUI()
    end
    C_Timer.After(0.25, function() AL:BlastNextItem() end)
end

function AL:HandlePostSuccess()
    if not AL.itemBeingPosted then return end

    -- SURGICAL FIX: Moved history recording logic here from Core.lua to ensure it runs on the correct event.
    if AL.pendingPostDetails and AL.pendingPostDetails.itemLink then
        local details = AL.pendingPostDetails

        AL:RecordTransaction("AUCTION_POST", details.itemID, details.depositFee, details.quantity)
        
        local historyData = { 
            itemLink = details.itemLink, 
            quantity = details.quantity, 
            price = details.depositFee, 
            totalValue = details.postPrice * details.quantity,
            timestamp = time() 
        }
        AL:AddToHistory("posts", historyData)
        
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        if not _G.AL_SavedData.PendingAuctions[charKey] then _G.AL_SavedData.PendingAuctions[charKey] = {} end
        table.insert(_G.AL_SavedData.PendingAuctions[charKey], { itemLink = details.itemLink, quantity = details.quantity, totalValue = details.postPrice * details.quantity, depositFee = details.depositFee, postTime = time() })
        
        AL:BuildSalesCache()
        AL:RefreshBlasterHistory()
    end
    AL.pendingPostDetails = nil -- Clear it after processing.

    AL:SetBlasterStatus(string.format("✓ Posted %s", AL.itemBeingPosted.itemName), AL.COLOR_PROFIT)
    AL:TrackPostResult(AL.itemBeingPosted, true)
    AL:CancelPostFailureTimer()
    AL.isPosting = false
    if AL.blasterQueue and #AL.blasterQueue > 0 then
        table.remove(AL.blasterQueue, 1)
        AL:RenderBlasterQueueUI()
    end
    AL.itemBeingPosted = nil
    C_Timer.After(0.25, function() AL:BlastNextItem() end)
end

function AL:SkipQueueItem()
    if not self.isPosting or not self.itemBeingPosted then return end
    AL:HandlePostFailure("Manually Skipped")
end

function AL:InitializeBlasterSession()
    AL.currentBlasterSession = { startTime = time(), totalPosts = 0, successfulPosts = 0, failedPosts = 0, totalValue = 0, totalFees = 0, items = {} }
end

function AL:TrackPostResult(itemData, success, failureReason)
    if not AL.currentBlasterSession then AL:InitializeBlasterSession() end
    local session = AL.currentBlasterSession
    local totalValue = itemData.postPrice * itemData.quantity
    local itemLocation = ItemLocation:CreateFromBagAndSlot(itemData.bag, itemData.slot)
    local depositFee = 0
    if itemLocation:IsValid() then
        local itemID = C_Container.GetContainerItemID(itemData.bag, itemData.slot)
        if itemID then
            local vendorPrice = select(11, GetItemInfo(itemID)) or 0
            if vendorPrice and vendorPrice > 0 then
                local durationHours = (itemData.durationMinutes or 720) / 60
                local durationMultiplier = durationHours / 12
                depositFee = math.floor(vendorPrice * itemData.quantity * 0.05 * durationMultiplier)
            end
        end
    end
    session.totalPosts = session.totalPosts + 1
    if success then
        session.successfulPosts = session.successfulPosts + 1
        session.totalValue = session.totalValue + totalValue
        session.totalFees = session.totalFees + depositFee
    else
        session.failedPosts = session.failedPosts + 1
    end
    table.insert(session.items, { itemLink = itemData.itemLink, quantity = itemData.quantity, price = itemData.postPrice, totalValue = totalValue, fee = depositFee, success = success, failureReason = failureReason, timestamp = time() })
    if depositFee > 0 then
        local pricingInfo = AL.PricingData and AL.PricingData[itemData.itemID]
        if pricingInfo and pricingInfo.charKey then
            local charKey = pricingInfo.charKey
            local itemEntry = _G.AL_SavedData and _G.AL_SavedData.Items and _G.AL_SavedData.Items[itemData.itemID]
            if itemEntry and itemEntry.characters and itemEntry.characters[charKey] then
                local charData = itemEntry.characters[charKey]
                charData.totalCosts = (charData.totalCosts or 0) + depositFee
            end
        end
    end
end

function AL:PrintBlasterSummary()
    if not AL.currentBlasterSession or AL.currentBlasterSession.totalPosts == 0 then
        AL:SetBlasterStatus("Queue finished!", AL.COLOR_PROFIT)
        return
    end
    local session = AL.currentBlasterSession
    if session.successfulPosts > 0 then
        AL:SetBlasterStatus(string.format("Session complete! Posted %s worth of items.", AL:FormatGoldWithIcons(session.totalValue)), AL.COLOR_PROFIT)
    else
        AL:SetBlasterStatus("Session complete. No items were posted.", {1, 0.8, 0, 1})
    end
    AL.currentBlasterSession = nil
end

function AL:AddScannedItemToQueue(itemID, postPrice, skipped, skipReason, undercutInfo)
    local totalCountInBags = C_Item.GetItemCount(itemID)
    if totalCountInBags == 0 then return end
    local itemData = self.PricingData[itemID]
    if not itemData then return end
    local settings = itemData.settings
    local postQuantity = settings.quantity or 1
    if postQuantity <= 0 then postQuantity = 1 end
    local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
    if (tonumber(maxStack) or 1) <= 1 then postQuantity = 1 end
    local quantityForThisPost = math.min(totalCountInBags, postQuantity)
    local durationMinutes = settings.duration or 720
    local auctionDuration
    if durationMinutes <= 720 then auctionDuration = 1
    elseif durationMinutes <= 1440 then auctionDuration = 2
    else auctionDuration = 3 end
    local bag, slot, link, icon, name, rarity
    for b = 0, NUM_BAG_SLOTS + 1 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            if C_Container.GetContainerItemID(b, s) == itemID then
                bag, slot = b, s
                link = C_Container.GetContainerItemLink(b, s)
                local itemInfo = C_Container.GetContainerItemInfo(b, s)
                icon = itemInfo and itemInfo.iconFileID
                local iName, _, iRarity = GetItemInfo(link)
                name = iName
                rarity = iRarity
                break
            end
        end
        if bag then break end
    end
    if link then
        table.insert(self.blasterQueue, { 
            itemID = itemID, 
            itemLink = link, 
            itemName = ("|c%s%s|r"):format(select(4, GetItemQualityColor(rarity or 1)), name or "?"), 
            bag = bag, 
            slot = slot, 
            icon = icon, 
            quantity = quantityForThisPost, 
            duration = auctionDuration, 
            durationMinutes = durationMinutes, 
            postPrice = postPrice, 
            skipped = skipped or false, 
            skipReason = skipReason, 
            undercutInfo = undercutInfo,
            readyForRescan = false
        })
    end
    self:RenderBlasterQueueUI()
end

function AL:BlastNextItem()
    if AL.isPosting then return end

    if self.blasterQueue and #self.blasterQueue > 0 then
        table.sort(self.blasterQueue, function(a, b)
            if a.skipped and not b.skipped then
                return false
            end
            if not a.skipped and b.skipped then
                return true
            end
            return a.itemName < b.itemName
        end)
        self:RenderBlasterQueueUI()
    end

    if self.isScanning or not self.blasterQueue or #self.blasterQueue == 0 or self.blasterQueue[1].skipped or self.blasterQueue[1].readyForRescan then
        if self.BlasterWindow and self.BlasterWindow.BlastButton then
            self.BlasterWindow.BlastButton:Disable()
            self.BlasterWindow.SkipButton:Disable()
        end
        if not self.isScanning then
            self:UnregisterBlasterEvents()
        end
        if self.currentBlasterSession then
            if self.currentBlasterSession.totalPosts > 0 then
                 self:PrintBlasterSummary()
            else
                 self:SetBlasterStatus("No items to post. Right-click skipped items to set a price.", {1, 0.8, 0, 1})
            end
        end
        return
    end
    
    if not self.isScanning then
        self:RegisterBlasterEvents()
    end
    AL.blasterAPIRetryCount = (AL.blasterAPIRetryCount or 0) + 1
    if AL.blasterAPIRetryCount > 5 then
        self:SetBlasterStatus("Error: Max retries reached. Re-open AH.", AL.COLOR_LOSS)
        self:ResetBlasterState()
        self:UnregisterBlasterEvents()
        return
    end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:SetBlasterStatus(string.format("Waiting for API: AH not open (retry %d/5)", AL.blasterAPIRetryCount), {1, 0.8, 0, 1})
        C_Timer.After(1.5, function() if not AL.isPosting and AL.blasterQueue and #AL.blasterQueue > 0 then AL:BlastNextItem() end end)
        return
    end
    local itemToPost = self.blasterQueue[1]
    if not itemToPost then return end
    local itemLocation = ItemLocation:CreateFromBagAndSlot(itemToPost.bag, itemToPost.slot)
    if not itemLocation:IsValid() or C_Container.GetContainerItemID(itemToPost.bag, itemToPost.slot) ~= itemToPost.itemID then
        self:SetBlasterStatus(string.format("Item %s moved or missing. Re-scanning...", itemToPost.itemName), {1, 0.8, 0, 1})
        C_Timer.After(1.5, function() self:StartScan() end)
        return
    end
    self.itemBeingPosted = itemToPost
    AL.isPosting = true
    if self.BlasterWindow and self.BlasterWindow.BlastButton then
        self.BlasterWindow.BlastButton:Enable()
        self.BlasterWindow.SkipButton:Enable()
        self.BlasterWindow.ScanButton:Disable()
        self.BlasterWindow.ReloadButton:Enable()
    end
    self:SetBlasterStatus(string.format("Ready to post %s for %s. Click Blast!", itemToPost.itemName, AL:FormatGoldWithIcons(itemToPost.postPrice * itemToPost.quantity)), {0.5, 0.8, 1.0, 1.0})
    AL.blasterAPIRetryCount = 0
end

function AL:RestoreAuctionHouseState()
    if not AL.savedAuctionHouseState or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        AL.savedAuctionHouseState = nil
        return
    end
    local savedState = AL.savedAuctionHouseState
    C_Timer.After(0.3, function()
        if AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SetText then
            AuctionHouseFrame.SearchBar:SetText(savedState.searchText or "")
            if AuctionHouseFrame.SearchBar.ClearFocus then
                AuctionHouseFrame.SearchBar:ClearFocus()
            end
        end
        if savedState.currentTab and AuctionHouseFrame.displayMode then
            if savedState.currentTab == AuctionHouseFrame.displayMode then
                if AuctionHouseFrame.BrowseResultsFrame and AuctionHouseFrame.BrowseResultsFrame.RefreshResults then
                    AuctionHouseFrame.BrowseResultsFrame:RefreshResults()
                elseif AuctionHouseFrame.FavoritesFrame and AuctionHouseFrame.FavoritesFrame.RefreshResults then
                    AuctionHouseFrame.FavoritesFrame:RefreshResults()
                end
            end
        end
        C_Timer.After(0.5, function()
            if AuctionHouseFrame.displayMode == 1 then
                AuctionHouseFrameBuyTab:Click()
            elseif AuctionHouseFrame.displayMode == 4 then
                AuctionHouseFrameBuyTab:Click()
                C_Timer.After(0.1, function()
                    if AuctionHouseFrameFavoritesTab then
                        AuctionHouseFrameFavoritesTab:Click()
                    end
                end)
            end
        end)
    end)
    AL.savedAuctionHouseState = nil
end

function AL:ResetBlasterState()
    AL.blasterAPIRetryCount = 0
    AL.isPosting = false
    AL.itemBeingPosted = nil
    AL.itemBeingScanned = nil
    AL.isScanning = false
    AL.isMarketScan = false
end
