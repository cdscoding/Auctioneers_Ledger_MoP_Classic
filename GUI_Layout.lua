-- Auctioneer's Ledger - GUI Layout
-- This file handles the dynamic positioning and visibility of major UI elements.

function AL:UpdateButtonStates()
    if not self or not self.LeftPanel or not self.LeftPanel:IsShown() then return end
    
    local currentFilters = _G.AL_SavedData.Settings.filterSettings[AL.currentActiveTab]
    if not currentFilters then return end

    local function UpdateGroup(buttons, activeCriteria, comparisonFunc)
        if not buttons or #buttons == 0 then return end
        for _, button in ipairs(buttons) do
            if button and button.SetChecked and button.criteria then
                local isChecked = comparisonFunc(button.criteria, activeCriteria)
                button:SetChecked(isChecked)
                if button.selectedHighlight then
                    if isChecked then button.selectedHighlight:Show() else button.selectedHighlight:Hide() end
                end
            end
        end
    end

    local visibleSortButtons = {}
    if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then
        -- MoP Change: Removed Warband/Reagent bank buttons from visible list
        visibleSortButtons = {self.SortAlphaButton, self.SortCharacterButton, self.SortRealmButton, self.SortBagsButton, self.SortBankButton, self.SortMailButton, self.SortAuctionButton}
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES or AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES then
        visibleSortButtons = {self.SortItemNameFlatButton, self.SortCharacterButton, self.SortRealmButton}
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_PRICING or AL.currentActiveTab == AL.VIEW_AUCTION_SETTINGS then
        visibleSortButtons = {self.SortItemNameFlatButton, self.SortCharacterButton, self.SortRealmButton}
    end
    UpdateGroup(visibleSortButtons, currentFilters.sort, function(a, b) return a == b end)

    UpdateGroup(AL.SortQualityButtons, currentFilters.quality, function(btnCrit, activeCrit)
        local qualityValue = tonumber(string.sub(btnCrit, #AL.SORT_QUALITY_PREFIX + 1))
        if qualityValue == -1 then return activeCrit == nil else return activeCrit == qualityValue end
    end)

    UpdateGroup(AL.StackFilterButtons, currentFilters.stack, function(btnCrit, activeCrit)
        local filterType = string.sub(btnCrit, #AL.FILTER_STACK_PREFIX + 1)
        if filterType == AL.FILTER_ALL_STACKS then return activeCrit == nil else return activeCrit == filterType end
    end)
end

function AL:UpdateLayout()
    if not self.MainWindow then return end
    local frameNameSuffix = "_v" .. AL.VERSION:gsub("%.","_")
    local topInset, bottomInset, sideInset = 28, 8, 8

    local titleText = AL.ADDON_NAME .. " (v" .. AL.VERSION .. ")"
    if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then titleText = titleText .. " - Warband Stock"
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES then titleText = titleText .. " - Auction Finances"
    elseif AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES then titleText = titleText .. " - Vendor Finances"
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_PRICING then titleText = titleText .. " - Auction Pricing"
	elseif AL.currentActiveTab == AL.VIEW_AUCTION_SETTINGS then titleText = titleText .. " - Auction Settings"
    end
    self.MainWindow.TitleText:SetText(titleText)

    if self.MainWindow.TitleText then
        self.MainWindow.TitleText:ClearAllPoints()
        self.MainWindow.TitleText:SetPoint("TOP", self.MainWindow, "TOP", 0, -4)
    end

    local tabTop = -topInset + AL.TAB_TOP_OFFSET
    local tabLeft = sideInset + AL.TAB_HORIZONTAL_POSITION_OFFSET
	
    local function setTabAppearance(tab, isActive)
        if tab then
            if isActive then
                tab:SetNormalTexture("Interface\\Buttons\\UI-Panel-Tab-Highlight")
                tab:GetFontString():SetTextColor(unpack(AL.LABEL_TEXT_COLOR))
            else
                tab:SetNormalTexture("Interface\\Buttons\\UI-Panel-Tab")
                tab:GetFontString():SetTextColor(unpack(AL.COLOR_TAB_INACTIVE_TEXT))
            end
        end
    end

    local tabs = {
        { frame = self.WarbandStockTab, view = AL.VIEW_WARBAND_STOCK },
        { frame = self.AuctionFinancesTab, view = AL.VIEW_AUCTION_FINANCES },
        { frame = self.VendorFinancesTab, view = AL.VIEW_VENDOR_FINANCES },
        { frame = self.AuctionPricingTab, view = AL.VIEW_AUCTION_PRICING },
        { frame = self.AuctionSettingsTab, view = AL.VIEW_AUCTION_SETTINGS }
    }

    local lastTabFrame
    for i, tabInfo in ipairs(tabs) do
        local tabFrame = tabInfo.frame
        if tabFrame then
            tabFrame:ClearAllPoints()
            tabFrame:SetSize(AL.TAB_BUTTON_WIDTH, AL.TAB_BUTTON_HEIGHT)
            if i == 1 then
                tabFrame:SetPoint("TOPLEFT", self.MainWindow, "TOPLEFT", tabLeft, tabTop)
            else
                tabFrame:SetPoint("LEFT", lastTabFrame, "RIGHT", AL.TAB_BUTTON_SPACING, 0)
            end
            setTabAppearance(tabFrame, AL.currentActiveTab == tabInfo.view)
            lastTabFrame = tabFrame
        end
    end

    -- RETAIL CHANGE: Position the Nuke buttons and new checkbox
    if self.NukeHistoryButton then
        self.NukeHistoryButton:SetSize(100, 22)
        self.NukeHistoryButton:SetPoint("TOPRIGHT", self.MainWindow, "TOPRIGHT", -sideInset, tabTop)
    end
    if self.NukeLedgerButton then
        self.NukeLedgerButton:SetSize(100, 22)
        self.NukeLedgerButton:SetPoint("TOPRIGHT", self.NukeHistoryButton, "TOPLEFT", -AL.BUTTON_SPACING, 0)
    end
    if self.AutoAddNewItemsCheckButton then
        self.AutoAddNewItemsCheckButton:SetPoint("RIGHT", self.NukeLedgerButton, "LEFT", -AL.BUTTON_SPACING * 42, 0)
        local shouldBeChecked = _G.AL_SavedData.Settings and _G.AL_SavedData.Settings.autoAddNewItems
        self.AutoAddNewItemsCheckButton:SetChecked(shouldBeChecked)
    end

    local contentTopY = tabTop + AL.TAB_BUTTON_HEIGHT + AL.COL_PADDING + AL.MAIN_CONTENT_VERTICAL_OFFSET_ADJUSTMENT

    if self.LeftPanel then
        self.LeftPanel:ClearAllPoints()
        self.LeftPanel:SetPoint("TOPLEFT", self.MainWindow, "TOPLEFT", sideInset, contentTopY)
        self.LeftPanel:SetPoint("BOTTOMLEFT", self.MainWindow, "BOTTOMLEFT", sideInset, bottomInset)
        self.LeftPanel:SetWidth(AL.LEFT_PANEL_WIDTH)

        local currentButtonY = -AL.BUTTON_SPACING
        local allButtons = {
            self.CreateReminderButton, self.RefreshListButton, self.HelpWindowButton, self.ToggleMinimapButton, 
            self.SupportMeButton, self.SortAlphaButton, self.SortItemNameFlatButton, self.SortCharacterButton, 
            self.SortRealmButton, self.SortBagsButton, self.SortBankButton, 
            self.SortMailButton, self.SortAuctionButton, self.SortLimboButton
        }
        for _, btn in ipairs(allButtons) do if btn then btn:Hide() end end
        for _, qButton in ipairs(self.SortQualityButtons) do if qButton then qButton:Hide() end end
        for _, sButton in ipairs(self.StackFilterButtons) do if sButton then sButton:Hide() end end
        local allLabels = {self.LabelSortBy, self.LabelFilterLocation, self.LabelFilterQuality, self.LabelFilterLedger, self.LabelFilterStackability}
        for _, lbl in ipairs(allLabels) do if lbl then lbl:Hide() end end

        local buttonStructure = {}
        table.insert(buttonStructure, {type = "button", ref = self.CreateReminderButton})
        table.insert(buttonStructure, {type = "button", ref = self.RefreshListButton})
        table.insert(buttonStructure, {type = "button", ref = self.HelpWindowButton})
        table.insert(buttonStructure, {type = "button", ref = self.ToggleMinimapButton})
        table.insert(buttonStructure, {type = "button", ref = self.SupportMeButton})
        table.insert(buttonStructure, {type = "label",  refName = "LabelSortBy", text = "Sort View:"})

        if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then
            table.insert(buttonStructure, {type = "button", ref = self.SortAlphaButton}); table.insert(buttonStructure, {type = "button", ref = self.SortCharacterButton}); table.insert(buttonStructure, {type = "button", ref = self.SortRealmButton})
            table.insert(buttonStructure, {type = "label",  refName = "LabelFilterLocation", text = "Filter Location (Flat List):"})
            -- MoP Change: Removed Warband/Reagent bank buttons from layout
            table.insert(buttonStructure, {type = "button", ref = self.SortBagsButton}); table.insert(buttonStructure, {type = "button", ref = self.SortBankButton}); table.insert(buttonStructure, {type = "button", ref = self.SortMailButton}); table.insert(buttonStructure, {type = "button", ref = self.SortAuctionButton})
        elseif AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES or AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES then
            table.insert(buttonStructure, {type = "button", ref = self.SortItemNameFlatButton}); table.insert(buttonStructure, {type = "button", ref = self.SortCharacterButton}); table.insert(buttonStructure, {type = "button", ref = self.SortRealmButton})
        elseif AL.currentActiveTab == AL.VIEW_AUCTION_PRICING then
             table.insert(buttonStructure, {type = "button", ref = self.SortItemNameFlatButton}); table.insert(buttonStructure, {type = "button", ref = self.SortCharacterButton}); table.insert(buttonStructure, {type = "button", ref = self.SortRealmButton})
        elseif AL.currentActiveTab == AL.VIEW_AUCTION_SETTINGS then
            table.insert(buttonStructure, {type = "button", ref = self.SortItemNameFlatButton}); table.insert(buttonStructure, {type = "button", ref = self.SortCharacterButton}); table.insert(buttonStructure, {type = "button", ref = self.SortRealmButton})
            table.insert(buttonStructure, {type = "label",  refName = "LabelFilterStackability", text = "Filter Stackability:"})
            for _, stackButton in ipairs(AL.StackFilterButtons) do table.insert(buttonStructure, {type = "button", ref = stackButton}) end
        end

        table.insert(buttonStructure, {type = "label",  refName = "LabelFilterQuality", text = "Filter Quality:"})
        for _, qualityButton in ipairs(AL.SortQualityButtons) do table.insert(buttonStructure, {type = "button", ref = qualityButton}) end

        for _, itemDef in ipairs(buttonStructure) do
            if itemDef.type == "label" then
                local labelFrame = self[itemDef.refName]
                if labelFrame then 
                    currentButtonY = currentButtonY - (AL.BUTTON_HEIGHT / 4)
                    labelFrame:ClearAllPoints(); labelFrame.text:SetText(itemDef.text)
                    labelFrame:SetPoint("TOPLEFT", self.LeftPanel, "TOPLEFT", AL.BUTTON_SPACING, currentButtonY)
                    labelFrame:SetPoint("TOPRIGHT", self.LeftPanel, "TOPRIGHT", -AL.BUTTON_SPACING, currentButtonY)
                    labelFrame:SetHeight(AL.BUTTON_HEIGHT / 1.5 * 1.2); labelFrame.text:SetJustifyH("CENTER"); labelFrame.text:SetJustifyV("MIDDLE"); labelFrame:Show()
                    currentButtonY = currentButtonY - (AL.BUTTON_HEIGHT / 1.5 * 1.2) - AL.BUTTON_SPACING
                end
            elseif itemDef.type == "button" then
                local button = itemDef.ref
                if button then 
                    button:ClearAllPoints(); button:SetHeight(AL.BUTTON_HEIGHT)
                    button:SetPoint("TOPLEFT", self.LeftPanel, "TOPLEFT", AL.BUTTON_SPACING, currentButtonY)
                    button:SetPoint("TOPRIGHT", self.LeftPanel, "TOPRIGHT", -AL.BUTTON_SPACING, currentButtonY)
                    button:Show(); currentButtonY = currentButtonY - AL.BUTTON_HEIGHT - AL.BUTTON_SPACING
                end
            end
        end
        self:UpdateButtonStates()
    end

    local scrollContentLeftOffset = sideInset
    if self.LeftPanel and self.LeftPanel:IsShown() then scrollContentLeftOffset = sideInset + AL.LEFT_PANEL_WIDTH + AL.BUTTON_SPACING end

    if self.ColumnHeaderFrame then
        self.ColumnHeaderFrame:ClearAllPoints()
        self.ColumnHeaderFrame:SetPoint("TOPLEFT",self.MainWindow,"TOPLEFT",scrollContentLeftOffset, contentTopY)
        self.ColumnHeaderFrame:SetPoint("TOPRIGHT",self.MainWindow,"TOPRIGHT",-sideInset, contentTopY)
        self.ColumnHeaderFrame:SetHeight(AL.COLUMN_HEADER_HEIGHT)
        
        self.ColumnHeaderFrame.NameHFS:ClearAllPoints()
        self.ColumnHeaderFrame.NameHFS:SetPoint("LEFT", self.ColumnHeaderFrame, "LEFT", AL.COL_PADDING, 0)
        self.ColumnHeaderFrame.NameHFS:SetWidth(AL.EFFECTIVE_NAME_COL_WIDTH); self.ColumnHeaderFrame.NameHFS:SetJustifyH("CENTER")
        self.ColumnHeaderFrame.NameHFS:SetText("Item / Name"); self.ColumnHeaderFrame.NameHFS:Show()

        local allHeaders = {
            self.ColumnHeaderFrame.LocationHFS, self.ColumnHeaderFrame.OwnedHFS, self.ColumnHeaderFrame.NotesHFS, self.ColumnHeaderFrame.locCharacterHFS, self.ColumnHeaderFrame.locRealmHFS, self.ColumnHeaderFrame.ActionsHFS,
            self.ColumnHeaderFrame.finCharacterHFS, self.ColumnHeaderFrame.finRealmHFS, self.ColumnHeaderFrame.finTotalBoughtHFS, self.ColumnHeaderFrame.finTotalSoldHFS, self.ColumnHeaderFrame.finTotalProfitHFS, self.ColumnHeaderFrame.finTotalLossHFS,
            self.ColumnHeaderFrame.apCharacterHFS, self.ColumnHeaderFrame.apRealmHFS, self.ColumnHeaderFrame.safetyNetBuyoutHFS, self.ColumnHeaderFrame.normalBuyoutPriceHFS,
            self.ColumnHeaderFrame.undercutAmountHFS, self.ColumnHeaderFrame.asCharacterHFS, self.ColumnHeaderFrame.asRealmHFS, self.ColumnHeaderFrame.asDurationHFS, self.ColumnHeaderFrame.asStackableHFS, self.ColumnHeaderFrame.asQuantityHFS,
            self.ColumnHeaderFrame.apAllowAutoPricingHFS
        }
        for _, header in ipairs(allHeaders) do if header then header:Hide() end end
		
        local currentHeaderContentX = AL.COL_PADDING + AL.EFFECTIVE_NAME_COL_WIDTH + AL.COL_PADDING
		
        local headers_to_show = {}
        if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then
            headers_to_show = {
                {frame = self.ColumnHeaderFrame.locCharacterHFS, width = AL.STOCK_COL_CHARACTER_WIDTH}, {frame = self.ColumnHeaderFrame.locRealmHFS, width = AL.STOCK_COL_REALM_WIDTH}, {frame = self.ColumnHeaderFrame.NotesHFS, width = AL.STOCK_COL_NOTES_WIDTH},
                {frame = self.ColumnHeaderFrame.LocationHFS, width = AL.STOCK_COL_LOCATION_WIDTH}, {frame = self.ColumnHeaderFrame.OwnedHFS, width = AL.STOCK_COL_OWNED_WIDTH}, {frame = self.ColumnHeaderFrame.ActionsHFS, width = AL.STOCK_COL_DELETE_BTN_AREA_WIDTH}
            }
        elseif AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES or AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES then
            headers_to_show = {
                {frame = self.ColumnHeaderFrame.finCharacterHFS, width = AL.FIN_COL_CHARACTER_WIDTH}, {frame = self.ColumnHeaderFrame.finRealmHFS, width = AL.FIN_COL_REALM_WIDTH}, 
                {frame = self.ColumnHeaderFrame.finTotalBoughtHFS, width = AL.FIN_COL_TOTAL_BOUGHT_WIDTH}, {frame = self.ColumnHeaderFrame.finTotalSoldHFS, width = AL.FIN_COL_TOTAL_SOLD_WIDTH},
                {frame = self.ColumnHeaderFrame.finTotalProfitHFS, width = AL.FIN_COL_TOTAL_PROFIT_WIDTH}, {frame = self.ColumnHeaderFrame.finTotalLossHFS, width = AL.FIN_COL_TOTAL_LOSS_WIDTH}
            }
        elseif AL.currentActiveTab == AL.VIEW_AUCTION_PRICING then
            headers_to_show = {
                {frame = self.ColumnHeaderFrame.apCharacterHFS, width = AL.AP_COL_CHARACTER_WIDTH}, {frame = self.ColumnHeaderFrame.apRealmHFS, width = AL.AP_COL_REALM_WIDTH}, {frame = self.ColumnHeaderFrame.apAllowAutoPricingHFS, width = AL.AP_COL_ALLOW_AUTO_PRICING_WIDTH},
                {frame = self.ColumnHeaderFrame.safetyNetBuyoutHFS, width = AL.AP_COL_SAFETY_NET_WIDTH}, {frame = self.ColumnHeaderFrame.normalBuyoutPriceHFS, width = AL.AP_COL_NORMAL_BUYOUT_WIDTH}, {frame = self.ColumnHeaderFrame.undercutAmountHFS, width = AL.AP_COL_UNDERCUT_AMOUNT_WIDTH}
            }
		elseif AL.currentActiveTab == AL.VIEW_AUCTION_SETTINGS then
            headers_to_show = {
                {frame = self.ColumnHeaderFrame.asCharacterHFS, width = AL.AS_COL_CHARACTER_WIDTH}, {frame = self.ColumnHeaderFrame.asRealmHFS, width = AL.AS_COL_REALM_WIDTH}, {frame = self.ColumnHeaderFrame.asDurationHFS, width = AL.AS_COL_DURATION_WIDTH},
                {frame = self.ColumnHeaderFrame.asStackableHFS, width = AL.AS_COL_STACKABLE_WIDTH}, {frame = self.ColumnHeaderFrame.asQuantityHFS, width = AL.AS_COL_QUANTITY_WIDTH}
            }
        end
        for _, h in ipairs(headers_to_show) do h.frame:SetPoint("LEFT", self.ColumnHeaderFrame, "LEFT", currentHeaderContentX, 0); h.frame:SetWidth(h.width); h.frame:Show(); currentHeaderContentX = currentHeaderContentX + h.width + AL.COL_PADDING; end
    end
	
    if self.ScrollFrame then
        local scrollFrameTopOffset = contentTopY + AL.COLUMN_HEADER_HEIGHT + AL.SCROLL_FRAME_VERTICAL_OFFSET
        self.ScrollFrame:ClearAllPoints()
        self.ScrollFrame:SetPoint("TOPLEFT",self.MainWindow,"TOPLEFT",scrollContentLeftOffset,-scrollFrameTopOffset)
        self.ScrollFrame:SetPoint("BOTTOMRIGHT",self.MainWindow,"BOTTOMRIGHT",-sideInset,bottomInset)
        if self.ScrollChild then
            local sbw=0
            if self.ScrollChild:GetHeight()>self.ScrollFrame:GetHeight() then sbw=16 end
            
            local totalContentWidthInScrollChild = AL.COL_PADDING + AL.EFFECTIVE_NAME_COL_WIDTH + AL.COL_PADDING
            if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then
                totalContentWidthInScrollChild = totalContentWidthInScrollChild + AL.STOCK_COL_CHARACTER_WIDTH + AL.COL_PADDING + AL.STOCK_COL_REALM_WIDTH + AL.COL_PADDING + AL.STOCK_COL_NOTES_WIDTH + AL.COL_PADDING + AL.STOCK_COL_LOCATION_WIDTH + AL.COL_PADDING + AL.STOCK_COL_OWNED_WIDTH + AL.COL_PADDING + AL.STOCK_COL_DELETE_BTN_AREA_WIDTH + AL.COL_PADDING
            elseif AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES or AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES then
                totalContentWidthInScrollChild = totalContentWidthInScrollChild + AL.FIN_COL_CHARACTER_WIDTH + AL.COL_PADDING + AL.FIN_COL_REALM_WIDTH + AL.COL_PADDING + AL.FIN_COL_TOTAL_BOUGHT_WIDTH + AL.COL_PADDING + AL.FIN_COL_TOTAL_SOLD_WIDTH + AL.COL_PADDING + AL.FIN_COL_TOTAL_PROFIT_WIDTH + AL.COL_PADDING + AL.FIN_COL_TOTAL_LOSS_WIDTH + AL.COL_PADDING
            elseif AL.currentActiveTab == AL.VIEW_AUCTION_PRICING then
                totalContentWidthInScrollChild = totalContentWidthInScrollChild + AL.AP_COL_CHARACTER_WIDTH + AL.COL_PADDING + AL.AP_COL_REALM_WIDTH + AL.COL_PADDING + AL.AP_COL_ALLOW_AUTO_PRICING_WIDTH + AL.COL_PADDING + AL.AP_COL_SAFETY_NET_WIDTH + AL.COL_PADDING + AL.AP_COL_NORMAL_BUYOUT_WIDTH + AL.COL_PADDING + AL.AP_COL_UNDERCUT_AMOUNT_WIDTH + AL.COL_PADDING
            elseif AL.currentActiveTab == AL.VIEW_AUCTION_SETTINGS then
                totalContentWidthInScrollChild = totalContentWidthInScrollChild + AL.AS_COL_CHARACTER_WIDTH + AL.COL_PADDING + AL.AS_COL_REALM_WIDTH + AL.COL_PADDING + AL.AS_COL_DURATION_WIDTH + AL.COL_PADDING + AL.AS_COL_STACKABLE_WIDTH + AL.COL_PADDING + AL.AS_COL_QUANTITY_WIDTH + AL.COL_PADDING
            end

            self.ScrollChild:SetWidth(math.max(totalContentWidthInScrollChild, self.ScrollFrame:GetWidth() - sbw))
        end
    end

    for i = 1, #self.mainDividers do if self.mainDividers[i] and self.mainDividers[i]:IsObjectType("Frame") then self.mainDividers[i]:Hide() end end

    local divX_centers_abs = {}
    local currentDivXForDividers = scrollContentLeftOffset + AL.COL_PADDING
    table.insert(divX_centers_abs, currentDivXForDividers + AL.EFFECTIVE_NAME_COL_WIDTH)
    currentDivXForDividers = currentDivXForDividers + AL.EFFECTIVE_NAME_COL_WIDTH + AL.COL_PADDING

    local widths = {}
    if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then widths = {AL.STOCK_COL_CHARACTER_WIDTH, AL.STOCK_COL_REALM_WIDTH, AL.STOCK_COL_NOTES_WIDTH, AL.STOCK_COL_LOCATION_WIDTH, AL.STOCK_COL_OWNED_WIDTH, AL.STOCK_COL_DELETE_BTN_AREA_WIDTH}
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_FINANCES or AL.currentActiveTab == AL.VIEW_VENDOR_FINANCES then widths = {AL.FIN_COL_CHARACTER_WIDTH, AL.FIN_COL_REALM_WIDTH, AL.FIN_COL_TOTAL_BOUGHT_WIDTH, AL.FIN_COL_TOTAL_SOLD_WIDTH, AL.FIN_COL_TOTAL_PROFIT_WIDTH, AL.FIN_COL_TOTAL_LOSS_WIDTH}
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_PRICING then widths = {AL.AP_COL_CHARACTER_WIDTH, AL.AP_COL_REALM_WIDTH, AL.AP_COL_ALLOW_AUTO_PRICING_WIDTH, AL.AP_COL_SAFETY_NET_WIDTH, AL.AP_COL_NORMAL_BUYOUT_WIDTH, AL.AP_COL_UNDERCUT_AMOUNT_WIDTH}
    elseif AL.currentActiveTab == AL.VIEW_AUCTION_SETTINGS then widths = {AL.AS_COL_CHARACTER_WIDTH, AL.AS_COL_REALM_WIDTH, AL.AS_COL_DURATION_WIDTH, AL.AS_COL_STACKABLE_WIDTH, AL.AS_COL_QUANTITY_WIDTH}
    end

    for i=1, #widths do
        if widths[i] and widths[i] > 0 then
            table.insert(divX_centers_abs, currentDivXForDividers + widths[i])
            currentDivXForDividers = currentDivXForDividers + widths[i] + AL.COL_PADDING
        end
    end
	
    for i = 1, #divX_centers_abs -1 do
        local div = self.mainDividers[i]
        if not div then
            div = CreateFrame("Frame", "AL_MainDivider" .. i .. frameNameSuffix, self.MainWindow)
            self.mainDividers[i] = div
            -- BUG FIX: Create a texture for the backdrop manually
            div.bg = div:CreateTexture(nil, "BACKGROUND")
            div.bg:SetAllPoints(true)
        end
        div:ClearAllPoints()
        div:SetFrameLevel(self.MainWindow:GetFrameLevel() + 1)
        div:SetWidth(AL.DIVIDER_THICKNESS)
        
        -- BUG FIX: Set texture and color on the manually created texture
        div.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        div.bg:SetVertexColor(unpack(AL.WINDOW_DIVIDER_COLOR))

        div:SetPoint("TOP", self.ColumnHeaderFrame, "TOP", 0, 0)
        div:SetPoint("BOTTOM", self.ScrollFrame, "BOTTOM", 0, 0)
        div:SetPoint("LEFT", self.MainWindow, "LEFT", divX_centers_abs[i] + (AL.COL_PADDING / 2) - (AL.DIVIDER_THICKNESS / 2), 0)
        div:Show()
    end
    for i = #divX_centers_abs, #self.mainDividers do if self.mainDividers[i] then self.mainDividers[i]:Hide() end end
end
