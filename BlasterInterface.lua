-- BlasterInterface.lua
-- This file contains the UI creation and management for the Blaster feature.

-- ============================================================================
-- UI STATUS MANAGEMENT
-- ============================================================================

function AL:SetBlasterStatus(text, color)
    if self.BlasterWindow and self.BlasterWindow.StatusText then
        local status = self.BlasterWindow.StatusText
        status:SetText(text or "")
        status:SetTextColor(unpack(color or {1, 1, 1, 1}))
        status:Show()
    end
end

function AL:EnableBlasterButtons()
    if AL.BlasterWindow then
        AL.BlasterWindow.ScanButton:Enable()
        AL.BlasterWindow.BlastButton:Disable()
        AL.BlasterWindow.SkipButton:Disable()
        AL.BlasterWindow.ReloadButton:Enable()
        AL.BlasterWindow.AutoPricingButton:Enable()
        AL.BlasterWindow.CancelUndercutButton:Enable()
    end
end

function AL:RefreshBlasterQueue()
    if self.scanFailsafeTimer then self.scanFailsafeTimer:Cancel(); self.scanFailsafeTimer = nil end
    if self.postFailureTimer then self.postFailureTimer:Cancel(); self.postFailureTimer = nil end
    AL.savedAuctionHouseState = nil
    self:ResetBlasterState()
    
    -- [[ FIX: Explicitly reset cancel-scan state on refresh ]]
    -- This ensures that clicking "Refresh" provides a completely clean slate for all
    -- Blaster operations, including any pending cancellation actions.
    self.isCancelScanning = false
    self.isCancelling = false
    self.auctionsToCancel = {}
    -- [[ END FIX ]]

    self.blasterQueue = {}
    self:RenderBlasterQueueUI()
    AL:EnableBlasterButtons()
    AL:SetBlasterStatus("Queue cleared. Ready to scan.")
    
    -- SURGICAL CHANGE: Ensure the cancel buttons are reset to their default state on refresh.
    if AL.BlasterWindow then
        if AL.BlasterWindow.CancelUndercutButton then AL.BlasterWindow.CancelUndercutButton:Show() end
        if AL.BlasterWindow.CancelNextButton then 
            AL.BlasterWindow.CancelNextButton:Hide() 
            AL.BlasterWindow.CancelNextButton:Disable()
            AL.BlasterWindow.CancelNextButton:SetText("Cancel Next (0)")
        end
    end
end

function AL:HideBlasterWindow()
    if self.BlasterWindow then
        if self.scanFailsafeTimer then self.scanFailsafeTimer:Cancel(); self.scanFailsafeTimer = nil end
        if self.postFailureTimer then self.postFailureTimer:Cancel(); self.postFailureTimer = nil end
        self:UnregisterBlasterEvents()
        AL.originalBrowseResults = nil
        self:ResetBlasterState()
        self.BlasterWindow:Hide()
        if self.BlasterWindow.HistoryContainer then
            self.BlasterWindow.HistoryContainer:Hide()
        end
    end
end

function AL:ToggleBlasterWindow()
    if self.BlasterWindow and self.BlasterWindow:IsShown() then
        self:HideBlasterWindow()
    else
        self:ShowBlasterWindow()
    end
end

function AL:RenderBlasterQueueUI()
    if not self.BlasterWindow or not self.blasterQueue then return end
    local container = self.BlasterWindow.QueueScrollChild
    if not self.BlasterWindow.QueueItemButtons then self.BlasterWindow.QueueItemButtons = {} end
    for _, btn in ipairs(self.BlasterWindow.QueueItemButtons) do btn:Hide() end
    wipe(self.BlasterWindow.QueueItemButtons)
    local itemSize = 32
    local padding = 6
    local itemsPerRow = 4
    local containerWidth = container:GetWidth()
    local totalItemWidth = itemsPerRow * itemSize + (itemsPerRow - 1) * padding
    local xStartOffset = (containerWidth - totalItemWidth) / 2
    for i, itemData in ipairs(self.blasterQueue) do
        local row = math.floor((i-1) / itemsPerRow)
        local col = (i-1) % itemsPerRow
        local xOffset = xStartOffset + col * (itemSize + padding)
        local yOffset = padding + row * (itemSize + padding)
        local button = CreateFrame("Button", "AL_BlasterQueueButton" .. i, container)
        table.insert(self.BlasterWindow.QueueItemButtons, button)
        button:SetSize(itemSize, itemSize)
        button:SetPoint("TOPLEFT", xOffset, -yOffset)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(true)
        icon:SetTexture(itemData.icon)
        
        if itemData.readyForRescan then
            local rescanIndicator = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            rescanIndicator:SetPoint("CENTER", 0, 0)
            rescanIndicator:SetText("!")
            rescanIndicator:SetTextColor(1, 0.82, 0, 1) -- Gold color
            rescanIndicator:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
            
            button:SetScript("OnEnter", function(self_button)
                GameTooltip:SetOwner(self_button, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemData.itemLink)
                GameTooltip:AddLine("This item has been recently changed and is ready to be rescanned and blasted.", 1, 1, 1, true)
                
                -- SURGICAL CHANGE: Add vendor price information to the tooltip.
                local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemData.itemLink)
                if vendorPrice and vendorPrice > 0 then
                    local totalVendorPrice = vendorPrice * itemData.quantity
                    GameTooltip:AddLine(" ") -- Add a spacer line for readability
                    GameTooltip:AddLine(string.format("Vendor Sell: %s (%s total)", C_CurrencyInfo.GetCoinTextureString(vendorPrice), C_CurrencyInfo.GetCoinTextureString(totalVendorPrice)))
                end
                -- END SURGICAL CHANGE

                GameTooltip:Show()
            end)
        elseif itemData.skipped then
            local skipIndicator = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            skipIndicator:SetPoint("CENTER", 0, 0)
            skipIndicator:SetText("?")
            skipIndicator:SetTextColor(1, 0, 0, 1)
            skipIndicator:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
            
            button:SetScript("OnMouseUp", function(self, mouseButton)
                if mouseButton == "RightButton" then
                    AL:ShowPriceEntryPopup(itemData)
                end
            end)
            
            button:SetScript("OnEnter", function(self_button)
                GameTooltip:SetOwner(self_button, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemData.itemLink)
                GameTooltip:AddLine(string.format("|cffff0000SKIPPED:|r %s", itemData.skipReason or "Unknown reason"), 1, 1, 1, true)
                GameTooltip:AddLine("Right-click to set a price.", 0.6, 0.8, 1, true)
                
                -- SURGICAL CHANGE: Add vendor price information to the tooltip.
                local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemData.itemLink)
                if vendorPrice and vendorPrice > 0 then
                    local totalVendorPrice = vendorPrice * itemData.quantity
                    GameTooltip:AddLine(" ") -- Add a spacer line for readability
                    GameTooltip:AddLine(string.format("Vendor Sell: %s (%s total)", C_CurrencyInfo.GetCoinTextureString(vendorPrice), C_CurrencyInfo.GetCoinTextureString(totalVendorPrice)))
                end
                -- END SURGICAL CHANGE

                GameTooltip:Show()
            end)
        else
             button:SetScript("OnEnter", function(self_button)
                GameTooltip:SetOwner(self_button, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemData.itemLink)
                local durationHours
                if itemData.duration == 1 then durationHours = 12
                elseif itemData.duration == 2 then durationHours = 24
                elseif itemData.duration == 3 then durationHours = 48
                else durationHours = (itemData.durationMinutes or 720) / 60 end
                GameTooltip:AddLine(string.format("Post %d for ~%s each (%dh)", itemData.quantity, GetCoinTextureString(itemData.postPrice), durationHours))
                if itemData.undercutInfo then
                    GameTooltip:AddLine(string.format("|cff87ceebUndercutting %s by %s|r", GetCoinTextureString(itemData.undercutInfo.undercuttingPrice), GetCoinTextureString(itemData.undercutInfo.undercutAmount)), 1, 1, 1, true)
                end
                
                -- SURGICAL CHANGE: Add vendor price information to the tooltip.
                local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemData.itemLink)
                if vendorPrice and vendorPrice > 0 then
                    local totalVendorPrice = vendorPrice * itemData.quantity
                    GameTooltip:AddLine(" ") -- Add a spacer line for readability
                    GameTooltip:AddLine(string.format("Vendor Sell: %s (%s total)", C_CurrencyInfo.GetCoinTextureString(vendorPrice), C_CurrencyInfo.GetCoinTextureString(totalVendorPrice)))
                end
                -- END SURGICAL CHANGE

                GameTooltip:Show()
            end)
        end

        local countFS = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        countFS:SetPoint("BOTTOMRIGHT", -2, 2)
        countFS:SetText(itemData.quantity)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local totalRows = math.ceil(#self.blasterQueue / itemsPerRow)
    local requiredHeight = math.max(totalRows * (itemSize + padding) + padding, container:GetParent():GetHeight())
    container:SetHeight(requiredHeight)
end

function AL:ShowBlasterWindow()
    if not self.BlasterWindow or not self.BlasterWindow:IsObjectType("Frame") then
        self:CreateBlasterWindow()
    end
    if self.BlasterWindow then
        self.BlasterWindow:Show()
        if self.BlasterWindow.HistoryContainer then
            self.BlasterWindow.HistoryContainer:Show()
        end
        self:RefreshBlasterQueue()
    end
end

-- ============================================================================
-- SECURE ACTION FUNCTIONS & UI
-- ============================================================================

function AL:SetupBlastButton(blastButton)
    blastButton:SetScript("OnClick", function(self_button)
        self_button:Disable()
        local itemToPost = AL.itemBeingPosted
        if not itemToPost then
            AL:SetBlasterStatus("Error: No item ready to post", AL.COLOR_LOSS)
            self_button:Enable()
            return
        end
        
        local itemLocation = ItemLocation:CreateFromBagAndSlot(itemToPost.bag, itemToPost.slot)
        if not itemLocation:IsValid() or C_Container.GetContainerItemID(itemToPost.bag, itemToPost.slot) ~= itemToPost.itemID then
            AL:HandlePostFailure("Item changed or missing")
            return
        end
        
        if not C_AuctionHouse.IsThrottledMessageSystemReady() then
            AL:SetBlasterStatus("Auction House not ready, retrying...", {1, 1, 0, 1})
            C_Timer.After(2.0, function() if AL.itemBeingPosted then self_button:Enable() end end)
            return
        end
        
        AL:SetPostFailureTimer()
        local isCommodity = AL:IsItemACommodity(itemLocation)
        AL:SetBlasterStatus(string.format("Posting %s...", itemToPost.itemName), {1, 1, 0, 1})
        
        AL.pendingPostDetails = { 
            itemID = itemToPost.itemID, itemLink = itemToPost.itemLink,
            quantity = itemToPost.quantity, duration = itemToPost.duration,
            postPrice = itemToPost.postPrice -- Ensure postPrice is carried over
        }

        local success, needsConfirmationOrError
        if isCommodity then
            success, needsConfirmationOrError = pcall(C_AuctionHouse.PostCommodity, itemLocation, itemToPost.duration, itemToPost.quantity, itemToPost.postPrice)
            if not success then
                AL:HandlePostFailure("PostCommodity Error: " .. tostring(needsConfirmationOrError))
                return
            end
            if needsConfirmationOrError then
                C_AuctionHouse.ConfirmPostCommodity(itemLocation, itemToPost.duration, itemToPost.quantity, itemToPost.postPrice)
            end
        else
            local totalBuyout = itemToPost.postPrice * itemToPost.quantity
            success, needsConfirmationOrError = pcall(C_AuctionHouse.PostItem, itemLocation, itemToPost.duration, itemToPost.quantity, nil, totalBuyout)
            if not success then
                AL:HandlePostFailure("PostItem Error: " .. tostring(needsConfirmationOrError))
                return
            end
            if needsConfirmationOrError then
                C_AuctionHouse.ConfirmPostItem(itemLocation, itemToPost.duration, itemToPost.quantity, nil, totalBuyout)
            end
        end
    end)
end

function AL:CreatePriceEntryPopup()
    if self.PriceEntryPopup then return end
    local p = CreateFrame("Frame", "AL_PriceEntryPopup", UIParent, "BasicFrameTemplateWithInset")
    self.PriceEntryPopup = p
    p:SetSize(280, 180)
    p:SetFrameStrata("HIGH")
    p:SetFrameLevel(20)
    p:SetMovable(true)
    p:EnableMouse(true) 
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self) self:StartMoving() end)
    p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    p.TitleText:SetText("Set Normal Buyout Price")
    p.CloseButton:SetScript("OnClick", function() p:Hide() end)

    local instruction = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    instruction:SetPoint("TOP", 0, -30)
    instruction:SetWidth(p:GetWidth() - 40)
    instruction:SetText("This item has no active competitors, or your safety net conditions are blocking it from being added to the blaster queue. Please verify the price before proceeding.")
    p.Instruction = instruction

    local moneyInput = self:CreateMoneyInput(p, 0, 0, 0, "quickPrice", 0, "", "")
    moneyInput.container:ClearAllPoints()
    moneyInput.container:SetPoint("TOP", instruction, "BOTTOM", 0, -10)
    p.MoneyInput = moneyInput

    local disclaimer = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    disclaimer:SetPoint("TOP", moneyInput.container, "BOTTOM", 0, -10)
    disclaimer:SetTextColor(0.8, 0.8, 0.8)
    disclaimer:SetText("Safety Net will be set to 70% of this value.")
    
    local saveButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    saveButton:SetSize(100, 25)
    saveButton:SetText("Save")
    saveButton:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -5, 10)
    p.SaveButton = saveButton

    local cancelButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 25)
    cancelButton:SetText("Cancel")
    cancelButton:SetPoint("BOTTOMLEFT", p, "BOTTOM", 5, 10)
    cancelButton:SetScript("OnClick", function() p:Hide() end)
    
    p:Hide()
end

function AL:ShowPriceEntryPopup(itemData)
    if not self.PriceEntryPopup then self:CreatePriceEntryPopup() end
    local p = self.PriceEntryPopup
    
    p.MoneyInput.goldEB:SetText("0")
    p.MoneyInput.silverEB:SetText("00")

    p.SaveButton:SetScript("OnClick", function()
        local g = p.MoneyInput.goldEB:GetText()
        local s = p.MoneyInput.silverEB:GetText()
        local normalPrice = AL:CombineGSCToCopper(g, s, "0")
        
        if normalPrice > 0 then
            local safetyNetPrice = math.floor(normalPrice * 0.7)
            local pricingInfo = AL.PricingData[itemData.itemID]
            if pricingInfo and pricingInfo.charKey then
                local charName, realmName = strsplit("-", pricingInfo.charKey)
                AL:SavePricingValue(itemData.itemID, charName, realmName, "normalBuyoutPrice", normalPrice)
                AL:SavePricingValue(itemData.itemID, charName, realmName, "safetyNetBuyout", safetyNetPrice)
                
                for _, item in ipairs(AL.blasterQueue) do
                    if item.itemID == itemData.itemID then
                        item.skipped = false
                        item.readyForRescan = true
                        item.postPrice = normalPrice
                        break
                    end
                end
                
                p:Hide()
                AL:RenderBlasterQueueUI()
            end
        end
    end)

    p:ClearAllPoints()
    p:SetPoint("CENTER")
    p:Show()
    p:Raise()
end

function AL:CreateBlasterWindow()
    if self.BlasterWindow then return end
    local f = CreateFrame("Frame", "AL_BlasterWindow_v" .. self.VERSION:gsub("%.", "_"), UIParent, "BasicFrameTemplateWithInset")
    self.BlasterWindow = f
    f:SetSize(AL.BLASTER_WINDOW_WIDTH, AL.BLASTER_WINDOW_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f.TitleText:SetText("AL Blaster")
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() self:HideBlasterWindow() end) end
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function(self) self:StartMoving() end); f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local logo = f:CreateTexture(nil, "ARTWORK"); logo:SetSize(AL.BLASTER_LOGO_WIDTH, AL.BLASTER_LOGO_HEIGHT); logo:SetTexture(AL.BLASTER_LOGO_PATH); logo:SetPoint("TOP", f, "TOP", 0, -30)
    local statusText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal"); statusText:SetPoint("TOP", logo, "BOTTOM", 0, -10); statusText:SetJustifyH("CENTER"); statusText:SetWidth(f:GetWidth() - 40); f.StatusText = statusText
    
    local lowerContent = CreateFrame("Frame", nil, f)
    lowerContent:SetPoint("TOP", logo, "BOTTOM", 0, -40) 
    lowerContent:SetPoint("LEFT", f, "LEFT")
    lowerContent:SetPoint("RIGHT", f, "RIGHT")
    lowerContent:SetPoint("BOTTOM", f, "BOTTOM")

    local queueWidth = AL.BLASTER_LOGO_WIDTH / 1.85; local queueHeight = AL.BLASTER_LOGO_HEIGHT / 1.2
    local queueBackdrop = CreateFrame("Frame", nil, lowerContent, "BackdropTemplate"); 
    queueBackdrop:SetSize(queueWidth, queueHeight); 
    
    queueBackdrop:SetPoint("TOPLEFT", lowerContent, "TOPLEFT", 13, -60)
    
    queueBackdrop:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }); queueBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.9); queueBackdrop:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local queueScroll = CreateFrame("ScrollFrame", "AL_BlasterQueueScrollFrame", queueBackdrop, "UIPanelScrollFrameTemplate"); queueScroll:SetPoint("TOPLEFT", 8, -8); queueScroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local queueScrollChild = CreateFrame("Frame", "AL_BlasterQueueScrollChild", queueScroll); queueScrollChild:SetWidth(queueScroll:GetWidth()); queueScroll:SetScrollChild(queueScrollChild); f.QueueScrollChild = queueScrollChild; f.QueueItemButtons = {}
    local buttonPanel = CreateFrame("Frame", nil, lowerContent); buttonPanel:SetSize(180, queueHeight); buttonPanel:SetPoint("LEFT", queueBackdrop, "RIGHT", 10, 0)
    
    local scanButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.ScanButton = scanButton
    local blastButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.BlastButton = blastButton
    local skipButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.SkipButton = skipButton
    local reloadButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.ReloadButton = reloadButton
    local autoPricingButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.AutoPricingButton = autoPricingButton
    local cancelUndercutButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.CancelUndercutButton = cancelUndercutButton
    local cancelNextButton = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate"); f.CancelNextButton = cancelNextButton

    scanButton:SetText("Scan Inventory"); scanButton:SetScript("OnClick", function() AL:StartScan() end)
    blastButton:SetText("Blast!"); blastButton:Disable(); self:SetupBlastButton(blastButton)
    skipButton:SetText("Skip"); skipButton:Disable(); skipButton:SetScript("OnClick", function() self:SkipQueueItem() end)
    reloadButton:SetText("Refresh"); reloadButton:SetScript("OnClick", function() self:RefreshBlasterQueue() end)
    autoPricingButton:SetText("Auto Pricing"); autoPricingButton:SetScript("OnClick", function() self:StartMarketPriceScan() end)
    -- SURGICAL CHANGE: The OnClick for this button now starts the scan directly.
    cancelUndercutButton:SetText("Cancel Undercut"); cancelUndercutButton:SetScript("OnClick", function() AL:StartCancelScan() end)
    cancelNextButton:SetText("Cancel Next (0)"); cancelNextButton:SetScript("OnClick", function() AL:CancelSingleUndercutAuction() end); cancelNextButton:Hide(); cancelNextButton:Disable()
    
    local buttons = {scanButton, blastButton, skipButton, reloadButton, autoPricingButton, cancelUndercutButton}
    local buttonHeight = 28
    local buttonSpacing = 2
    local numButtons = #buttons
    local totalButtonHeight = (numButtons * buttonHeight) + ((numButtons - 1) * buttonSpacing)
    local startY = -((queueHeight - totalButtonHeight) / 2)

    for i, button in ipairs(buttons) do
        button:SetSize(AL.BLASTER_BUTTON_WIDTH or 140, buttonHeight)
        button:ClearAllPoints()
        if i == 1 then
            button:SetPoint("TOP", buttonPanel, "TOP", 0, startY)
        else
            button:SetPoint("TOP", buttons[i-1], "BOTTOM", 0, -buttonSpacing)
        end
    end

    cancelNextButton:SetAllPoints(cancelUndercutButton)

    self:AttachBlasterHistory(f)
end
