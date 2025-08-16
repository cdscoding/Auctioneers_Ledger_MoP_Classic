-- Auctioneer's Ledger MoP - v1.0.2 - Created by Clint Seewald (CS&A-Software)
-- This file creates the main addon table and initializes all addon-wide variables.

-- Create the main addon table if it doesn't exist
AL = _G.AL or {}
_G.AL = AL

-- Define shared variables on the main AL table to make them globally accessible
AL.ADDON_NAME = "AuctioneersLedgerMoP" 
AL.LDB_PREFIX = "AuctioneersLedgerMoPDB"
AL.ADDON_MSG_PREFIX = "ALMOP_MSG"

-- Set the addon version for MoP
AL.VERSION = "1.0.2"

-- This is the root of the addon's database.
_G.AL_SavedData = _G.AL_SavedData or {}

-- NEW: Error handling function
function AL:ErrorHandler(err, source)
    print("|cffff0000AL ERROR:|r in " .. tostring(source) .. ": " .. tostring(err))
end

-- Initialize all addon-wide variables to nil or their default empty state.
AL.ScanTooltip = nil -- Will be created in Core.lua at a safe time
AL.reminderPopupLastX = nil
AL.reminderPopupLastY = nil
AL.revertPopupTextTimer = nil
AL.itemRowFrames = {}
AL.eventRefreshTimer = nil
AL.eventDebounceCounter = 0
AL.periodicRefreshTimer = nil
AL.addonLoadedProcessed = false
AL.libsReady = false
AL.LDB_Lib = nil
AL.LibDBIcon_Lib = nil
AL.LDBObject = nil
AL.MainWindow = nil
AL.LeftPanel = nil
AL.CreateReminderButton = nil
AL.RefreshListButton = nil
AL.HelpWindowButton = nil
AL.ToggleMinimapButton = nil
AL.SupportMeButton = nil
AL.NukeLedgerButton = nil
AL.NukeHistoryButton = nil
AL.WarbandStockTab = nil
AL.AuctionFinancesTab = nil
AL.VendorFinancesTab = nil
AL.AuctionPricingTab = nil
AL.AuctionSettingsTab = nil
AL.SortAlphaButton = nil
AL.SortItemNameFlatButton = nil
AL.SortBagsButton = nil
AL.SortBankButton = nil
AL.SortMailButton = nil
AL.SortAuctionButton = nil
AL.SortLimboButton = nil
AL.SortCharacterButton = nil
AL.SortRealmButton = nil
AL.SortLastSellPriceButton = nil
AL.SortLastSellDateButton = nil
AL.SortLastBuyPriceButton = nil
AL.SortLastBuyDateButton = nil
AL.SortTotalProfitButton = nil
AL.SortTotalLossButton = nil
AL.LabelSortBy = nil
AL.LabelFilterLocation = nil
AL.LabelFilterQuality = nil
AL.LabelFilterLedger = nil
AL.LabelFilterStackability = nil
AL.ColumnHeaderFrame = nil
AL.ScrollFrame = nil
AL.ScrollChild = nil
AL.ReminderPopup = nil
AL.HelpWindow = nil
AL.HelpWindowScrollFrame = nil
AL.HelpWindowScrollChild = nil
AL.HelpWindowFontString = nil
AL.SupportWindow = nil
AL.BlasterWindow = nil
AL.WelcomeWindow = nil -- SURGICAL ADDITION: Frame variable for the new welcome window.
AL.testSetScriptControlDone = false
AL.mainDividers = AL.mainDividers or {}
AL.postItemHooked = false
AL.mailAPIsMissingLogged = false
AL.mailRefreshTimer = nil
AL.ahEntryDumpDone = false
AL.gameFullyInitialized = false
AL.currentActiveTab = nil 
AL.dataHasChanged = false
AL.pendingPostDetails = nil
AL.cancellationProcessedForID = nil -- SURGICAL ADDITION

-- Purchase tracking logic
AL.previousMoney = 0
AL.lastKnownPurchaseDetails = nil
AL.lastKnownMoneySpent = 0
AL.isVendorPurchase = false -- [[ DIRECTIVE: Add flag to prevent money event misfires ]]

-- Caching for mail processing
AL.salesItemCache = {}
AL.salesPendingAuctionCache = {}

-- Blaster State Variables
AL.itemsToScan = {}
AL.itemBeingScanned = nil
AL.isScanning = false
AL.blasterQueue = {}
AL.itemBeingPosted = nil
AL.isPosting = false 
AL.blasterQueueIsReady = false
AL.PricingData = {}

AL.auctionIDCache = {}

-- Button collections
AL.SortQualityButtons = {}
AL.StackFilterButtons = {}

-- Nuke functions to wipe saved data
function AL:NukeLedgerAndHistory()
    if _G.AL_SavedData then
        _G.AL_SavedData.Items = {}
        _G.AL_SavedData.PendingAuctions = {}
        if _G.AL_SavedData.Settings and _G.AL_SavedData.Settings.itemExpansionStates then
            _G.AL_SavedData.Settings.itemExpansionStates = {}
        end
        -- SURGICAL ADDITION: Reset the welcome window setting when the ledger is nuked.
        if _G.AL_SavedData.Settings then
            _G.AL_SavedData.Settings.showWelcomeWindow = true
        end
    end

    if _G.AuctioneersLedgerFinances then
        _G.AuctioneersLedgerFinances.posts = {}
        _G.AuctioneersLedgerFinances.sales = {}
        _G.AuctioneersLedgerFinances.purchases = {}
        _G.AuctioneersLedgerFinances.cancellations = {}
        _G.AuctioneersLedgerFinances.processedMailIDs = {}
    end
    
    ReloadUI()
end

function AL:NukeHistoryOnly()
    if _G.AuctioneersLedgerFinances then
        _G.AuctioneersLedgerFinances.posts = {}
        _G.AuctioneersLedgerFinances.sales = {}
        _G.AuctioneersLedgerFinances.purchases = {}
        _G.AuctioneersLedgerFinances.cancellations = {}
        _G.AuctioneersLedgerFinances.processedMailIDs = {}
    end

    if _G.AL_SavedData and _G.AL_SavedData.Items then
        for itemID, itemData in pairs(_G.AL_SavedData.Items) do
            if itemData and itemData.characters then
                for charKey, charData in pairs(itemData.characters) do
                    charData.totalAuctionBoughtQty = 0
                    charData.totalAuctionSoldQty = 0
                    charData.totalAuctionProfit = 0
                    charData.totalAuctionLoss = 0
                    charData.totalVendorBoughtQty = 0
                    charData.totalVendorSoldQty = 0
                    charData.totalVendorProfit = 0
                    charData.totalVendorLoss = 0
                end
            end
        end
    end

    ReloadUI()
end
