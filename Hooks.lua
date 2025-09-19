-- Auctioneer's Ledger - Financial Tracker
-- This file contains all the secure hooks for tracking financial transactions

local AL = _G.AL or {}
_G.AL = AL

AL.recentlyViewedItems = {}
AL.pendingItem = nil
AL.pendingCost = nil
AL.isPrintingFromAddon = false
AL.purchaseMessageHandled = false

function AL:HandleOnUpdate(frame, elapsed)
    -- Tooltip caching logic: records the last 20 items you mouse over.
    if GameTooltip:IsVisible() then
        local name, link = GameTooltip:GetItem()
        if name and link then
            -- Avoid adding the same item repeatedly if the mouse doesn't move.
            if #AL.recentlyViewedItems > 0 and AL.recentlyViewedItems[#AL.recentlyViewedItems].link == link then
                return
            end
            table.insert(AL.recentlyViewedItems, {name = name, link = link, time = GetTime()})
            -- Keep the cache from growing indefinitely.
            if #AL.recentlyViewedItems > 20 then
                table.remove(AL.recentlyViewedItems, 1)
            end
        end
    end
end

function AL:TryToMatchEvents()
    if not AL.pendingCost then 
        return 
    end

    local itemToProcess = nil
    local purchaseProcessed = false

    -- The new logic no longer uses time. It relies on the tooltip cache.
    -- If a chat message arrived, we use its name and quantity for accuracy.
    if AL.pendingItem then
        -- We have a name from the chat message, find the matching link in the cache.
        for i = #AL.recentlyViewedItems, 1, -1 do
            local cachedItem = AL.recentlyViewedItems[i]
            if cachedItem.name == AL.pendingItem.name then
                itemToProcess = AL.pendingItem
                itemToProcess.link = cachedItem.link -- Get the reliable link from the cache.
                break
            end
        end
    else
        -- No chat message yet. Assume the last item moused over is the one purchased.
        if #AL.recentlyViewedItems > 0 then
            local lastViewedItem = AL.recentlyViewedItems[#AL.recentlyViewedItems]
            itemToProcess = {
                name = lastViewedItem.name,
                link = lastViewedItem.link,
                quantity = 1, -- We have to assume 1 since we don't have chat info.
                time = lastViewedItem.time
            }
        end
    end

    if itemToProcess and itemToProcess.link then
        AL:ProcessPurchase(
            itemToProcess.name,
            itemToProcess.link,
            itemToProcess.quantity,
            AL.pendingCost.cost
        )
        purchaseProcessed = true
    end

    if purchaseProcessed then
        -- A successful purchase was processed. Clear everything to be ready for the next one.
        AL.pendingItem = nil
        AL.pendingCost = nil
        wipe(AL.recentlyViewedItems)
    end
end

function AL:HandlePurchaseMessage(message, source)
    if AL.isPrintingFromAddon then return end

    if message and string.find(message, "You won an auction for") then
        local itemName
        -- The item link from chat can be unreliable, so we primarily want the name and quantity.
        local itemLinkInMsg = string.match(message, "(|Hitem.-|h%[.-%]|h)") or string.match(message, "(|Hitem.-|h.+|h)")
        
        if itemLinkInMsg then
            itemName = string.match(itemLinkInMsg, "%[(.-)%]")
        else
            itemName = string.match(message, "You won an auction for ([^%(]+)")
        end

        if itemName then
            itemName = itemName:gsub("%s+$", "")
            
            AL.pendingItem = {
                name = itemName,
                link = itemLinkInMsg, -- Store the link, but we will prefer the one from the cache.
                quantity = tonumber(string.match(message, "%(x(%d+)%)") or "1"),
                time = GetTime()
            }
            AL:TryToMatchEvents()
        end
    end
end

function AL:BuildSalesCache()
    wipe(self.salesItemCache)
    wipe(self.salesPendingAuctionCache)
    if _G.AL_SavedData and _G.AL_SavedData.Items then
        for itemID, itemData in pairs(_G.AL_SavedData.Items) do
            if itemData and itemData.itemName then
                self.salesItemCache[itemData.itemName] = { itemID = tonumber(itemID), itemLink = itemData.itemLink }
            end
        end
    end
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    local pendingAuctions = _G.AL_SavedData.PendingAuctions and _G.AL_SavedData.PendingAuctions[charKey]
    if pendingAuctions then
        for i, auctionData in ipairs(pendingAuctions) do
            local itemID = self:GetItemIDFromLink(auctionData.itemLink)
            if itemID then
                if not self.salesPendingAuctionCache[itemID] then
                    self.salesPendingAuctionCache[itemID] = {}
                end
                table.insert(self.salesPendingAuctionCache[itemID], { originalIndex = i, data = auctionData })
            end
        end
    end
end

function AL:ProcessInboxForSales()
    self:BuildSalesCache()

    local numItems = GetInboxNumItems()
    if numItems == 0 then return end
    
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    local pendingAuctions = _G.AL_SavedData.PendingAuctions and _G.AL_SavedData.PendingAuctions[charKey]
    local itemsByName = self.salesItemCache
    local pendingByID = self.salesPendingAuctionCache
    local didUpdate = false
    local indicesToRemove = {}

    for i = 1, numItems do
        local _, _, sender, subject, money, _, _, _, _, _, textCreated = GetInboxHeaderInfo(i)
        local invoiceType, itemNameFromInvoice = GetInboxInvoiceInfo(i)
        local mailKey = sender .. subject .. tostring(money) .. tostring(textCreated or 0) .. tostring(itemNameFromInvoice or "")
        
        if _G.AuctioneersLedgerFinances and _G.AuctioneersLedgerFinances.processedMailIDs and not _G.AuctioneersLedgerFinances.processedMailIDs[mailKey] and invoiceType == "seller" and money > 0 then
            if itemNameFromInvoice then
                local itemName = itemNameFromInvoice:gsub("%s+$", "")
                
                local itemInfo = itemsByName[itemName]
                if itemInfo then
                    local itemID = itemInfo.itemID
                    local originalValue = math.floor((money / 0.95) + 0.5)
                    local matchedIndex, bestMatchArrayIndex = nil, nil
                    local candidates = pendingByID and pendingByID[itemID]
                    
                    if candidates and #candidates > 0 then
                        local smallestDiff = math.huge
                        for c_idx, candidate in ipairs(candidates) do
                            if candidate and candidate.data and candidate.data.totalValue then
                                local diff = math.abs(candidate.data.totalValue - originalValue)
                                if diff < smallestDiff then
                                    smallestDiff, matchedIndex, bestMatchArrayIndex = diff, candidate.originalIndex, c_idx
                                end
                            end
                        end
                        if smallestDiff > 1 then
                            matchedIndex = nil 
                        end
                    end

                    local quantity, itemLink, soldAuctionData
                    if matchedIndex then
                        soldAuctionData = pendingAuctions and pendingAuctions[matchedIndex]
                        if soldAuctionData then
                            quantity = soldAuctionData.quantity
                            itemLink = soldAuctionData.itemLink
                        end
                    end

                    if not quantity then
                        local qtyFromSubject = subject and tonumber(string.match(subject, "%((%d+)%)"))
                        if qtyFromSubject then
                            quantity = qtyFromSubject
                        else
                            quantity = 1
                        end
                    end
                    
                    if not itemLink then
                        itemLink = itemInfo.itemLink
                    end

                    local depositFee = 0
                    if matchedIndex and pendingAuctions and pendingAuctions[matchedIndex] then
                        local matchedAuctionData = pendingAuctions[matchedIndex]
                        if matchedAuctionData and matchedAuctionData.depositFee then
                            depositFee = matchedAuctionData.depositFee
                        end
                    end

                    self:RecordTransaction("SELL", "AUCTION", itemID, money, quantity)
                    self:AddToHistory("sales", { itemLink = itemLink, itemName = itemName, quantity = quantity, price = money, depositFee = depositFee, totalValue = originalValue, timestamp = time() })
                    
                    _G.AuctioneersLedgerFinances.processedMailIDs[mailKey] = true
                    didUpdate = true

                    if matchedIndex then
                        table.insert(indicesToRemove, matchedIndex)
                        if bestMatchArrayIndex and candidates then
                            table.remove(candidates, bestMatchArrayIndex)
                        end
                    end
                end
            end
        end
    end

    if #indicesToRemove > 0 then
        table.sort(indicesToRemove, function(a, b) return a > b end)
        if pendingAuctions then
            for _, index in ipairs(indicesToRemove) do
                table.remove(pendingAuctions, index)
            end
        end
    end

    if didUpdate and self.BlasterWindow and self.BlasterWindow:IsShown() then
        self:RefreshBlasterHistory()
    end
end

function AL:InitializeCoreHooks()
    if self.coreHooksInitialized then return end
    
    for i = 1, 7 do
        local frameName = "ChatFrame" .. i
        local frame = _G[frameName]
        if frame and frame.AddMessage then
            hooksecurefunc(frame, "AddMessage", function(self, message, ...)
                AL:HandlePurchaseMessage(message, frameName)
            end)
        end
    end
    
    hooksecurefunc(UIErrorsFrame, "AddMessage", function(self, message, ...)
        AL:HandlePurchaseMessage(message, "UIErrorsFrame")
    end)
    
    hooksecurefunc("TakeInboxItem", function(mailIndex, attachmentIndex)
        local _, _, _, subject = GetInboxHeaderInfo(mailIndex)
        if subject and (subject:find("expired") or subject:find("Expired")) then
            local itemLink = GetInboxItemLink(mailIndex, attachmentIndex)
            if itemLink then
                local itemID = self:GetItemIDFromLink(itemLink)
                local _, _, itemCount = GetInboxItem(mailIndex, attachmentIndex)
                if itemID and itemCount then
                    local charKey = UnitName("player") .. "-" .. GetRealmName()
                    local pendingAuctions = _G.AL_SavedData.PendingAuctions and _G.AL_SavedData.PendingAuctions[charKey]
                    if pendingAuctions then
                         for idx = #pendingAuctions, 1, -1 do
                            local auctionData = pendingAuctions[idx]
                            if self:GetItemIDFromLink(auctionData.itemLink) == itemID and auctionData.quantity == itemCount then
                                local removedAuction = table.remove(pendingAuctions, idx)
                                local reliableItemLink = removedAuction.itemLink
                                local itemName = reliableItemLink and GetItemInfo(reliableItemLink)
                                self:RecordTransaction("DEPOSIT", "AUCTION", itemID, removedAuction.depositFee or 0, removedAuction.quantity)
                                self:AddToHistory("cancellations", { itemName = itemName or "Unknown", itemLink = reliableItemLink, quantity = removedAuction.quantity, price = removedAuction.depositFee or 0, timestamp = time() })
                                self:RefreshBlasterHistory()
                                self:BuildSalesCache()
                                break
                            end
                        end
                    end
                end
            end
        end
    end)
    self.coreHooksInitialized = true
end

function AL:InitializeAuctionHooks()
    if self.auctionHooksInitialized then return end
    local function cachePendingPost(itemLocation, quantity, duration, postPrice, isCommodity)
        if not itemLocation or not itemLocation:IsValid() then return end
        local itemID, itemLink = C_Container.GetContainerItemID(itemLocation:GetBagAndSlot()), C_Container.GetContainerItemLink(itemLocation:GetBagAndSlot())
        if itemID and itemLink then
            local depositFee = isCommodity and C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity) or C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity)
            AL.pendingPostDetails = { itemID = itemID, itemLink = itemLink, quantity = quantity or 1, duration = duration, postPrice = postPrice, depositFee = depositFee }
            AL:RecordTransaction("DEPOSIT", "AUCTION", itemID, depositFee, quantity)
        end
    end
    if C_AuctionHouse and C_AuctionHouse.PostItem then
        hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity, bid, buyout)
            local pricePer = buyout and buyout > 0 and quantity > 0 and (buyout / quantity) or 0
            cachePendingPost(itemLocation, quantity, duration, pricePer, false)
        end)
    end
    if C_AuctionHouse and C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity, unitPrice)
            cachePendingPost(itemLocation, quantity, duration, unitPrice, true)
        end)
    end
    
    -- SURGICAL ADDITION: Hook the standard CancelAuction function to track manual cancellations.
    if C_AuctionHouse and C_AuctionHouse.CancelAuction then
        hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID)
            -- If the Blaster already processed this, do nothing.
            if AL.cancellationProcessedForID and AL.cancellationProcessedForID == auctionID then
                AL.cancellationProcessedForID = nil -- Reset the flag
                return
            end

            -- Find the full auction details from the list of owned auctions.
            local allOwnedAuctions = C_AuctionHouse.GetOwnedAuctions()
            local auctionInfoToCancel = nil
            if allOwnedAuctions then
                for _, auction in ipairs(allOwnedAuctions) do
                    if auction.auctionID == auctionID then
                        auctionInfoToCancel = auction
                        break
                    end
                end
            end

            -- If we found the auction, process it using our centralized function.
            if auctionInfoToCancel then
                -- SURGICAL FIX: The object from GetOwnedAuctions() does not contain the itemLink.
                -- We must add it manually before processing to prevent an error.
                if not auctionInfoToCancel.itemLink and auctionInfoToCancel.itemKey and auctionInfoToCancel.itemKey.itemID then
                    local _, link = GetItemInfo(auctionInfoToCancel.itemKey.itemID)
                    auctionInfoToCancel.itemLink = link
                end
                AL:ProcessAuctionCancellation(auctionInfoToCancel)
            end
        end)
    end
    
    self.auctionHooksInitialized = true
end

function AL:InitializeVendorHooks()
    if self.vendorHooksInitialized then return end

    local function handleVendorPurchase(itemLink, itemID, price, quantity)
        if not itemLink or not itemID or not price or price <= 0 or not quantity or quantity <= 0 then
            return
        end
        
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        local isTracked = _G.AL_SavedData.Items and _G.AL_SavedData.Items[itemID] and _G.AL_SavedData.Items[itemID].characters[charKey]
        
        if isTracked then
            AL:RecordTransaction("BUY", "VENDOR", itemID, price, quantity)
        else
            -- RETAIL CHANGE: Check setting before showing popup
            if _G.AL_SavedData and _G.AL_SavedData.Settings and _G.AL_SavedData.Settings.autoAddNewItems then
                local success, msg = AL:InternalAddItem(itemLink, UnitName("player"), GetRealmName())
                if success then
                    AL:RecordTransaction("BUY", "VENDOR", itemID, price, quantity)
                    AL:RefreshLedgerDisplay()
                end
            else
                local name = GetItemInfo(itemLink)
                if not name then return end

                local popupData = { itemLink = itemLink, itemID = itemID, price = price, quantity = quantity }
                StaticPopup_Show("AL_CONFIRM_TRACK_NEW_VENDOR_PURCHASE", name, nil, popupData)
            end
        end
    end

    hooksecurefunc("BuyMerchantItem", function(index, quantity)
        -- [[ DIRECTIVE: Set flag to identify this as a vendor purchase ]]
        AL.isVendorPurchase = true
        
        if not index then return end
        
        local itemLink = GetMerchantItemLink(index)
        if not itemLink then return end
        
        local itemID = AL:GetItemIDFromLink(itemLink)
        local _, _, price, numInStack = GetMerchantItemInfo(index)

        if itemID and price and price > 0 then
            local itemsToBuy = quantity or 1
            local stackSize = numInStack or 1
            
            local pricePerItem = price
            if stackSize > 1 then
                pricePerItem = price / stackSize
            end

            local totalPrice = math.floor(pricePerItem * itemsToBuy)
            handleVendorPurchase(itemLink, itemID, totalPrice, itemsToBuy)
        end
    end)
    
    self.vendorHooksInitialized = true
end

function AL:InitializeTradeHooks()
    -- Trade hooks are not relevant to this financial restructure.
end

function AL:GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    return tonumber(itemLink:match("item:(%d+)"))
end

