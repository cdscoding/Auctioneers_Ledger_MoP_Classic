-- GUI_BlasterHistory.lua
-- This file handles the creation and management of the Blaster's history panel.

function AL:CreateHistoryRow(parent, yOffset, data, isEven, historyType)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth(), AL.BLASTER_HISTORY_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -yOffset)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(unpack(isEven and AL.ROW_COLOR_EVEN or AL.ROW_COLOR_ODD))

    local effectiveItemLink = data.itemLink
    if not effectiveItemLink and data.itemName and AL.salesItemCache and AL.salesItemCache[data.itemName] then
        effectiveItemLink = AL.salesItemCache[data.itemName].itemLink
    end

    local currentX = AL.COL_PADDING

    -- Column 1: Icon & Name
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(AL.ITEM_ICON_SIZE, AL.ITEM_ICON_SIZE)
    icon:SetPoint("LEFT", currentX, 0)
    
    local nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormalTiny")
    nameFS:SetPoint("LEFT", icon, "RIGHT", AL.ICON_TEXT_PADDING, 0)
    nameFS:SetSize(AL.BH_COL_ICON_AND_NAME_WIDTH - AL.ITEM_ICON_SIZE - AL.ICON_TEXT_PADDING, AL.BLASTER_HISTORY_ROW_HEIGHT)
    nameFS:SetJustifyH("LEFT")
    currentX = currentX + AL.BH_COL_ICON_AND_NAME_WIDTH + AL.COL_PADDING

    if effectiveItemLink then
        local _, itemIcon, itemRarity = GetItemInfo(effectiveItemLink)
        icon:SetTexture(itemIcon or "Interface\\Icons\\inv_misc_questionmark")
        nameFS:SetText(effectiveItemLink)
        row:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(effectiveItemLink); GameTooltip:Show() end)
        row:SetScript("OnLeave", function(s) GameTooltip:Hide() end)
    else
        icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
        local r, g, b = GetItemQualityColor(0) 
        local displayName = data.itemName or "Invalid Item Data" 
        nameFS:SetText(string.format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, displayName))
        
        if data.itemName then
            row:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetText(data.itemName, r, g, b); GameTooltip:Show() end)
            row:SetScript("OnLeave", function(s) GameTooltip:Hide() end)
        else
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
        end
    end

    -- Column 2: Quantity
    local qtyFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormalTiny")
    qtyFS:SetPoint("LEFT", row, "LEFT", currentX, 0)
    qtyFS:SetSize(AL.BH_COL_QTY_WIDTH, AL.BLASTER_HISTORY_ROW_HEIGHT)
    qtyFS:SetJustifyH("CENTER")
    qtyFS:SetText("x"..tostring(data.quantity or 1))
    currentX = currentX + AL.BH_COL_QTY_WIDTH + AL.COL_PADDING

    -- Column 3: Price / Status
    local priceFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormalTiny")
    priceFS:SetPoint("LEFT", row, "LEFT", currentX, 0)
    priceFS:SetSize(AL.BH_COL_PRICE_WIDTH, AL.BLASTER_HISTORY_ROW_HEIGHT)
    priceFS:SetJustifyH("CENTER")
    currentX = currentX + AL.BH_COL_PRICE_WIDTH + AL.COL_PADDING
    
    if historyType == "cancellations" then
        priceFS:SetText(string.format("|cffff3333%s|r", self:FormatGoldAndSilverRoundedUp(data.price or 0)))
    elseif historyType == "posts" then
        priceFS:SetText(string.format("|cff33ff33%s|r / |cffff3333%s|r", self:FormatGoldAndSilverRoundedUp(data.totalValue or 0), self:FormatGoldAndSilverRoundedUp(data.price or 0)))
    elseif historyType == "sales" then
        priceFS:SetTextColor(unpack(AL.COLOR_PROFIT))
        local totalRefund = (data.price or 0) + (data.depositFee or 0)
        priceFS:SetText(self:FormatGoldAndSilverRoundedUp(totalRefund))
    elseif historyType == "purchases" then
        priceFS:SetTextColor(unpack(AL.COLOR_LOSS))
        priceFS:SetText(self:FormatGoldAndSilverRoundedUp(data.pricePerItem or 0))
    else
        priceFS:SetText(self:FormatGoldAndSilverRoundedUp(data.price or 0))
    end

    -- Column 4: Timestamp
    local dateFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormalTiny")
    dateFS:SetPoint("LEFT", row, "LEFT", currentX, 0)
    dateFS:SetSize(AL.BH_COL_DATE_WIDTH, AL.BLASTER_HISTORY_ROW_HEIGHT)
    dateFS:SetJustifyH("CENTER")
    dateFS:SetText(date("%m/%d", data.timestamp or 0))

    return row
end

function AL:PopulateHistoryPanel(blasterFrame, historyType)
    local panel, scrollChild
    if historyType == "posts" then panel, scrollChild = blasterFrame.HistoryPostsPanel, blasterFrame.HistoryPostsScrollChild
    elseif historyType == "sales" then panel, scrollChild = blasterFrame.HistorySalesPanel, blasterFrame.HistorySalesScrollChild
    elseif historyType == "purchases" then panel, scrollChild = blasterFrame.HistoryPurchasePanel, blasterFrame.HistoryPurchaseScrollChild
    elseif historyType == "cancellations" then panel, scrollChild = blasterFrame.HistoryCancelPanel, blasterFrame.HistoryCancelScrollChild
    else return end

    if not panel or not scrollChild then return end

    if scrollChild.rows then
        for _, row in ipairs(scrollChild.rows) do row:Hide() end
        wipe(scrollChild.rows)
    else
        scrollChild.rows = {}
    end
    
    local yOffset = 0
    local historyData = _G.AuctioneersLedgerFinances and _G.AuctioneersLedgerFinances[historyType]
    
    if historyData then
        for i = #historyData, 1, -1 do
            local data = historyData[i]
            local isEven = (#scrollChild.rows % 2 == 0)
            local rowFrame = self:CreateHistoryRow(scrollChild, yOffset, data, isEven, historyType)
            table.insert(scrollChild.rows, rowFrame)
            yOffset = yOffset + AL.BLASTER_HISTORY_ROW_HEIGHT
        end
    end
    
    scrollChild:SetHeight(math.max(panel:GetHeight(), yOffset))
end

function AL:RefreshBlasterHistory()
    if not self.BlasterWindow or not self.BlasterWindow:IsShown() then return end
    if not self.BlasterWindow.activeHistoryPanel then return end
    self:PopulateHistoryPanel(self.BlasterWindow, self.BlasterWindow.activeHistoryPanel)
end

function AL:CreateBlasterHistoryFrames(parent)
    local historyContainer = CreateFrame("Frame", "AL_BlasterHistoryContainer", parent)
    historyContainer:SetPoint("TOPLEFT", parent, "TOPRIGHT", AL.BLASTER_HISTORY_PANEL_X_OFFSET, -25)
    historyContainer:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", AL.BLASTER_HISTORY_PANEL_X_OFFSET, 0)
    historyContainer:SetWidth(AL.BLASTER_HISTORY_PANEL_WIDTH)
    parent.HistoryContainer = historyContainer

    local tabs = {
        {name="Posts", type="posts"}, {name="Sales", type="sales"},
        {name="Purchases", type="purchases"}, {name="Cancellations", type="cancellations"}
    }
    local lastTab
    local firstTab
    for i, tabInfo in ipairs(tabs) do
        local tab = CreateFrame("Button", "AL_BlasterHistory"..tabInfo.name.."Tab", historyContainer, "UIPanelButtonTemplate")
        tab:SetSize(AL.BLASTER_HISTORY_TAB_WIDTH, AL.BLASTER_HISTORY_TAB_HEIGHT)
        tab:SetText(tabInfo.name)
        
        if i == 1 then
            tab:SetPoint("TOPLEFT", historyContainer, "TOPLEFT", 5, 0)
            firstTab = tab
        else
            tab:SetPoint("LEFT", lastTab, "RIGHT", AL.BLASTER_HISTORY_TAB_SPACING, 0)
        end
        
        tab:SetScript("OnClick", function() AL:ShowBlasterHistoryPanel(parent, tabInfo.type) end)
        
        parent["History"..tabInfo.name.."Tab"] = tab
        lastTab = tab
    end

    local displayBackdrop = CreateFrame("Frame", "AL_BlasterHistoryDisplayBackdrop", historyContainer, "BackdropTemplate")
    if firstTab then
        displayBackdrop:SetPoint("TOPLEFT", firstTab, "BOTTOMLEFT", 0, -AL.BLASTER_HISTORY_TAB_SPACING)
    else
        displayBackdrop:SetPoint("TOPLEFT", historyContainer, "TOPLEFT", 5, -AL.BLASTER_HISTORY_TAB_HEIGHT - AL.BLASTER_HISTORY_TAB_SPACING)
    end
    displayBackdrop:SetPoint("BOTTOMRIGHT", historyContainer, "BOTTOMRIGHT", -5, 5)
    displayBackdrop:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 1, right = 1, top = 1, bottom = 1 }})
    displayBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    parent.HistoryDisplayBackdrop = displayBackdrop
    
    local headerFrame = CreateFrame("Frame", "AL_BlasterHistoryHeader", displayBackdrop)
    headerFrame:SetPoint("TOPLEFT", 2, -2)
    headerFrame:SetPoint("TOPRIGHT", -2, -2)
    headerFrame:SetHeight(AL.COLUMN_HEADER_HEIGHT)
    parent.HistoryHeader = headerFrame

    headerFrame.NameHFS = AL.CreateHeaderText(headerFrame, "_NameHFS", "Item", "CENTER")
    headerFrame.QtyHFS = AL.CreateHeaderText(headerFrame, "_QtyHFS", "Qty", "CENTER")
    headerFrame.PriceHFS = AL.CreateHeaderText(headerFrame, "_PriceHFS", "Price", "CENTER")
    headerFrame.DateHFS = AL.CreateHeaderText(headerFrame, "_DateHFS", "Date", "CENTER")

    parent.HistoryDividers = {}
    for i=1, 3 do
        local div = CreateFrame("Frame", nil, displayBackdrop)
        if BackdropTemplateMixin then Mixin(div, BackdropTemplateMixin) end
        div:SetWidth(AL.DIVIDER_THICKNESS)
        div:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"})
        div:SetBackdropColor(unpack(AL.WINDOW_DIVIDER_COLOR))
        div:SetPoint("TOP", headerFrame, "TOP", 0, 0)
        div:SetPoint("BOTTOM", displayBackdrop, "BOTTOM", 0, 0)
        table.insert(parent.HistoryDividers, div)
    end

    local function createHistoryPanel(name, backdropParent, mainBlasterFrame)
        local panel = CreateFrame("ScrollFrame", "AL_Blaster" .. name .. "Panel", backdropParent, "UIPanelScrollFrameTemplate")
        panel:SetPoint("TOPLEFT", 2, -2 - AL.COLUMN_HEADER_HEIGHT); panel:SetPoint("BOTTOMRIGHT", -2, 2)
        local scrollChild = CreateFrame("Frame", "AL_Blaster" .. name .. "ScrollChild", panel)
        scrollChild:SetWidth(panel:GetWidth())
        panel:SetScrollChild(scrollChild)
        panel:Hide()
        mainBlasterFrame["History" .. name .. "Panel"] = panel
        mainBlasterFrame["History" .. name .. "ScrollChild"] = scrollChild
    end

    createHistoryPanel("Posts", displayBackdrop, parent)
    createHistoryPanel("Sales", displayBackdrop, parent)
    createHistoryPanel("Purchase", displayBackdrop, parent)
    createHistoryPanel("Cancel", displayBackdrop, parent)
end

function AL:ShowBlasterHistoryPanel(blasterFrame, panelType)
    blasterFrame.activeHistoryPanel = panelType
    
    local panels = {blasterFrame.HistoryPostsPanel, blasterFrame.HistorySalesPanel, blasterFrame.HistoryPurchasePanel, blasterFrame.HistoryCancelPanel}
    for _, p in ipairs(panels) do if p then p:Hide() end end

    local tabs = {
        {frame=blasterFrame.HistoryPostsTab, type="posts"}, {frame=blasterFrame.HistorySalesTab, type="sales"},
        {frame=blasterFrame.HistoryPurchasesTab, type="purchases"}, {frame=blasterFrame.HistoryCancellationsTab, type="cancellations"}
    }
    for _, t in ipairs(tabs) do
        if t.frame and t.frame:IsObjectType("Button") then
            local isActive = (t.type == panelType)
            if isActive then
                t.frame:SetNormalTexture("Interface\\Buttons\\UI-Panel-Tab-Highlight")
                t.frame:GetFontString():SetTextColor(unpack(AL.LABEL_TEXT_COLOR))
            else
                t.frame:SetNormalTexture("Interface\\Buttons\\UI-Panel-Tab")
                t.frame:GetFontString():SetTextColor(unpack(AL.COLOR_TAB_INACTIVE_TEXT))
            end
        end
    end
    
    -- [[ DIRECTIVE: Update column headers for clarity ]]
    if panelType == "posts" then blasterFrame.HistoryPostsPanel:Show(); blasterFrame.HistoryHeader.PriceHFS:SetText("Value / Deposit Fee")
    elseif panelType == "sales" then blasterFrame.HistorySalesPanel:Show(); blasterFrame.HistoryHeader.PriceHFS:SetText("Net Sale + Fee Refund")
    elseif panelType == "purchases" then blasterFrame.HistoryPurchasePanel:Show(); blasterFrame.HistoryHeader.PriceHFS:SetText("Price Per")
    elseif panelType == "cancellations" then blasterFrame.HistoryCancelPanel:Show(); blasterFrame.HistoryHeader.PriceHFS:SetText("Lost Deposit")
    end
    
    local header = blasterFrame.HistoryHeader
    local currentX = AL.COL_PADDING
    header.NameHFS:SetPoint("LEFT", header, "LEFT", currentX, 0); header.NameHFS:SetWidth(AL.BH_COL_ICON_AND_NAME_WIDTH); currentX = currentX + AL.BH_COL_ICON_AND_NAME_WIDTH + AL.COL_PADDING
    blasterFrame.HistoryDividers[1]:SetPoint("LEFT", header, "LEFT", currentX - (AL.COL_PADDING/2), 0)
    
    header.QtyHFS:SetPoint("LEFT", header, "LEFT", currentX, 0); header.QtyHFS:SetWidth(AL.BH_COL_QTY_WIDTH); currentX = currentX + AL.BH_COL_QTY_WIDTH + AL.COL_PADDING
    blasterFrame.HistoryDividers[2]:SetPoint("LEFT", header, "LEFT", currentX - (AL.COL_PADDING/2), 0)

    header.PriceHFS:SetPoint("LEFT", header, "LEFT", currentX, 0); header.PriceHFS:SetWidth(AL.BH_COL_PRICE_WIDTH); currentX = currentX + AL.BH_COL_PRICE_WIDTH + AL.COL_PADDING
    blasterFrame.HistoryDividers[3]:SetPoint("LEFT", header, "LEFT", currentX - (AL.COL_PADDING/2), 0)

    header.DateHFS:SetPoint("LEFT", header, "LEFT", currentX, 0); header.DateHFS:SetWidth(AL.BH_COL_DATE_WIDTH)

    self:PopulateHistoryPanel(blasterFrame, panelType)
end

function AL:AttachBlasterHistory(blasterFrame)
    if not blasterFrame.HistoryContainer then
        self:CreateBlasterHistoryFrames(blasterFrame)
    end
    blasterFrame.HistoryContainer:Show()
    self:ShowBlasterHistoryPanel(blasterFrame, "posts")
end
