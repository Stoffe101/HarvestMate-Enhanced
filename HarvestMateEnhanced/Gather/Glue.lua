-- HarvestMate Enhanced: Gather/Glue.lua
-- Joins HarvestMate's vendored modules to HME without changing them:
--   * one price source: HarvestMate's auction prices come from Engine/Prices.lua
--   * the one-key gather binding is offered with an explanation and only turned
--     on with the player's yes; it is released on combat, on a binding change
--     and when HME's window closes with a key capture still open
--   * Soft Target Interact is only changed with the player's yes (HarvestMate's
--     own popup) and never in combat
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local HG = ns.HG

---------------------------------------------------------------------------
-- Prices: HarvestMate asks HG.AuctionPrice (before the 5% cut) and checks
-- HG.HasAuctionSource. Both now read HME's price layer.
---------------------------------------------------------------------------
function HG.AuctionPrice(id)
    local rec = HME.Prices.Get(id)
    if rec and rec.typical then return rec.typical / (1 - HME.Prices.AH_CUT) end
    return nil
end

function HG.HasAuctionSource()
    return #HME.Prices.Available() > 0
end

---------------------------------------------------------------------------
-- One-key gathering: consent first.
---------------------------------------------------------------------------
local CONSENT = "HARVESTMATEENHANCED_GATHER_KEY"

local function KeyLabel(key) return (HG.KeyLabel and HG.KeyLabel(key)) or key end

-- What the chosen key does today, for the explanation.
local function KeyNow(key)
    local action = GetBindingAction and GetBindingAction(key)
    action = HME.Str(action)
    if not action or action == "" then return "nothing" end
    local label = _G["BINDING_NAME_" .. action]
    return HME.Str(label) or action
end

local function RegisterConsent()
    if not StaticPopupDialogs or StaticPopupDialogs[CONSENT] then return StaticPopupDialogs ~= nil end
    StaticPopupDialogs[CONSENT] = {
        text = "%s",
        button1 = "Turn it on",
        button2 = "Not now",
        OnAccept = function()
            if HME.InCombat() then
                HME.Print("not in combat: key bindings can't change now. Try again after the fight.")
                return
            end
            HG.db.opt.gatherKey = true
            HG.db.gatherKeyAsked = true
            HG.Signal("OPTIONS")
            HME.Signal("SETTINGS")
            HME.Print(("one-key gathering is on: |cffffd100%s|r gathers while you stand at something you can gather.")
                :format(KeyLabel(HG.db.opt.gatherKeyBind)))
        end,
        OnCancel = function()
            HG.db.gatherKeyAsked = true
            HME.Signal("SETTINGS")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    return true
end

-- Turning the feature on always goes through here.
function HME.AskGatherKey()
    local key = HG.db.opt.gatherKeyBind or "F"
    local text = ("One-key gathering\n\nWhile you stand next to a herb, vein, chest or skinnable corpse you can "
        .. "gather, |cffffd100%s|r becomes \"Interact with target\" for that moment, so one press gathers it. As soon "
        .. "as you step away, start a fight, or turn this off, %s goes back to what it does now (|cffffd100%s|r). "
        .. "Your saved key bindings are never changed. You can pick another key in Settings."):format(
        KeyLabel(key), KeyLabel(key), KeyNow(key))
    if RegisterConsent() and StaticPopup_Show then
        StaticPopup_Show(CONSENT, text)
    else
        HME.Print(text)
    end
end

function HME.SetGatherKey(on)
    if on then
        HME.AskGatherKey()
    else
        HG.db.opt.gatherKey = false
        if HG.SetGatherKeyActive then HG.SetGatherKeyActive(false) end
        HG.Signal("OPTIONS")
        HME.Signal("SETTINGS")
    end
end

---------------------------------------------------------------------------
-- Key capture safety: the capture window never outlives a fight or HME's
-- window, and a key captured as a lone modifier is never stored.
---------------------------------------------------------------------------
-- Hiding is enough: a hidden frame gets no keys, and Hide is never protected.
local function CloseCapture()
    local f = _G.HarvestMateEnhancedKeyCapture
    if f and f.IsShown and f:IsShown() then f:Hide() end
end
HME.CloseKeyCapture = CloseCapture
HME.On("PLAYER_REGEN_DISABLED", CloseCapture)
HME.Listen("WINDOW_HIDDEN", CloseCapture)
-- A binding set elsewhere (the game's keybinding window) while ours is held:
-- let go, so the player's new binding is what the key does.
HME.On("UPDATE_BINDINGS", function()
    if HG.GatherKeyBound and HG.GatherKeyBound() and not HME.InCombat() then
        HG.SetGatherKeyActive(false)
    end
end)
-- Logging out with the key held: release it (and the temporary CVars).
HME.On("PLAYER_LOGOUT", function()
    if HG.SetGatherKeyActive and not HME.InCombat() then HG.SetGatherKeyActive(false) end
end)

---------------------------------------------------------------------------
-- HarvestMate's chat commands, reachable as /hme <command> (and /hm when
-- HarvestMate itself is not installed): see Core/Commands.lua.
---------------------------------------------------------------------------
HME.HGCommands = HG.commands
