-- Auctioneer's Ledger - GUI Core Frames
-- This file handles the initial creation and setup of the main UI frames.

-- Creates all UI frames for the addon's main window
function AL:CreateFrames()
    local frameNameSuffix = "_v" .. AL.VERSION:gsub("%.","_")
    local mainWindowName = "AL_MainWindow" .. frameNameSuffix
    
    if self.MainWindow and self.MainWindow:IsObjectType("Frame") and self.MainWindow:GetName() == mainWindowName then 
        self:UpdateLayout()
        return
    elseif self.MainWindow then
        -- Full reset of frame variables
        self.MainWindow,self.LeftPanel,self.CreateReminderButton,self.RefreshListButton,self.HelpWindowButton,self.ToggleMinimapButton,self.SupportMeButton,self.ColumnHeaderFrame,self.ScrollFrame,self.ScrollChild,self.ReminderPopup=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
        self.WarbandStockTab, self.AuctionFinancesTab, self.VendorFinancesTab, self.AuctionPricingTab, self.AuctionSettingsTab = nil, nil, nil, nil, nil
        self.NukeLedgerButton, self.NukeHistoryButton = nil, nil
        self.SortAlphaButton, self.SortItemNameFlatButton, self.SortBagsButton, self.SortBankButton, self.SortMailButton, self.SortAuctionButton, self.SortLimboButton = nil,nil,nil,nil,nil,nil,nil
        self.SortCharacterButton, self.SortRealmButton = nil, nil
        self.LabelSortBy, self.LabelFilterLocation, self.LabelFilterQuality, self.LabelFilterLedger, self.LabelFilterStackability = nil, nil, nil, nil, nil
        wipe(AL.SortQualityButtons) 
        wipe(AL.StackFilterButtons)
        wipe(AL.mainDividers)
    end

    local f=CreateFrame("Frame", mainWindowName, UIParent,"BasicFrameTemplateWithInset")
    self.MainWindow=f
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(false)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(1000)
    f.TitleText:SetText(AL.ADDON_NAME .. " (v" .. AL.VERSION .. ")")
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(s,b)if b=="LeftButton"then s:StartMoving() end end)
    f:SetScript("OnDragStop",function(s) s:StopMovingOrSizing()
        local x,y = s:GetLeft(), UIParent:GetHeight()-s:GetTop()
        if _G.AL_SavedData.Settings and _G.AL_SavedData.Settings.window then
            _G.AL_SavedData.Settings.window.x = x
            _G.AL_SavedData.Settings.window.y = y
        end
    end)
    f.CloseButton:SetScript("OnClick", function() AL:ToggleMainWindow() end)

    self.WarbandStockTab = AL.createTabButton(f, "WarbandStock", "Warband Stock", AL.VIEW_WARBAND_STOCK, frameNameSuffix)
    self.AuctionFinancesTab = AL.createTabButton(f, "AuctionFinances", "Auction Finances", AL.VIEW_AUCTION_FINANCES, frameNameSuffix)
    self.VendorFinancesTab = AL.createTabButton(f, "VendorFinances", "Vendor Finances", AL.VIEW_VENDOR_FINANCES, frameNameSuffix)
    self.AuctionPricingTab = AL.createTabButton(f, "AuctionPricing", "Auction Pricing", AL.VIEW_AUCTION_PRICING, frameNameSuffix)
    self.AuctionSettingsTab = AL.createTabButton(f, "AuctionSettings", "Auction Settings", AL.VIEW_AUCTION_SETTINGS, frameNameSuffix)

    self.NukeLedgerButton = CreateFrame("Button", "AL_NukeLedgerButton" .. frameNameSuffix, f, "UIPanelButtonTemplate")
    self.NukeLedgerButton:SetText("Nuke Ledger")
    self.NukeLedgerButton:SetScript("OnClick", function() StaticPopup_Show("AL_CONFIRM_NUKE_LEDGER") end)
    
    self.NukeHistoryButton = CreateFrame("Button", "AL_NukeHistoryButton" .. frameNameSuffix, f, "UIPanelButtonTemplate")
    self.NukeHistoryButton:SetText("Nuke History")
    self.NukeHistoryButton:SetScript("OnClick", function() StaticPopup_Show("AL_CONFIRM_NUKE_HISTORY") end)

    -- BUG FIX: Create the LeftPanel using a template that includes backdrop support.
    local lp=CreateFrame("Frame","AL_LeftPanel" .. frameNameSuffix, self.MainWindow, "BackdropTemplate")
    self.LeftPanel=lp
    lp:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    lp:SetBackdropColor(0.15,0.15,0.2,0.9)

    self.CreateReminderButton = AL.createLeftPanelButton(lp, "CreateReminder", "Track New Item", function() AL:ShowReminderPopup() end, false, frameNameSuffix)
    self.RefreshListButton = AL.createLeftPanelButton(lp, "RefreshList", "Refresh List", function() AL:RefreshLedgerDisplay() end, false, frameNameSuffix)
    self.HelpWindowButton = AL.createLeftPanelButton(lp, "HelpWindow", "How To Use", function() AL:ToggleHelpWindow() end, false, frameNameSuffix)
    self.ToggleMinimapButton = AL.createLeftPanelButton(lp, "ToggleMinimap", "Toggle Minimap Icon", function()
        _G.AL_SavedData.Settings.minimapIcon.hide = not _G.AL_SavedData.Settings.minimapIcon.hide
        if AL.LibDBIcon_Lib then
            if _G.AL_SavedData.Settings.minimapIcon.hide then AL.LibDBIcon_Lib:Hide(AL.LDB_PREFIX) else AL.LibDBIcon_Lib:Show(AL.LDB_PREFIX) end
        end
    end, false, frameNameSuffix)
    self.SupportMeButton = AL.createLeftPanelButton(lp, "SupportMe", "Patreon", function() AL:ToggleSupportWindow() end, false, frameNameSuffix)
    self.SortAlphaButton = AL.createLeftPanelButton(lp, "SortAlpha", "Item Name (Grouped)", AL.SORT_ALPHA, true, frameNameSuffix)
    self.SortItemNameFlatButton = AL.createLeftPanelButton(lp, "SortItemNameFlat", "Item Name", AL.SORT_ITEM_NAME_FLAT, true, frameNameSuffix)
    self.SortCharacterButton = AL.createLeftPanelButton(lp, "SortCharacter", "By Character", AL.SORT_CHARACTER, true, frameNameSuffix)
    self.SortRealmButton = AL.createLeftPanelButton(lp, "SortRealm", "By Realm", AL.SORT_REALM, true, frameNameSuffix)
    self.SortBagsButton = AL.createLeftPanelButton(lp, "SortBags", "Bags First (Flat)", AL.SORT_BAGS, true, frameNameSuffix)
    self.SortBankButton = AL.createLeftPanelButton(lp, "SortBank", "Bank First (Flat)", AL.SORT_BANK, true, frameNameSuffix)
    self.SortMailButton = AL.createLeftPanelButton(lp, "SortMail", "Mail First (Flat)", AL.SORT_MAIL, true, frameNameSuffix)
    self.SortAuctionButton = AL.createLeftPanelButton(lp, "SortAuction", "Auction First (Flat)", AL.SORT_AUCTION, true, frameNameSuffix)
    self.SortLimboButton = AL.createLeftPanelButton(lp, "SortLimbo", "Limbo First (Flat)", AL.SORT_LIMBO, true, frameNameSuffix)

    local qualities = {{label = "Poor", value = 0}, {label = "Common", value = 1}, {label = "Uncommon", value = 2}, {label = "Rare", value = 3}, {label = "Epic", value = 4}, {label = "Legendary+", value = 5}}
    for i, qualityInfo in ipairs(qualities) do
        local color = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualityInfo.value] and ITEM_QUALITY_COLORS[qualityInfo.value].hex) or "|cffffffff"
        table.insert(self.SortQualityButtons, AL.createLeftPanelButton(lp, "SortQuality"..qualityInfo.value, color..qualityInfo.label.."|r", AL.SORT_QUALITY_PREFIX .. qualityInfo.value, true, frameNameSuffix))
    end
    table.insert(self.SortQualityButtons, AL.createLeftPanelButton(lp, "ClearQualityFilter", "All Qualities", AL.SORT_QUALITY_PREFIX .. "-1", true, frameNameSuffix))

    table.insert(self.StackFilterButtons, AL.createLeftPanelButton(lp, "FilterStackable", "Stackable", AL.FILTER_STACK_PREFIX .. AL.FILTER_STACKABLE, true, frameNameSuffix))
    table.insert(self.StackFilterButtons, AL.createLeftPanelButton(lp, "FilterNonStackable", "Non-Stackable", AL.FILTER_STACK_PREFIX .. AL.FILTER_NONSTACKABLE, true, frameNameSuffix))
    table.insert(self.StackFilterButtons, AL.createLeftPanelButton(lp, "FilterAllStacks", "All Items", AL.FILTER_STACK_PREFIX .. AL.FILTER_ALL_STACKS, true, frameNameSuffix))

    self.LabelSortBy = AL.createLabelFrame(lp, "LabelSortBy", frameNameSuffix)
    self.LabelFilterLocation = AL.createLabelFrame(lp, "LabelFilterLocation", frameNameSuffix)
    self.LabelFilterQuality = AL.createLabelFrame(lp, "LabelFilterQuality", frameNameSuffix)
    self.LabelFilterLedger = AL.createLabelFrame(lp, "LabelFilterLedger", frameNameSuffix)
    self.LabelFilterStackability = AL.createLabelFrame(lp, "LabelFilterStackability", frameNameSuffix)

    -- BUG FIX: Create the Header using a template that includes backdrop support.
    local headerFrame=CreateFrame("Frame","AL_ColumnHeaderFrame" .. frameNameSuffix,self.MainWindow, "BackdropTemplate")
    self.ColumnHeaderFrame=headerFrame
    headerFrame:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background", edgeSize=0, tile=true, tileSize=16, insets = {left=0,right=0,top=0,bottom=0}})
    headerFrame:SetBackdropBorderColor(0,0,0,0)
    headerFrame:SetBackdropColor(0.1,0.1,0.12,0.0)
    headerFrame:SetFrameLevel(AL.MainWindow:GetFrameLevel() + 2)
    
    headerFrame.NameHFS=AL.CreateHeaderText(headerFrame,"_NameHFS","Item / Name","CENTER")
    headerFrame.LocationHFS=AL.CreateHeaderText(headerFrame,"_LocationHFS","Location","CENTER")
    headerFrame.OwnedHFS=AL.CreateHeaderText(headerFrame,"_OwnedHFS","Owned","CENTER")
    headerFrame.NotesHFS=AL.CreateHeaderText(headerFrame,"_NotesHFS","Notes","CENTER")
    headerFrame.locCharacterHFS=AL.CreateHeaderText(headerFrame,"_locCharacterHFS","Character","CENTER")
    headerFrame.locRealmHFS=AL.CreateHeaderText(headerFrame,"_locRealmHFS","Realm","CENTER")
    headerFrame.ActionsHFS=AL.CreateHeaderText(headerFrame,"_ActionsHFS","Delete","CENTER")
    
    -- Finance Headers
    headerFrame.finCharacterHFS = AL.CreateHeaderText(headerFrame, "_finCharacterHFS", "Character", "CENTER")
    headerFrame.finRealmHFS = AL.CreateHeaderText(headerFrame, "_finRealmHFS", "Realm", "CENTER")
    headerFrame.finTotalBoughtHFS = AL.CreateHeaderText(headerFrame, "_finTotalBoughtHFS", "Total Bought", "CENTER")
    headerFrame.finTotalSoldHFS = AL.CreateHeaderText(headerFrame, "_finTotalSoldHFS", "Total Sold", "CENTER")
    headerFrame.finTotalProfitHFS = AL.CreateHeaderText(headerFrame, "_finTotalProfitHFS", "Total Profit", "CENTER")
    headerFrame.finTotalLossHFS = AL.CreateHeaderText(headerFrame, "_finTotalLossHFS", "Total Loss", "CENTER")
    
    -- Auction Pricing Headers
    headerFrame.apCharacterHFS = AL.CreateHeaderText(headerFrame, "_apCharacterHFS", "Character", "CENTER"); headerFrame.apRealmHFS = AL.CreateHeaderText(headerFrame, "_apRealmHFS", "Realm", "CENTER"); headerFrame.apAllowAutoPricingHFS = AL.CreateHeaderText(headerFrame, "_apAllowAutoPricingHFS", "Allow Auto-Pricing", "CENTER"); headerFrame.safetyNetBuyoutHFS = AL.CreateHeaderText(headerFrame, "_SafetyNetBuyoutHFS", "Safety Net Buyout", "CENTER"); headerFrame.normalBuyoutPriceHFS = AL.CreateHeaderText(headerFrame, "_NormalBuyoutPriceHFS", "Normal Buyout Price", "CENTER"); headerFrame.undercutAmountHFS = AL.CreateHeaderText(headerFrame, "_UndercutAmountHFS", "Undercut Amount", "CENTER")
    
    -- Auction Settings Headers
    headerFrame.asCharacterHFS = AL.CreateHeaderText(headerFrame, "_asCharacterHFS", "Character", "CENTER"); headerFrame.asRealmHFS = AL.CreateHeaderText(headerFrame, "_asRealmHFS", "Realm", "CENTER"); headerFrame.asDurationHFS = AL.CreateHeaderText(headerFrame, "_asDurationHFS", "Duration", "CENTER"); headerFrame.asStackableHFS = AL.CreateHeaderText(headerFrame, "_asStackableHFS", "Stackable", "CENTER"); headerFrame.asQuantityHFS = AL.CreateHeaderText(headerFrame, "_asQuantityHFS", "Quantity", "CENTER")

    local sf=CreateFrame("ScrollFrame","AL_ItemScrollFrame" .. frameNameSuffix,self.MainWindow,"UIPanelScrollFrameTemplate")
    self.ScrollFrame=sf
    self.ScrollFrame:SetFrameLevel(AL.MainWindow:GetFrameLevel() + 2)
    local sc=CreateFrame("Frame","AL_ItemScrollChild" .. frameNameSuffix,sf)
    self.ScrollChild=sc
    sc:SetSize(100,10)
    sf:SetScrollChild(sc)
end
