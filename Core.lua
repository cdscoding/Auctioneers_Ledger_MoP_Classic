-- Auctioneer's Ledger - Core
-- This file contains the core logic for event handling and initialization.

AL.ahTabHooked = false -- Keep track of our hook

-- MoP Change: C_Timer does not exist. We need a frame-based timer for delayed actions.
local function CreateDelayedCall(delay, func)
    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= delay then
            func()
            self:SetScript("OnUpdate", nil) -- Stop the timer
        end
    end)
end

-- SURGICAL FIX: New polling function to reliably find the AuctionHouseFrame.
function AL:SetupAuctionHouseIntegration(attempt)
    attempt = attempt or 1
    if attempt > 20 then -- Failsafe after 2 seconds (20 * 0.1s)
        return
    end

    -- SURGICAL FIX: Changed AuctionFrame to AuctionHouseFrame for MoP compatibility.
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        if not _G["AL_AHBlasterButton"] then
            local ahButton = CreateFrame("Button", "AL_AHBlasterButton", AuctionHouseFrame, "UIPanelButtonTemplate")
            ahButton:SetSize(80, 22)
            ahButton:SetText("Blaster")
            -- SURGICAL CHANGE: Adjusted Y-offset from 25 to 5 to move the button down.
            ahButton:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -20, 0)
            ahButton:SetScript("OnClick", function() AL:ToggleBlasterWindow() end)
        end
        AL:InitializeAuctionHooks()
        QueryAuctionItems("", nil, nil, nil, nil, nil, nil, nil, true)
        AL:ShowBlasterWindow()
        AL:TriggerDebouncedRefresh("AUCTION_HOUSE_SHOW")
    else
        -- AuctionHouseFrame not ready, try again shortly.
        CreateDelayedCall(0.1, function()
            AL:SetupAuctionHouseIntegration(attempt + 1)
        end)
    end
end


-- Internal function to process purchase events. This function is now called by our new system.
function AL:ProcessPurchase(itemName, itemLink, quantity, price)
    if not itemName or not quantity or not price or price <= 0 then
        return
    end

    -- Step 1: ALWAYS add the transaction to the history database.
    self:AddToHistory("purchases", { itemName = itemName, itemLink = itemLink, quantity = quantity, price = price, pricePerItem = price / quantity, timestamp = time() })
    self:RefreshBlasterHistory()

    if not itemLink then
        return
    end

    local itemID = self:GetItemIDFromLink(itemLink)
    if not itemID then return end

    -- Step 2: Check if the item is tracked in the main ledger.
    local isTracked = (_G.AL_SavedData.Items and _G.AL_SavedData.Items[itemID])
    
    if isTracked then
        self:RecordTransaction("BUY", "AUCTION", itemID, price, quantity)
        -- [[ DIRECTIVE #3 START: Update location on purchase for existing items ]]
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        local itemEntry = _G.AL_SavedData.Items and _G.AL_SavedData.Items[itemID]
        if itemEntry and itemEntry.characters and itemEntry.characters[charKey] then
            local charData = itemEntry.characters[charKey]
            charData.isExpectedInMail = true
            charData.expectedMailCount = (charData.expectedMailCount or 0) + quantity
        end
        -- [[ DIRECTIVE #3 END ]]
    else
        -- RETAIL CHANGE: Check setting before showing popup
        if _G.AL_SavedData and _G.AL_SavedData.Settings and _G.AL_SavedData.Settings.autoAddNewItems then
            local success, msg = AL:InternalAddItem(itemLink, UnitName("player"), GetRealmName())
            if success then
                -- Retroactively record the transaction that triggered this
                self:RecordTransaction("BUY", "AUCTION", itemID, price, quantity)
                self:RefreshLedgerDisplay()
            end
        else
            StaticPopup_Show("AL_CONFIRM_TRACK_NEW_PURCHASE", itemName, nil, { itemName = itemName, itemLink = itemLink, itemID = itemID, price = price, quantity = quantity })
        end
    end
end

function AL:InitializeLibs()
    if self.libsReady then return end
    self.LDB_Lib = LibStub("LibDataBroker-1.1", true)
    self.LibDBIcon_Lib = LibStub("LibDBIcon-1.0", true)
    if not self.LDB_Lib then DEFAULT_CHAT_FRAME:AddMessage(AL.ADDON_NAME .. " (v" .. AL.VERSION .. ") Warning: LibDataBroker-1.1 not found!") end
    if not self.LibDBIcon_Lib then DEFAULT_CHAT_FRAME:AddMessage(AL.ADDON_NAME .. " (v" .. AL.VERSION .. ") Warning: LibDBIcon-1.0 not found!") end
    self.libsReady = (self.LDB_Lib ~= nil and self.LibDBIcon_Lib ~= nil)
end

function AL:CreateLDBSourceAndMinimapIcon()
    if not self.libsReady or not self.LDB_Lib then return end
    
    local ldbObject = {
        type = "launcher",
        label = AL.ADDON_NAME,
        icon = "Interface\\Icons\\inv_misc_book_09", -- MoP Change: Updated icon to match .toc
        OnClick = function(_, button)
            if IsShiftKeyDown() and IsControlKeyDown() and button == "LeftButton" then
                _G.AL_SavedData.Settings.minimapIcon.hide = not _G.AL_SavedData.Settings.minimapIcon.hide
                if AL.LibDBIcon_Lib then
                    if _G.AL_SavedData.Settings.minimapIcon.hide then AL.LibDBIcon_Lib:Hide(AL.LDB_PREFIX)
                    else AL.LibDBIcon_Lib:Show(AL.LDB_PREFIX) end
                end
            elseif IsShiftKeyDown() and button == "LeftButton" then
                _G.AL_SavedData.Settings.window.x = nil; _G.AL_SavedData.Settings.window.y = nil
                _G.AL_SavedData.Settings.window.width = AL.DEFAULT_WINDOW_WIDTH; _G.AL_SavedData.Settings.window.height = AL.DEFAULT_WINDOW_HEIGHT
                if AL.MainWindow and AL.MainWindow:IsShown() then AL:ApplyWindowState() else AL:ToggleMainWindow() end
            else
                AL:ToggleMainWindow()
            end
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip or not tooltip.AddLine then return end
            tooltip:AddLine(AL.ADDON_NAME); tooltip:AddLine("Left-Click: Toggle Window"); tooltip:AddLine("Shift + Left-Click: Reset Window Position/Size."); tooltip:AddLine("Ctrl + Shift + Left-Click: Toggle Minimap Icon.")
        end
    }

    self.LDBObject = self.LDB_Lib:NewDataObject(AL.LDB_PREFIX, ldbObject)
    if self.LibDBIcon_Lib then self.LibDBIcon_Lib:Register(AL.LDB_PREFIX, self.LDBObject, _G.AL_SavedData.Settings.minimapIcon) end
end

function AL:HandleAddonLoaded(arg)
    if not (arg == AL.ADDON_NAME and not self.addonLoadedProcessed) then return end
    self.addonLoadedProcessed = true

    local success, err = pcall(function()
        -- Create the dedicated scan tooltip at a safe time.
        if not AL.ScanTooltip then
            AL.ScanTooltip = CreateFrame("GameTooltip", "AL_ScanTooltip", UIParent, "GameTooltipTemplate")
            AL.ScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end

        AL:InitializeDB()
        AL:InitializeSavedData() 
        AL:InitializeCoreHooks() 
        AL.currentActiveTab = _G.AL_SavedData.Settings.activeViewMode
        SLASH_ALEDGERMOP1="/aledger"; SLASH_ALEDGERMOP2="/al";
        SlashCmdList["ALEDGERMOP"] = function() AL:ToggleMainWindow() end
        SlashCmdList["ALEDGER"] = function() AL:ToggleMainWindow() end
        SlashCmdList["AL"] = function() AL:ToggleMainWindow() end
        AL:InitializeLibs()
        if AL.libsReady then AL:CreateLDBSourceAndMinimapIcon() end
    end)
    if not success then AL:ErrorHandler(err, "HandleAddonLoaded") end
end

function AL:HandlePlayerLogin()
    AL.gameFullyInitialized = false
    if not self.libsReady then self:InitializeLibs() end
    
    local success, err = pcall(function()
        -- RETAIL CHANGE: Removed periodic refresh timer.
        AL.previousMoney = GetMoney()
        AL:BuildSalesCache()
    end)
    if not success then AL:ErrorHandler(err, "HandlePlayerLogin") end
end

function AL:HandleGameReady()
    if self.gameFullyInitialized then return end
    
    local success, err = pcall(function()
        local s, e = pcall(AL.CreateFrames, AL)
        if not s then AL:ErrorHandler(e, "CreateFrames (Delayed)") end
        
        s, e = pcall(AL.ApplyWindowState, AL)
        if not s then AL:ErrorHandler(e, "ApplyWindowState (Delayed)") end
        
        AL.gameFullyInitialized = true
        
        if self.MainWindow and self.MainWindow:IsShown() then self:RefreshLedgerDisplay() end
        
        -- SURGICAL ADDITION: Show the welcome window on first login or after a data nuke.
        if _G.AL_SavedData and _G.AL_SavedData.Settings.showWelcomeWindow then
            AL:ShowWelcomeWindow()
        end
        
        -- Unregister this event now that we're initialized
        local eventHandler = _G["AL_EventHandler_v" .. AL.VERSION:gsub("%.","_")]
        if eventHandler then
            eventHandler:UnregisterEvent("BAG_UPDATE_DELAYED")
        end
    end)
    if not success then AL:ErrorHandler(err, "HandleGameReady") end
end

local eventHandlerFrame = CreateFrame("Frame", "AL_EventHandler_v" .. AL.VERSION:gsub("%.","_"))
eventHandlerFrame:RegisterEvent("ADDON_LOADED")
eventHandlerFrame:RegisterEvent("PLAYER_LOGIN")
eventHandlerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventHandlerFrame:RegisterEvent("BAG_UPDATE")
eventHandlerFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventHandlerFrame:RegisterEvent("AUCTION_HOUSE_SHOW") 
eventHandlerFrame:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
eventHandlerFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
eventHandlerFrame:RegisterEvent("MAIL_SHOW")
eventHandlerFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventHandlerFrame:RegisterEvent("MAIL_CLOSED")
eventHandlerFrame:RegisterEvent("MAIL_SEND_SUCCESS") 
eventHandlerFrame:RegisterEvent("MERCHANT_SHOW")
eventHandlerFrame:RegisterEvent("MERCHANT_CLOSED")
eventHandlerFrame:RegisterEvent("TRADE_SHOW")
eventHandlerFrame:RegisterEvent("PLAYER_MONEY")

eventHandlerFrame:SetScript("OnEvent", function(selfFrame, event, ...)
    local args = {...}
    local success, err = pcall(function()
        if event == "ADDON_LOADED" then
            AL:HandleAddonLoaded(unpack(args))
        elseif event == "PLAYER_LOGIN" then
            AL:HandlePlayerLogin()
            selfFrame:SetScript("OnUpdate", function(...) AL:HandleOnUpdate(...) end)
        elseif event == "BAG_UPDATE_DELAYED" then
            AL:HandleGameReady()
        
        elseif event == "AUCTION_HOUSE_SHOW" then
            -- SURGICAL FIX: Use a polling function instead of a fixed delay.
            AL:SetupAuctionHouseIntegration()

        elseif event == "AUCTION_HOUSE_CLOSED" then
            wipe(AL.recentlyViewedItems)
            AL.pendingCost = nil
            AL.pendingItem = nil
            AL:HideBlasterWindow()
            AL:TriggerDebouncedRefresh(event)

        elseif event == "AUCTION_OWNED_LIST_UPDATE" then
            wipe(AL.auctionIDCache)
            local numOwnedAuctions = GetNumAuctionItems("owner")
            for i=1, numOwnedAuctions do
                local name, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, itemID = GetAuctionItemInfo("owner", i)
                if itemID then
                    local itemLink = GetAuctionItemLink("owner", i)
                    AL.auctionIDCache[i] = { itemID = itemID, quantity = count, itemLink = itemLink }
                end
            end
            AL:TriggerDebouncedRefresh(event)
        
        elseif event == "AUCTION_ITEM_LIST_UPDATE" then
            -- SURGICAL FIX: Logic moved to HandlePostSuccess. This event is now just a refresh trigger.
            AL:TriggerDebouncedRefresh(event)
        
        elseif event == "PLAYER_MONEY" then
            local currentMoney = GetMoney()
            if AL.previousMoney and currentMoney ~= AL.previousMoney then
                local moneyChange = currentMoney - AL.previousMoney
                if moneyChange < 0 then
                    local moneySpent = -moneyChange
                    AL.pendingCost = {
                        cost = moneySpent,
                        time = GetTime()
                    }
                    if not AL.isVendorPurchase then
                        AL:TryToMatchEvents()
                    end
                end
            end
            AL.previousMoney = currentMoney
            -- [[ DIRECTIVE: Manually reset the flag AFTER the event has been processed ]]
            AL.isVendorPurchase = false

        -- [[ DIRECTIVE: Mail logic rewrite ]]
        elseif event == "MAIL_INBOX_UPDATE" then
            if AL.mailRefreshTimer then AL.mailRefreshTimer:SetScript("OnUpdate", nil); AL.mailRefreshTimer = nil; end
            AL.mailRefreshTimer = CreateDelayedCall(AL.MAIL_REFRESH_DELAY, function()
                -- Process sales first to update pending auction lists
                AL:ProcessInboxForSales()
                -- Now, reconcile our internal mail state with what's actually in the mail
                AL:ReconcileLootedMail()
                -- Finally, refresh the UI with the corrected data
                AL:TriggerDebouncedRefresh(event)
                AL.mailRefreshTimer = nil
            end)
        -- [[ END: Mail logic rewrite ]]

        -- [[ DIRECTIVE #1: Remove refresh on MAIL_SHOW to prevent location changes ]]
        -- The original AL:TriggerDebouncedRefresh(event) has been removed from this block.
        elseif event == "MAIL_SHOW" then
            -- This block is now intentionally empty.

        elseif event == "MERCHANT_SHOW" then
            AL:InitializeVendorHooks()
            AL:TriggerDebouncedRefresh(event)
        elseif event == "TRADE_SHOW" then
            AL:InitializeTradeHooks()
        else
            AL:TriggerDebouncedRefresh(event)
        end
    end)
    if not success then AL:ErrorHandler(err, "OnEvent - " .. event) end
end)

