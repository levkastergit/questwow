-- QuestWow: кнопка у миникарты (без библиотек, перетаскивается по кругу)
local _, QW = ...
local M = {}
QW.Minimap = M

local btn

local function UpdatePosition()
    local angle = math.rad(QW.db.settings.minimap.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 10
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function Create()
    btn = CreateFrame("Button", "QuestWowMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            QW.UI.Show()
            QW.UI.SelectTab("settings")
        else
            QW.UI.Toggle()
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            cx, cy = cx / s, cy / s
            QW.db.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffffd100Quest|r|cff66ccffWow|r")
        local me = QW.me and QW.db.chars[QW.me]
        if me then GameTooltip:AddLine("Выполнено: " .. (me.doneCount or 0), 1, 1, 1) end
        for _, p in ipairs(QW.db.settings.partners) do
            local ch = QW.db.chars[p] or {}
            local on = QW.Comm.IsOnline(p) and "|cff5ce673в сети|r" or "|cff888888не в сети|r"
            GameTooltip:AddDoubleLine(QW.ColoredName(p) .. "  " .. (ch.doneCount or 0), on)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("ЛКМ — открыть, ПКМ — настройки, перетащить — переместить", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function M.Update()
    if not btn then Create() end
    btn:SetShown(not QW.db.settings.minimap.hide)
    UpdatePosition()
end

QW.On("LOGIN", function() M.Update() end)
