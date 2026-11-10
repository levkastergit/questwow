-- QuestWow: Core — база данных, события, запись выполненных квестов
local ADDON, QW = ...
_G.QuestWow = QW

QW.VERSION = "1.0.0"
QW.DB_VERSION = 1

-------------------------------------------------------------------------------
-- Утилиты
-------------------------------------------------------------------------------
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

function QW.ToB36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = B36:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

function QW.FromB36(s)
    return tonumber(s or "", 36) or 0
end

function QW.Print(...)
    local msg = table.concat({ ... }, " ")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Quest|r|cff66ccffWow|r: " .. msg)
end

-- "Имя-Сервер" для любого имени
function QW.FullName(name)
    if not name or name == "" then return nil end
    name = name:gsub("%s+", "")
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if realm and realm ~= "" then
            name = name .. "-" .. realm
        end
    end
    -- Первая буква имени заглавная (Кириллица в UTF-8 не трогаем)
    local first = name:sub(1, 1)
    if first:match("%l") then name = first:upper() .. name:sub(2) end
    return name
end

function QW.ShortName(full)
    if not full then return "?" end
    return (full:match("^([^-]+)")) or full
end

function QW.ClassColorHex(class)
    local c
    if class and C_ClassColor and C_ClassColor.GetClassColor then
        c = C_ClassColor.GetClassColor(class)
    end
    if not c and class and RAID_CLASS_COLORS then c = RAID_CLASS_COLORS[class] end
    if c and c.GenerateHexColor then return c:GenerateHexColor() end
    if c then return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "ffcccccc"
end

function QW.ClassRGB(class)
    local c
    if class and C_ClassColor and C_ClassColor.GetClassColor then
        c = C_ClassColor.GetClassColor(class)
    end
    if not c and class and RAID_CLASS_COLORS then c = RAID_CLASS_COLORS[class] end
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

function QW.ColoredName(full)
    local ch = QW.db and QW.db.chars[full]
    return "|c" .. QW.ClassColorHex(ch and ch.class) .. QW.ShortName(full) .. "|r"
end

-------------------------------------------------------------------------------
-- Колбэки (простая шина событий внутри аддона)
-------------------------------------------------------------------------------
QW.callbacks = {}
function QW.On(event, fn)
    QW.callbacks[event] = QW.callbacks[event] or {}
    table.insert(QW.callbacks[event], fn)
end
function QW.Fire(event, ...)
    local list = QW.callbacks[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-------------------------------------------------------------------------------
-- SavedVariables
-------------------------------------------------------------------------------
local DEFAULTS = {
    settings = {
        partners = {},          -- { "Имя-Сервер", ... }
        autoSync = true,
        notify = true,          -- сообщать в чат о квестах друга
        hideUntitled = true,    -- скрывать служебные квесты без названия
        scale = 1.0,
        minimap = { angle = 215, hide = false },
    },
    chars = {},                 -- [full] = { class, level, own, history = {{id,t,map,lvl}}, done = {[id]=true}, doneCount, active = {[id]=true}, updated }
    titles = {},                -- [questID] = "название"
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function QW.GetChar(full, create)
    local ch = QW.db.chars[full]
    if not ch and create then
        ch = { history = {}, done = {}, doneCount = 0, active = {}, updated = 0 }
        QW.db.chars[full] = ch
    end
    return ch
end

function QW.IsPartner(full)
    for _, p in ipairs(QW.db.settings.partners) do
        if p == full then return true end
    end
    return false
end

function QW.AddPartner(name)
    local full = QW.FullName(name)
    if not full or full == QW.me then return nil end
    if not QW.IsPartner(full) then
        table.insert(QW.db.settings.partners, full)
    end
    QW.GetChar(full, true)
    QW.Fire("DATA_CHANGED")
    return full
end

function QW.RemovePartner(full)
    local list = QW.db.settings.partners
    for i = #list, 1, -1 do
        if list[i] == full then table.remove(list, i) end
    end
    QW.Fire("DATA_CHANGED")
end

-------------------------------------------------------------------------------
-- Данные текущего персонажа
-------------------------------------------------------------------------------
local function GetAllCompleted()
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        return C_QuestLog.GetAllCompletedQuestIDs() or {}
    end
    local out = {}
    if GetQuestsCompleted then
        local t = GetQuestsCompleted()
        for id in pairs(t or {}) do out[#out + 1] = id end
    end
    return out
end

function QW.RefreshDone()
    local ch = QW.GetChar(QW.me, true)
    local done, n = {}, 0
    for _, id in ipairs(GetAllCompleted()) do
        if not done[id] then
            done[id] = true
            n = n + 1
        end
    end
    -- Квесты из своей истории тоже считаем выполненными
    -- (на случай, если сервер ещё не прислал полный список)
    for _, e in ipairs(ch.history) do
        if not done[e[1]] then done[e[1]] = true; n = n + 1 end
    end
    ch.done, ch.doneCount = done, n
    ch.updated = time()
end

function QW.RefreshActive()
    local ch = QW.GetChar(QW.me, true)
    local active = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 and not info.isHidden then
                active[info.questID] = true
                if info.title and info.title ~= "" then
                    QW.db.titles[info.questID] = info.title
                end
            end
        end
    end
    ch.active = active
end

function QW.CurrentMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
end

local function OnQuestTurnedIn(questID)
    if not questID then return end
    local ch = QW.GetChar(QW.me, true)
    local title = QW.GetTitle(questID)
    if title then QW.db.titles[questID] = title end
    local entry = { questID, time(), QW.CurrentMapID() or 0, UnitLevel("player") or 0 }
    table.insert(ch.history, entry)
    if not ch.done[questID] then
        ch.done[questID] = true
        ch.doneCount = (ch.doneCount or 0) + 1
    end
    ch.active[questID] = nil
    ch.updated = time()
    QW.Fire("QUEST_DONE", QW.me, entry)
    QW.Fire("DATA_CHANGED")
    if QW.Comm then QW.Comm.BroadcastNew(entry, #ch.history) end
end

-------------------------------------------------------------------------------
-- Слэш-команды
-------------------------------------------------------------------------------
SLASH_QUESTWOW1 = "/qw"
SLASH_QUESTWOW2 = "/questwow"
SlashCmdList.QUESTWOW = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        QW.UI.Toggle()
    elseif cmd == "add" and rest ~= "" then
        local full = QW.AddPartner(rest)
        if full then
            QW.Print("Друг добавлен:", full)
            QW.Comm.Hello(full, false)
        end
    elseif cmd == "del" and rest ~= "" then
        QW.RemovePartner(QW.FullName(rest))
        QW.Print("Друг удалён:", QW.FullName(rest))
    elseif cmd == "sync" then
        QW.Comm.HelloAll()
        QW.Print("Синхронизация запущена.")
    elseif cmd == "link" and tonumber(rest) then
        QW.LinkQuest(tonumber(rest))
    elseif cmd == "chain" and tonumber(rest) then
        QW.UI.Show()
        QW.UI.ShowChainFor(tonumber(rest))
    else
        QW.Print("Команды:")
        QW.Print("/qw — открыть окно")
        QW.Print("/qw add Имя[-Сервер] — добавить друга")
        QW.Print("/qw del Имя[-Сервер] — удалить друга")
        QW.Print("/qw sync — синхронизировать")
        QW.Print("/qw link <ID> — линк квеста в чат")
        QW.Print("/qw chain <ID> — цепочка квеста")
    end
end

function QuestWow_OnCompartmentClick()
    QW.UI.Toggle()
end

-------------------------------------------------------------------------------
-- События
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("PLAYER_LEVEL_UP")

local activeTimer
local function ScheduleActiveRefresh()
    if activeTimer then return end
    activeTimer = C_Timer.NewTimer(1.5, function()
        activeTimer = nil
        QW.RefreshActive()
        QW.Fire("DATA_CHANGED")
        if QW.Comm then QW.Comm.BroadcastActive() end
    end)
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        QuestWowDB = QuestWowDB or {}
        ApplyDefaults(QuestWowDB, DEFAULTS)
        QuestWowDB.dbVersion = QW.DB_VERSION
        QW.db = QuestWowDB
    elseif event == "PLAYER_LOGIN" then
        local name, realm = UnitFullName("player")
        realm = (realm and realm ~= "") and realm or GetNormalizedRealmName()
        QW.me = name .. "-" .. realm
        local ch = QW.GetChar(QW.me, true)
        ch.own = true
        ch.class = select(2, UnitClass("player"))
        ch.level = UnitLevel("player")
        ch.faction = UnitFactionGroup("player")
        QW.Fire("LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Список выполненных квестов приходит с сервера не мгновенно
        C_Timer.After(3, function()
            QW.RefreshDone()
            QW.RefreshActive()
            QW.Fire("DATA_CHANGED")
            if QW.db.settings.autoSync and QW.Comm then QW.Comm.HelloAll() end
        end)
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn(arg1)
        ScheduleActiveRefresh()
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        ScheduleActiveRefresh()
    elseif event == "PLAYER_LEVEL_UP" then
        local ch = QW.GetChar(QW.me, true)
        ch.level = arg1 or UnitLevel("player")
    end
end)
