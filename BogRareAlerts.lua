-- BogRareAlerts: on-screen alert when a rare mob is loaded near you.
-- Click the banner to target the rare, put a raid marker on it, and ping it.

local COOLDOWN  = 300       -- seconds before the same mob can alert again
local MARK_ICON = 8         -- 1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon, 6 Square, 7 Cross, 8 Skull
local PING_TYPE = "warning" -- attack | warning | assist | onmyway
local seen = {}             -- [guid] = time of last alert

BogRareAlertsDB = BogRareAlertsDB or {}
if BogRareAlertsDB.sound == nil then BogRareAlertsDB.sound = true end
if BogRareAlertsDB.icon  == nil then BogRareAlertsDB.icon  = MARK_ICON end

-- Forever uses Midnight-style "secret values" in some situations.
-- Skip anything we're not allowed to read instead of erroring.
local function readable(v)
    return not (issecretvalue and issecretvalue(v))
end

---------------------------------------------------------------------
-- Alert frame
---------------------------------------------------------------------
local alert = CreateFrame("Frame", "BogRareAlertsFrame", UIParent)
alert:SetSize(500, 100)
alert:SetPoint("TOP", UIParent, "TOP", 0, -180)
alert:SetFrameStrata("FULLSCREEN_DIALOG")
alert:Hide()

alert.title = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
alert.title:SetPoint("TOP", 0, 0)
alert.title:SetText("RARE SPOTTED")
alert.title:SetTextColor(1, 0.82, 0)

alert.name = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
alert.name:SetPoint("TOP", alert.title, "BOTTOM", 0, -6)

alert.hint = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alert.hint:SetPoint("TOP", alert.name, "BOTTOM", 0, -6)

---------------------------------------------------------------------
-- Secure click button
-- SetRaidTarget is protected in the Midnight-era API, so an addon can't
-- call it directly. A secure macro button run by a real mouse click can.
---------------------------------------------------------------------
local btn = CreateFrame("Button", "BogRareAlertsButton", UIParent, "SecureActionButtonTemplate")
btn:SetAllPoints(alert)
btn:SetFrameStrata("FULLSCREEN_DIALOG")
btn:SetFrameLevel(alert:GetFrameLevel() + 10)
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:Hide()

local needHide = false

local function ArmButton(rawName)
    -- Secure attributes can't be changed in combat.
    if InCombatLockdown() or not rawName then return false end
    local macro = ("/targetexact %s\n/tm %d\n/ping [@target] %s"):format(
        rawName, BogRareAlertsDB.icon, PING_TYPE)
    btn:SetAttribute("macrotext", macro)
    btn:Show()
    needHide = false
    return true
end

local function DisarmButton()
    if InCombatLockdown() then
        needHide = true
    else
        btn:Hide()
    end
end

---------------------------------------------------------------------
-- Showing the alert
---------------------------------------------------------------------
local hideToken = 0
local function ShowAlert(displayName, rawName)
    alert.name:SetText(displayName)

    if ArmButton(rawName) then
        alert.hint:SetText("|cff00ff00Click to target, mark & ping|r")
    else
        alert.hint:SetText("|cffaaaaaa(click action unavailable)|r")
    end

    alert:SetAlpha(1)
    alert:Show()

    if BogRareAlertsDB.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end

    hideToken = hideToken + 1
    local token = hideToken
    C_Timer.After(8, function()
        if token ~= hideToken then return end -- a newer alert took over
        UIFrameFadeOut(alert, 1.5, 1, 0)
        C_Timer.After(1.5, function()
            if token == hideToken then
                alert:Hide()
                DisarmButton()
            end
        end)
    end)
end

---------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------
local function CheckUnit(unit)
    if not unit or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) or UnitIsDead(unit) then return end

    local class = UnitClassification(unit)
    if not readable(class) then return end
    if class ~= "rare" and class ~= "rareelite" then return end

    local guid = UnitGUID(unit)
    if not guid or not readable(guid) then return end

    local now = GetTime()
    if seen[guid] and (now - seen[guid]) < COOLDOWN then return end
    seen[guid] = now

    local rawName = UnitName(unit)
    if rawName and not readable(rawName) then rawName = nil end

    local display = rawName or "Unknown Rare"
    if class == "rareelite" then display = display .. " (Rare Elite)" end

    ShowAlert(display, rawName)
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        CheckUnit(unit)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CheckUnit("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target")
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: hide the click button if it was waiting to be hidden.
        if needHide and not alert:IsShown() then
            btn:Hide()
            needHide = false
        end
    end
end)

---------------------------------------------------------------------
-- Slash commands: /bograre test | sound | icon <1-8> | reset
---------------------------------------------------------------------
SLASH_BOGRAREALERTS1 = "/bograre"
SLASH_BOGRAREALERTS2 = "/bograrealerts"
SlashCmdList["BOGRAREALERTS"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "test" then
        ShowAlert("Test Rare")
    elseif cmd == "sound" then
        BogRareAlertsDB.sound = not BogRareAlertsDB.sound
        print("BogRareAlerts sound:", BogRareAlertsDB.sound and "on" or "off")
    elseif cmd == "icon" then
        local n = tonumber(arg)
        if n and n >= 1 and n <= 8 then
            BogRareAlertsDB.icon = n
            print("BogRareAlerts marker icon set to", n)
        else
            print("BogRareAlerts: use /bograre icon 1-8 (8 = skull)")
        end
    elseif cmd == "reset" then
        wipe(seen)
        print("BogRareAlerts: alert history cleared.")
    else
        print("BogRareAlerts commands: /bograre test, sound, icon <1-8>, reset")
    end
end