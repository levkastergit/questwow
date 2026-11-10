-- QuestWow: Core — база данных, события, запись выполненных квестов
local ADDON, QW = ...
_G.QuestWow = QW

QW.VERSION = "1.3.0"
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

function QW.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- string.lower/upper в Lua не трогают кириллицу (UTF-8) — переводим А-Я и Ё вручную
function QW.ULower(s)
    s = s:lower()
    s = s:gsub("\208([\144-\175])", function(c)
        local b = c:byte()
        if b < 160 then return "\208" .. string.char(b + 32) end
        return "\209" .. string.char(b - 32)
    end)
    s = s:gsub("\208\129", "\209\145")
    return s
end

-- Первая буква слова заглавная (латиница и кириллица)
local function Cap(word)
    local b1, b2 = word:byte(1, 2)
    if not b1 then return word end
    if b1 >= 97 and b1 <= 122 then
        return string.char(b1 - 32) .. word:sub(2)
    elseif b1 == 208 and b2 and b2 >= 176 and b2 <= 191 then       -- а-п
        return "\208" .. string.char(b2 - 32) .. word:sub(3)
    elseif b1 == 209 and b2 and b2 >= 128 and b2 <= 143 then       -- р-я
        return "\208" .. string.char(b2 + 32) .. word:sub(3)
    elseif b1 == 209 and b2 == 145 then                            -- ё
        return "\208\129" .. word:sub(3)
    end
    return word
end

-------------------------------------------------------------------------------
-- Имена персонажей
-- WoW Forever: серверов нет, у персонажа имя + фамилия. UnitName() возвращает
-- их двумя значениями, а шёпот адресуется как "Имя Фамилия".
-- Обычный WoW: "Имя-Сервер".
-------------------------------------------------------------------------------
QW.surnames = false

function QW.FullName(name)
    if type(name) ~= "string" or QW.IsSecret(name) then return nil end
    name = (name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
    if name == "" then return nil end
    if QW.surnames then
        -- "Имя Фамилия", "Имя-Фамилия", "Имя Фамилия-Что-то" -> "Имя Фамилия"
        local a, b = name:match("^([^%s%-]+)[%s%-]+([^%s%-]+)")
        if a then return Cap(a) .. " " .. Cap(b) end
        return Cap(name)  -- только имя: неполное, шёпот может не дойти
    end
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if realm and realm ~= "" then name = name .. "-" .. realm end
    end
    return Cap(name)
end

-- Ключ для сравнения имён без учёта регистра
function QW.NameKey(name)
    local full = QW.FullName(name)
    return full and QW.ULower(full) or nil
end

function QW.SameName(a, b)
    local ka, kb = QW.NameKey(a), QW.NameKey(b)
    return ka ~= nil and ka == kb
end

-- В режиме фамилий имя без фамилии считается неполным
function QW.IsCompleteName(full)
    if not QW.surnames then return true end
    return full and full:find(" ", 1, true) ~= nil
end

-- Полное имя игрока по юниту ("party1", "target"...)
function QW.UnitId(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local a, b = UnitName(unit)
    if QW.IsSecret(a) or QW.IsSecret(b) then return nil end
    if not a or a == "" or a == UNKNOWNOBJECT then return nil end
    if b and b ~= "" then
        return QW.FullName(a .. (QW.surnames and " " or "-") .. b)
    end
    return QW.FullName(a)
end

function QW.ShortName(full)
    if not full then return "?" end
    return (full:match("^([^%s%-]+)")) or full
end

-- Для показа: в Forever "Имя Фамилия", в обычном WoW просто имя
function QW.DisplayName(full)
    if not full then return "?" end
    if QW.surnames then return full end
    return QW.ShortName(full)
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

-- short = true: только имя (для узких колонок)
function QW.ColoredName(full, short)
    local ch = QW.db and QW.db.chars[full]
    local text = short and QW.ShortName(full) or QW.DisplayName(full)
    return "|c" .. QW.ClassColorHex(ch and ch.class) .. text .. "|r"
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
        chainFilter = "all",    -- all | mine | everyone — какие пройденные цепочки скрывать
        minimap = { angle = 215, hide = false },
    },
    chars = {},                 -- [full] = { class, level, own, history = {{id,t,map,lvl}}, done = {[id]=true}, doneCount, active = {[id]=true}, updated }
    titles = {},                -- [questID] = "название"
    questZones = {},            -- [questID] = "зона" (из заголовков журнала квестов)
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

-- Найти друга по любому написанию имени. Возвращает имя, как оно сохранено.
function QW.FindPartner(name)
    local key = QW.NameKey(name)
    if not key then return nil end
    local partners = QW.db.settings.partners
    for _, p in ipairs(partners) do
        if QW.ULower(p) == key then return p end
    end
    -- Пришло только имя без фамилии: совпадение по имени, если оно однозначно
    if QW.surnames and not key:find(" ", 1, true) then
        local found
        for _, p in ipairs(partners) do
            if QW.ULower(QW.ShortName(p)) == key then
                if found then return nil end
                found = p
            end
        end
        return found
    end
    return nil
end

function QW.IsPartner(name)
    return QW.FindPartner(name) ~= nil
end

function QW.IsMe(name)
    return QW.me ~= nil and QW.SameName(name, QW.me)
end

function QW.AddPartner(name)
    local full = QW.FullName(name)
    if not full or QW.IsMe(full) then return nil end
    local existing = QW.FindPartner(full)
    if not existing and QW.surnames and QW.IsCompleteName(full) then
        -- Был сохранён только по имени ("Лев") — теперь знаем фамилию
        local first = QW.ULower(QW.ShortName(full))
        for _, p in ipairs(QW.db.settings.partners) do
            if not QW.IsCompleteName(p) and QW.ULower(p) == first then existing = p break end
        end
    end
    if existing and existing ~= full and not QW.IsCompleteName(existing) then
        -- Было "Имя", теперь "Имя Фамилия" — переносим данные
        QW.RemovePartner(existing)
        if QW.db.chars[existing] and not QW.db.chars[full] then
            QW.db.chars[full] = QW.db.chars[existing]
        end
        QW.db.chars[existing] = nil
        existing = nil
    end
    if not existing then
        table.insert(QW.db.settings.partners, full)
    else
        full = existing
    end
    QW.GetChar(full, true)
    if not QW.IsCompleteName(full) then
        QW.Print("|cffff6060Внимание:|r в WoW Forever нужно указывать имя и фамилию, например |cffffd100/qw add "
            .. full .. " Фамилия|r. Только по имени сообщения могут не дойти.")
    end
    QW.Fire("DATA_CHANGED")
    return full
end

function QW.RemovePartner(full)
    local list = QW.db.settings.partners
    for i = #list, 1, -1 do
        if QW.SameName(list[i], full) then table.remove(list, i) end
    end
    QW.Fire("DATA_CHANGED")
end

-- Переход со старых ключей "Имя-Сервер" на "Имя Фамилия" (версия 1.0.0)
local function MigrateNames()
    if not QW.surnames then return end
    local chars = QW.db.chars
    local myFirst = QW.ULower(QW.ShortName(QW.me))
    local old = {}
    for full, ch in pairs(chars) do
        if full ~= QW.me and full:find("-", 1, true) and not full:find(" ", 1, true)
            and ch.own and QW.ULower(QW.ShortName(full)) == myFirst then
            old[#old + 1] = full
        end
    end
    for _, full in ipairs(old) do
        local ch = chars[full]
        do
            local cur = chars[QW.me]
            if not cur or #(cur.history or {}) == 0 then
                chars[QW.me] = ch
            else
                for _, e in ipairs(ch.history or {}) do table.insert(cur.history, e) end
                table.sort(cur.history, function(x, y) return x[2] < y[2] end)
            end
            chars[full] = nil
        end
    end
    -- Друзья, добавленные как "Имя-Сервер": оставляем только имя
    local partners = QW.db.settings.partners
    for i, p in ipairs(partners) do
        if p:find("-", 1, true) and not p:find(" ", 1, true) then
            local short = QW.ShortName(p)
            partners[i] = short
            if chars[p] and not chars[short] then chars[short] = chars[p] end
            chars[p] = nil
            QW.Print("Друг |cffffd100" .. short .. "|r сохранён без фамилии. Добавь заново с фамилией: |cffffd100/qw add "
                .. short .. " Фамилия|r")
        end
    end
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
    local header
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and info.isHeader then
                header = info.title
            elseif info and info.questID and info.questID > 0 and not info.isHidden then
                active[info.questID] = true
                if info.title and info.title ~= "" then
                    QW.db.titles[info.questID] = info.title
                end
                -- Заголовок журнала = зона квеста (или категория)
                if header and header ~= "" and not QW.IsSecret(header) then
                    QW.db.questZones[info.questID] = header
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
    elseif cmd == "zone" then
        QW.UI.Show()
        QW.UI.ShowZone(rest ~= "" and rest or nil)
    elseif cmd == "minimap" then
        local mm = QW.db.settings.minimap
        if rest == "reset" then
            mm.angle, mm.free, mm.hide = 215, nil, false
        else
            mm.hide = not mm.hide
        end
        QW.Minimap.Update()
        QW.Print("Кнопка у миникарты: " .. (mm.hide and "скрыта" or "показана"))
    else
        local who = QW.surnames and "Имя Фамилия" or "Имя[-Сервер]"
        QW.Print("Команды:")
        QW.Print("/qw — открыть окно")
        QW.Print("/qw add " .. who .. " — добавить друга")
        QW.Print("/qw del " .. who .. " — удалить друга")
        QW.Print("/qw zone [зона] — квесты по зонам (без имени — текущая)")
        QW.Print("/qw minimap — показать/скрыть кнопку у миникарты (reset — вернуть на место)")
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
        -- В Forever второе значение UnitName("player") — фамилия (в обычном WoW тут nil)
        local first, second = UnitName("player")
        QW.surnames = second ~= nil and second ~= "" and not QW.IsSecret(second)
        if QW.surnames then
            QW.me = QW.FullName(first .. " " .. second)
        else
            local name, realm = UnitFullName("player")
            realm = (realm and realm ~= "") and realm or GetNormalizedRealmName() or ""
            QW.me = QW.FullName(realm ~= "" and (name .. "-" .. realm) or name)
        end
        MigrateNames()
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
        QW.Fire("DATA_CHANGED")   -- список "Можно взять" зависит от уровня
    end
end)
