-- Controls, game settings and combat: nothing changes without the player's
-- yes, everything is released and put back, and nothing protected runs in
-- combat (the fake client raises if SetOverrideBinding/ClearOverrideBindings
-- run while IN_COMBAT is set).

local ns, HME = LoadHME()
local HG = ns.HG

STEP("first login changes nothing by itself")
eq(CVARS.SoftTargetInteract, "0", "Soft Target Interact untouched")
eq(CVARS.autoInteract, "0", "click-to-move untouched")
eq(CVARS.autoLootDefault, "0", "auto loot untouched")
check(next(OVERRIDES) == nil, "no key overridden")
check(HG.db.opt.gatherKey == false, "one-key gathering starts off")
check(HG.db.opt.announceParty == false and HG.db.opt.announceEmote == false, "no chat announcements by default")
local asked = false
for _, p in ipairs(POPUPS) do if p == "HARVESTMATE_SOFT_TARGET" then asked = true end end
check(asked, "Soft Target Interact is offered with an explanation instead")
check(not (ns.db.sparkle and ns.db.sparkle.enabled), "Glimmer starts off (Gatherpedia's default)")

STEP("the gather key needs a yes")
HME.SetGatherKey(true)
check(HG.db.opt.gatherKey == false, "asking changes nothing yet")
local popup = StaticPopupDialogs.HARVESTMATEENHANCED_GATHER_KEY
check(popup and POPUPS[#POPUPS] == "HARVESTMATEENHANCED_GATHER_KEY", "the consent window shows")
popup.OnCancel()
check(HG.db.opt.gatherKey == false, "Not now: still off")
HME.SetGatherKey(true)
IN_COMBAT = true
popup.OnAccept()
check(HG.db.opt.gatherKey == false, "a yes in combat is turned down (bindings can't change then)")
IN_COMBAT = false
popup.OnAccept()
check(HG.db.opt.gatherKey == true, "a yes out of combat turns it on")

STEP("bound only at a node, released on combat and binding changes")
check(next(OVERRIDES) == nil, "nothing bound away from nodes")
HG.SetGatherKeyActive(true)
eq(OVERRIDES.F, "INTERACTTARGET", "F interacts while at a node")
FireEvent("PLAYER_REGEN_DISABLED")   -- fires before the lockdown starts
check(next(OVERRIDES) == nil, "released as the fight starts")
IN_COMBAT = true
HG.SetGatherKeyActive(true)          -- must not try to bind in combat
check(next(OVERRIDES) == nil, "nothing bound in combat (and no protected call)")
IN_COMBAT = false
FireEvent("PLAYER_REGEN_ENABLED")
HG.SetGatherKeyActive(true)
eq(OVERRIDES.F, "INTERACTTARGET", "bound again after the fight, at a node")
FireEvent("UPDATE_BINDINGS")
check(next(OVERRIDES) == nil, "a binding change elsewhere: let go")
HG.SetGatherKeyActive(true)
HME.SetGatherKey(false)
check(next(OVERRIDES) == nil and HG.db.opt.gatherKey == false, "turning it off releases it")

STEP("a key already bound to Interact is left alone")
HME.SetGatherKey(true)
StaticPopupDialogs.HARVESTMATEENHANCED_GATHER_KEY.OnAccept()
BINDINGS.G = "INTERACTTARGET"
HG.db.opt.gatherKeyBind = "G"
HG.SetGatherKeyActive(true)
check(OVERRIDES.G == nil, "no override on top of the same action")
HG.db.opt.gatherKeyBind = "F"

STEP("the key capture never outlives a fight")
HG.CaptureGatherKey()
local cap = _G.HarvestMateEnhancedKeyCapture
check(cap:IsShown(), "capture open")
FireEvent("PLAYER_REGEN_DISABLED")
check(not cap:IsShown(), "closed when combat starts")
IN_COMBAT = true
ClearLog()
HG.CaptureGatherKey()
check(not cap:IsShown(), "and won't open in combat")
IN_COMBAT = false

STEP("Soft Target Interact: only with a yes, and put back")
local sp = StaticPopupDialogs.HARVESTMATE_SOFT_TARGET
check(sp, "HarvestMate's own explanation")
sp.OnAccept()
eq(CVARS.SoftTargetInteract, "3", "on after the yes")
SlashCmdList.HARVESTMATEENHANCED("soft off")
eq(CVARS.SoftTargetInteract, "0", "/hme soft off puts back what it was")
IN_COMBAT = true
check(not HG.SetCVar("SoftTargetInteract", "3"), "no game setting changes in combat")
eq(CVARS.SoftTargetInteract, "0", "unchanged")
IN_COMBAT = false

STEP("Glimmer waits for the fight to end")
IN_COMBAT = true
check(HME.SetGlimmer(true) == false, "not in combat")
IN_COMBAT = false

STEP("logout lets go of everything")
HG.SetGatherKeyActive(true)
FireEvent("PLAYER_LOGOUT")
check(next(OVERRIDES) == nil, "released at logout")

STEP("old addons still enabled: HME pauses its copies, without saving that")
LOADED_ADDONS = { HarvestMate = true, Gatherpedia = true, GatherPathForever = true }
HG.Init(HME.db.hm)
check(HG.db.opt.enabled == false, "HarvestMate's helpers read as off")
check(HME.db.hm.opt.enabled == true, "but the saved choice is untouched")
HG.db.opt.nearby = false
check(HME.db.hm.opt.nearby == false, "changes still save")
HG.db.opt.nearby = true
check(HME.Routes:LinesPaused(), "route lines wait for GatherPath's own")
check(not HME.GlimmerAvailable(), "Glimmer waits for Gatherpedia's own")
local conflicts = HME.Migrate.Conflicts()
eq(#conflicts, 3, "all three named on the dashboard")
HME.Migrate.DisableReplaced()
check(DISABLED_ADDONS.HarvestMate and DISABLED_ADDONS.Gatherpedia and DISABLED_ADDONS.GatherPathForever,
    "the button turns them off (after the player pressed it)")
LOADED_ADDONS = nil
HG.Init(HME.db.hm)
check(HG.db.opt.enabled == true, "back to normal without them")

STEP("no protected calls happened during any of this")
for _, e in ipairs(ERRORS or {}) do check(not e:find("protected"), e) end
