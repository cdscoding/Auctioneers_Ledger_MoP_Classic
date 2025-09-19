-- Auctioneer's Ledger - GUI Elements
-- This file contains reusable functions for creating specific interactive UI elements.

-- Creates an editable money input field (Gold, Silver, Copper)
function AL:CreateMoneyInput(parent, xOffset, yOffset, initialValue, fieldType, itemID, characterName, realmName)
    -- Defensive checks
    characterName = characterName or ""
    realmName = realmName or ""
    initialValue = initialValue or 0
    local gsc = AL:SplitCoinToGSCTable(initialValue)

    -- Sizes and spacing
    local iconPadding = 2
    local groupPadding = 6
    local goldBoxWidth = 65
    local silverCopperBoxWidth = 25 
    local iconSize = 10

    -- Container for centering
    local moneyContainer = CreateFrame("Frame", nil, parent)
    moneyContainer:SetClipsChildren(true)
    moneyContainer.isProgrammaticallyUpdating = false

    -- This factory creates a unique, correctly-scoped handler for each row.
    -- MODIFIED: Removed copper handling.
    local function CreateCommitHandler(container, itemID, charName, rlmName, fType)
        return function(self)
            if container.isProgrammaticallyUpdating then return end
            
            local goldText = container.goldEB:GetText() == "" and "0" or container.goldEB:GetText()
            local silverText = container.silverEB:GetText() == "" and "0" or container.silverEB:GetText()

            local goldVal = tonumber(goldText) or 0
            local silverVal = tonumber(silverText) or 0
            
            AL:SavePricingValue(itemID, charName, rlmName, fType, goldVal, silverVal, 0) -- Pass 0 for copper
            
            container.isProgrammaticallyUpdating = true
            container.goldEB:SetText(goldVal)
            container.silverEB:SetText(string.format("%02d", silverVal))
            container.isProgrammaticallyUpdating = false

            if self then self:ClearFocus() end
        end
    end

    -- This handler provides a hard "full stop" on input.
    local function EnforceTextLimits(self)
        if self.isEnforcingLimits then return end 
        local max = self:GetMaxLetters()
        local currentText = self:GetText() or ""
        if max > 0 and string.len(currentText) > max then
            self.isEnforcingLimits = true 
            self:SetText(string.sub(currentText, 1, max))
            self:SetCursorPosition(max)
            self.isEnforcingLimits = false
        end
    end

    -- Definitive stateless navigation map logic
    -- MODIFIED: Removed copper from tab navigation
    local function HandleTabNavigation(self, key)
        if key ~= "TAB" then return end

        local navigationMap = {}
        local fieldOrder = { "safetyNetBuyout", "normalBuyoutPrice", "undercutAmount" }
        if AL and AL.itemRowFrames then
            for _, rowFrame in ipairs(AL.itemRowFrames) do
                if not rowFrame.isParentRow and rowFrame:IsShown() then
                    for _, fType in ipairs(fieldOrder) do
                        local inputs = rowFrame[fType .. "Inputs"]
                        if inputs and inputs.container:IsShown() then
                            table.insert(navigationMap, inputs.goldEB)
                            table.insert(navigationMap, inputs.silverEB)
                        end
                    end
                end
            end
        end

        if #navigationMap == 0 then return end

        local currentIndex
        for i, editBox in ipairs(navigationMap) do
            if editBox == self then
                currentIndex = i
                break
            end
        end
        if not currentIndex then return end
        
        local nextIndex
        if IsShiftKeyDown() then
            nextIndex = currentIndex - 1
            if nextIndex < 1 then nextIndex = #navigationMap end
        else
            nextIndex = currentIndex + 1
            if nextIndex > #navigationMap then nextIndex = 1 end
        end

        if navigationMap[nextIndex] then
            navigationMap[nextIndex]:SetFocus()
        end
    end
    
    -- Creates a custom EditBox from scratch
    local function CreateCustomEditBox(parent, width, height)
        local eb = CreateFrame("EditBox", nil, parent)
        
        if BackdropTemplateMixin then
            Mixin(eb, BackdropTemplateMixin)
        end
        
        eb:SetSize(width, height)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        
        eb:SetJustifyH("RIGHT")
        eb:SetTextInsets(0, 5, 0, 0)
        
        eb:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        eb:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
        eb:SetBackdropBorderColor(0.5, 0.5, 0.5, 1.0)
        
        return eb
    end

    -- Gold input
    local goldEB = CreateCustomEditBox(moneyContainer, goldBoxWidth, AL.ITEM_ROW_HEIGHT - 4)
    moneyContainer.goldEB = goldEB
    goldEB:SetPoint("LEFT", moneyContainer, "LEFT", 0, 0)
    goldEB:SetMaxLetters(7)
    goldEB:SetNumeric(true)
    goldEB:SetText(gsc.gold)
    
    local goldIcon = moneyContainer:CreateTexture(nil, "ARTWORK")
    goldIcon:SetSize(iconSize, iconSize)
    goldIcon:SetPoint("LEFT", goldEB, "RIGHT", iconPadding, 0)
    goldIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    
    -- Silver input
    local silverEB = CreateCustomEditBox(moneyContainer, silverCopperBoxWidth, AL.ITEM_ROW_HEIGHT - 4)
    moneyContainer.silverEB = silverEB
    silverEB:SetPoint("LEFT", goldIcon, "RIGHT", groupPadding, 0)
    silverEB:SetMaxLetters(2)
    silverEB:SetNumeric(true)
    silverEB:SetText(string.format("%02d", gsc.silver))

    local silverIcon = moneyContainer:CreateTexture(nil, "ARTWORK")
    silverIcon:SetSize(iconSize, iconSize)
    silverIcon:SetPoint("LEFT", silverEB, "RIGHT", iconPadding, 0)
    silverIcon:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")

    -- REMOVED: Copper input and icon are no longer needed.
    
    local commitHandler = CreateCommitHandler(moneyContainer, itemID, characterName, realmName, fieldType)
    
    local function highlightOnFocus(self)
        self:HighlightText()
    end

    goldEB:HookScript("OnEnterPressed", commitHandler)
    goldEB:HookScript("OnEditFocusLost", commitHandler)
    goldEB:HookScript("OnTextChanged", EnforceTextLimits)
    goldEB:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    goldEB:HookScript("OnKeyDown", HandleTabNavigation)
    goldEB:HookScript("OnEditFocusGained", highlightOnFocus)
    
    silverEB:HookScript("OnEnterPressed", commitHandler)
    silverEB:HookScript("OnEditFocusLost", commitHandler)
    silverEB:HookScript("OnTextChanged", EnforceTextLimits)
    silverEB:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    silverEB:HookScript("OnKeyDown", HandleTabNavigation)
    silverEB:HookScript("OnEditFocusGained", highlightOnFocus)

    -- MODIFIED: Recalculated total width without copper.
    local totalWidth = goldEB:GetWidth() + iconPadding + goldIcon:GetWidth() + groupPadding + 
                       silverEB:GetWidth() + iconPadding + silverIcon:GetWidth()
    moneyContainer:SetSize(totalWidth, AL.ITEM_ROW_HEIGHT)
    
    parent[fieldType .. "Inputs"] = { container = moneyContainer, goldEB = goldEB, silverEB = silverEB }

    local columnWidth = 0
    if fieldType == "safetyNetBuyout" then columnWidth = AL.AP_COL_SAFETY_NET_WIDTH
    elseif fieldType == "normalBuyoutPrice" then columnWidth = AL.AP_COL_NORMAL_BUYOUT_WIDTH
    elseif fieldType == "undercutAmount" then columnWidth = AL.AP_COL_UNDERCUT_AMOUNT_WIDTH
    end

    local centeredX = xOffset + (columnWidth / 2) - (totalWidth / 2)
    moneyContainer:SetPoint("LEFT", parent, "LEFT", centeredX, yOffset)

    return parent[fieldType .. "Inputs"]
end

-- Helper function to create a tab button
local function createTabButton(parentFrame, name, text, viewMode, frameNameSuffix)
    local btn = CreateFrame("Button", "AL_"..name.."Tab" .. frameNameSuffix, parentFrame, "UIPanelButtonTemplate")
    btn:SetText(text)
    btn:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", AL.COL_PADDING, -(AL.COL_PADDING))
    btn.viewMode = viewMode
    btn:SetScript("OnClick", function(selfBtn)
        AL.currentActiveTab = selfBtn.viewMode
        _G.AL_SavedData.Settings.activeViewMode = AL.currentActiveTab
        -- BUG FIX: Removed call to the now-defunct periodic refresh timer.
        AL:RefreshLedgerDisplay()
    end)
    return btn
end
AL.createTabButton = createTabButton

-- Helper function to create a left panel button (sort/filter)
function AL.createLeftPanelButton(parentFrame, name, text, criteriaOrFunc, isSortOrFilterButton, frameNameSuffix)
    local btn
    
    if isSortOrFilterButton then
        -- Inherit from the template to get all the size/font/positioning correct.
        btn = CreateFrame("CheckButton", "AL_"..name.."Button" .. frameNameSuffix, parentFrame, "UIPanelButtonTemplate")
        
        -- Create the custom highlight texture as a child of the button
        btn.selectedHighlight = btn:CreateTexture(nil, "OVERLAY")
        btn.selectedHighlight:SetAllPoints(true) -- Make it cover the whole button perfectly
        btn.selectedHighlight:SetTexture("Interface\\AddOns\\AuctioneersLedger\\Media\\SelectedFilterButton.tga")
        btn.selectedHighlight:Hide() -- Hide it initially
    else
        -- Action buttons are still regular buttons with the standard template.
        btn = CreateFrame("Button", "AL_"..name.."Button" .. frameNameSuffix, parentFrame, "UIPanelButtonTemplate")
    end

    btn:SetText(text)
    btn.originalText = text -- Store for quality filters
    
    if isSortOrFilterButton then
        btn.criteria = criteriaOrFunc
        btn:SetScript("OnClick", function(selfBtn)
            local criteria = selfBtn.criteria
            local currentFilters = _G.AL_SavedData.Settings.filterSettings[AL.currentActiveTab]
            if not currentFilters then return end

            if type(criteria) == "string" and string.find(criteria, AL.SORT_QUALITY_PREFIX, 1, true) then
                local qualityValue = tonumber(string.sub(criteria, #AL.SORT_QUALITY_PREFIX + 1))
                currentFilters.quality = (qualityValue == -1 and nil or qualityValue)
            elseif type(criteria) == "string" and string.find(criteria, AL.FILTER_STACK_PREFIX, 1, true) then
                local stackType = string.sub(criteria, #AL.FILTER_STACK_PREFIX + 1)
                currentFilters.stack = (stackType == AL.FILTER_ALL_STACKS and nil or stackType)
            else
                currentFilters.sort = criteria
                if AL.currentActiveTab == AL.VIEW_WARBAND_STOCK then
                    currentFilters.view = (criteria == AL.SORT_ALPHA) and "GROUPED_BY_ITEM" or "FILTERED_FLAT_LIST"
                else
                    currentFilters.view = (AL.currentActiveTab == AL.VIEW_PROFIT_LOSS) and "FLAT_PROFIT_LOSS" or "FLAT_LIST"
                end
            end

            AL:RefreshLedgerDisplay()
        end)
    elseif type(criteriaOrFunc) == "function" then
        btn:SetScript("OnClick", criteriaOrFunc)
    end

    return btn
end


-- Helper function to create a label frame for the left panel
local function createLabelFrame(parentPanel, name, frameNameSuffix)
    local labelFrame = CreateFrame("Frame", "AL_"..name.."Frame" .. frameNameSuffix, parentPanel)
    if BackdropTemplateMixin then Mixin(labelFrame, BackdropTemplateMixin) end
    labelFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Header", 
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border", 
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    labelFrame:SetBackdropColor(unpack(AL.LABEL_BACKDROP_COLOR))
    labelFrame.text = labelFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    labelFrame.text:SetAllPoints(true)
    labelFrame.text:SetTextColor(unpack(AL.LABEL_TEXT_COLOR))
    return labelFrame
end
AL.createLabelFrame = createLabelFrame

-- Helper function to create header text for columns
local function CreateHeaderText(parentFrame, fsns, txt, jstH_param)
    local fs = parentFrame:CreateFontString(parentFrame:GetName()..fsns, "ARTWORK", "GameFontNormalSmall")
    fs:SetHeight(AL.COLUMN_HEADER_HEIGHT - 4)
    fs:SetText(txt)
    fs:SetJustifyH(jstH_param or "CENTER") 
    fs:SetJustifyV("MIDDLE")
    return fs
end
AL.CreateHeaderText = CreateHeaderText
