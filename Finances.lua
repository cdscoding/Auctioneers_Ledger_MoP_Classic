-- Finances.lua
-- This file handles the new transaction database.

AL = _G.AL or {}

-- Initializes the new database for transaction history.
function AL:InitializeFinancesDB()
    -- FIX: Instead of checking if the table exists, we check if our addon has already run the defaults.
    -- This prevents re-initialization if the file loads after the saved variables.
    if _G.AuctioneersLedgerFinances and _G.AuctioneersLedgerFinances.isInitialized then
        return
    end

    -- If the table doesn't exist at all, create it.
    if type(_G.AuctioneersLedgerFinances) ~= "table" then
        _G.AuctioneersLedgerFinances = {}
    end
    
    local defaults = {
        posts = {},
        sales = {},
        purchases = {},
        cancellations = {},
        processedMailIDs = {} -- [[ DIRECTIVE: Add processedMailIDs to saved variables to prevent duplicates ]]
    }

    for key, val in pairs(defaults) do
        if type(_G.AuctioneersLedgerFinances[key]) ~= "table" then
            _G.AuctioneersLedgerFinances[key] = val
        end
    end
    
    -- Set a flag inside the saved table itself to show it's been processed.
    _G.AuctioneersLedgerFinances.isInitialized = true
end

-- Adds a record to the specified history table.
function AL:AddToHistory(historyType, itemData)
    if historyType == "purchases" and AL.isVendorPurchase then
        return
    end

    if not _G.AuctioneersLedgerFinances or not _G.AuctioneersLedgerFinances[historyType] then
        return
    end

    local historyTable = _G.AuctioneersLedgerFinances[historyType]
    
    -- Keep history tables from growing indefinitely.
    if #historyTable >= 100 then
        table.remove(historyTable, 1) -- Remove the oldest entry
    end

    table.insert(historyTable, itemData)
end
