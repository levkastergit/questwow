-- QuestWow: Comm — синхронизация между тобой и другом через скрытые аддон-сообщения (WHISPER)
local _, QW = ...
local Comm = {}
QW.Comm = Comm

local PREFIX = "QuestWow"
local PROTO = 1
local MAX_LEN = 240           -- лимит аддон-сообщения 255 байт, оставляем запас
local SEND_INTERVAL = 0.3     -- пауза между сообщениями
local THROTTLE_BACKOFF = 2.0  -- пауза, если клиент сказал «слишком часто»

local ToB36, FromB36 = QW.ToB36, QW.FromB36

Comm.online = {}              -- [full] = time() последнего сообщения от друга
Comm.lastSent = {}            -- [full] = GetTime() последней отправки
Comm.progress = {}            -- [full] = { got, total } для индикатора

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-------------------------------------------------------------------------------
-- Очередь отправки
-------------------------------------------------------------------------------
local queue = {}
local sending = false
local R = Enum and Enum.SendAddonMessageResult

local function ResultOK(r)
    if r == nil or r == true then return true end
    if r == false then return false end
    if R and R.Success ~= nil then return r == R.Success end
    return r == 0
end

local function ResultThrottled(r)
    if not R then return false end
    return r == R.AddonMessageThrottle or r == R.ChannelThrottle
end

local function Pump()
    if #queue == 0 then sending = false return end
    sending = true
    local item = queue[1]
    local okCall, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "WHISPER", item.target)
    if not okCall then r = false end
    if ResultThrottled(r) then
        C_Timer.After(THROTTLE_BACKOFF, Pump)
        return
    end
    table.remove(queue, 1)
    Comm.lastSent[item.target] = GetTime()
    if not ResultOK(r) then
        -- Например, в подземелье во время боя с боссом — сообщения заблокированы
        Comm.blockedUntil = GetTime() + 10
    end
    C_Timer.After(SEND_INTERVAL, Pump)
end

local function Send(target, msg)
    queue[#queue + 1] = { target = target, msg = msg }
    if not sending then Pump() end
end

local function DropQueueFor(target)
    for i = #queue, 1, -1 do
        if queue[i].target == target then table.remove(queue, i) end
    end
end

-- Разбивает список строк на сообщения: header .. item1 sep item2 ...
local function SendChunked(target, headerFn, items, sep)
    local chunks, cur, len = {}, {}, 0
    for _, it in ipairs(items) do
        local add = #it + (#cur > 0 and 1 or 0)
        if len + add > MAX_LEN - 24 and #cur > 0 then
            chunks[#chunks + 1] = cur
            cur, len = {}, 0
            add = #it
        end
        cur[#cur + 1] = it
        len = len + add
    end
    if #cur > 0 or #chunks == 0 then chunks[#chunks + 1] = cur end
    for i, c in ipairs(chunks) do
        Send(target, headerFn(i, #chunks) .. table.concat(c, sep))
    end
    return #chunks
end

-------------------------------------------------------------------------------
-- Кодирование
-------------------------------------------------------------------------------
local function EncodeEntry(e)
    return ToB36(e[1]) .. "," .. ToB36(e[2]) .. "," .. ToB36(e[3] or 0) .. "," .. ToB36(e[4] or 0)
end

local function DecodeEntry(s)
    local a, b, c, d = s:match("^(%w+),(%w+),(%w+),(%w+)$")
    if not a then return nil end
    return { FromB36(a), FromB36(b), FromB36(c), FromB36(d) }
end

-------------------------------------------------------------------------------
-- Друзья онлайн?
-------------------------------------------------------------------------------
local function KnownOffline(full)
    if not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
    local info = C_FriendList.GetFriendInfo(QW.ShortName(full)) or C_FriendList.GetFriendInfo(full)
    if info and info.connected == false then return true end
    return false
end

function Comm.IsOnline(full)
    local t = Comm.online[full]
    return t and (time() - t) < 600
end

-------------------------------------------------------------------------------
-- Исходящие
-------------------------------------------------------------------------------
function Comm.Hello(target, isReply)
    if not QW.me or not target or target == QW.me then return end
    if not isReply and KnownOffline(target) then return end
    local ch = QW.GetChar(QW.me, true)
    Send(target, table.concat({
        "H", PROTO, ch.class or "", ch.level or 0, #ch.history, ch.doneCount or 0, isReply and 1 or 0,
    }, ":"))
end

function Comm.HelloAll()
    for _, p in ipairs(QW.db.settings.partners) do
        Comm.Hello(p, false)
    end
end

local function SendHistory(target, from)
    local h = QW.GetChar(QW.me, true).history
    from = math.max(1, from or 1)
    if from > #h then return end
    local items = {}
    for i = from, #h do items[#items + 1] = EncodeEntry(h[i]) end
    -- В каждом куске свой стартовый индекс
    local idx = from
    local chunks, cur, len = {}, {}, 0
    for _, it in ipairs(items) do
        if len + #it + 1 > MAX_LEN - 16 and #cur > 0 then
            chunks[#chunks + 1] = { start = idx, list = cur }
            idx = idx + #cur
            cur, len = {}, 0
        end
        cur[#cur + 1] = it
        len = len + #it + 1
    end
    if #cur > 0 then chunks[#chunks + 1] = { start = idx, list = cur } end
    for _, c in ipairs(chunks) do
        Send(target, "D:" .. c.start .. ":" .. #h .. ":" .. table.concat(c.list, ";"))
    end
end

local function SendDone(target)
    local ch = QW.GetChar(QW.me, true)
    local items = {}
    for id in pairs(ch.done) do items[#items + 1] = ToB36(id) end
    table.sort(items)
    SendChunked(target, function(i, n) return "C:" .. i .. ":" .. n .. ":" end, items, ",")
end

local function SendActive(target)
    local ch = QW.GetChar(QW.me, true)
    local items = {}
    for id in pairs(ch.active or {}) do items[#items + 1] = ToB36(id) end
    SendChunked(target, function(i, n) return "A:" .. i .. ":" .. n .. ":" end, items, ",")
end

function Comm.BroadcastNew(entry, index)
    for _, p in ipairs(QW.db.settings.partners) do
        if Comm.IsOnline(p) then
            Send(p, "N:" .. index .. ":" .. EncodeEntry(entry))
        end
    end
end

function Comm.BroadcastActive()
    for _, p in ipairs(QW.db.settings.partners) do
        if Comm.IsOnline(p) then SendActive(p) end
    end
end

-------------------------------------------------------------------------------
-- Входящие
-------------------------------------------------------------------------------
local function MarkDone(ch, id)
    if not ch.done[id] then
        ch.done[id] = true
        ch.doneCount = (ch.doneCount or 0) + 1
    end
end

local handlers = {}

handlers.H = function(sender, f)
    local proto, class, level, histCount, doneCount, isReply =
        tonumber(f[2]), f[3], tonumber(f[4]), tonumber(f[5]) or 0, tonumber(f[6]) or 0, f[7] == "1"
    if not proto then return end
    local ch = QW.GetChar(sender, true)
    if class and class ~= "" then ch.class = class end
    ch.level = level or ch.level
    ch.remoteHist, ch.remoteDone = histCount, doneCount
    if #ch.history > histCount then
        -- У друга история стала короче (сброс данных) — перекачиваем заново
        ch.history = {}
    end
    if #ch.history < histCount then
        Send(sender, "RH:" .. (#ch.history + 1))
    end
    if (ch.doneCount or 0) ~= doneCount then
        Send(sender, "RD")
    end
    Send(sender, "RA")
    if not isReply then Comm.Hello(sender, true) end
    QW.Fire("DATA_CHANGED")
end

handlers.RH = function(sender, f) SendHistory(sender, tonumber(f[2]) or 1) end
handlers.RD = function(sender) SendDone(sender) end
handlers.RA = function(sender) SendActive(sender) end

handlers.D = function(sender, f, raw)
    local start, total = tonumber(f[2]), tonumber(f[3])
    local body = raw:match("^D:%d+:%d+:(.*)$")
    if not start or not body then return end
    local ch = QW.GetChar(sender, true)
    if start > #ch.history + 1 then
        Send(sender, "RH:" .. (#ch.history + 1))
        return
    end
    local i = start
    for s in body:gmatch("[^;]+") do
        local e = DecodeEntry(s)
        if e then
            ch.history[i] = e
            MarkDone(ch, e[1])
            i = i + 1
        end
    end
    for k = #ch.history, i, -1 do
        if k > (total or k) then ch.history[k] = nil end
    end
    ch.updated = time()
    Comm.progress[sender] = { got = #ch.history, total = total or #ch.history }
    QW.Fire("DATA_CHANGED")
    QW.Fire("SYNC_PROGRESS", sender)
end

local function ReceiveSet(sender, f, raw, kind)
    local seq, total = tonumber(f[2]), tonumber(f[3])
    local body = raw:match("^%a:%d+:%d+:(.*)$") or ""
    if not seq or not total then return end
    local ch = QW.GetChar(sender, true)
    local tmpKey = "_tmp" .. kind
    if seq == 1 or not ch[tmpKey] then ch[tmpKey] = {} end
    for s in body:gmatch("[^,]+") do ch[tmpKey][FromB36(s)] = true end
    if seq >= total then
        local set = ch[tmpKey]
        ch[tmpKey] = nil
        if kind == "C" then
            for _, e in ipairs(ch.history) do set[e[1]] = true end
            local n = 0
            for _ in pairs(set) do n = n + 1 end
            ch.done, ch.doneCount = set, n
        else
            ch.active = set
        end
        ch.updated = time()
        QW.Fire("DATA_CHANGED")
    end
    if kind == "C" then
        Comm.progress[sender] = { got = seq, total = total, set = true }
        QW.Fire("SYNC_PROGRESS", sender)
    end
end

handlers.C = function(sender, f, raw) ReceiveSet(sender, f, raw, "C") end
handlers.A = function(sender, f, raw) ReceiveSet(sender, f, raw, "A") end

handlers.N = function(sender, f, raw)
    local index = tonumber(f[2])
    local e = DecodeEntry(raw:match("^N:%d+:(.+)$") or "")
    if not index or not e then return end
    local ch = QW.GetChar(sender, true)
    if index == #ch.history + 1 then
        ch.history[index] = e
    elseif index > #ch.history + 1 then
        Send(sender, "RH:" .. (#ch.history + 1))
    end
    MarkDone(ch, e[1])
    if ch.active then ch.active[e[1]] = nil end
    ch.updated = time()
    QW.Fire("QUEST_DONE", sender, e)
    QW.Fire("DATA_CHANGED")
    if QW.db.settings.notify then
        local link = QW.GetLink(e[1]) or ("квест #" .. e[1])
        QW.Print(QW.ColoredName(sender) .. " выполнил(а) " .. link)
    end
end

local notPartnerWarned = {}

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        return
    end
    if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then return end
    if prefix ~= PREFIX or channel ~= "WHISPER" then return end
    local full = QW.FullName(sender)
    if not full or full == QW.me then return end
    if not QW.IsPartner(full) then
        if not notPartnerWarned[full] then
            notPartnerWarned[full] = true
            QW.Print(full .. " хочет поделиться квестами. Чтобы принять: |cffffd100/qw add " .. full .. "|r")
        end
        return
    end
    Comm.online[full] = time()
    local f = { strsplit(":", msg) }
    local h = handlers[f[1]]
    if h then
        local ok, err = pcall(h, full, f, msg)
        if not ok then geterrorhandler()(err) end
    end
end)

-------------------------------------------------------------------------------
-- Прячем системное «Персонаж не найден», если это наш скрытый пинг другу
-------------------------------------------------------------------------------
local notFoundPattern
local function BuildPattern()
    if notFoundPattern or not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
    local p = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    notFoundPattern = "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end

local function SystemFilter(_, _, msg)
    if IsSecret(msg) or type(msg) ~= "string" then return false end
    BuildPattern()
    if not notFoundPattern then return false end
    local name = msg:match(notFoundPattern)
    if not name then return false end
    local full = QW.FullName(name)
    local t = full and Comm.lastSent[full]
    if t and GetTime() - t < 10 then
        Comm.online[full] = nil
        DropQueueFor(full)
        QW.Fire("DATA_CHANGED")
        return true
    end
    return false
end

if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
    ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter)
elseif ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter)
end
