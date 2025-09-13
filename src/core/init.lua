-- Luacord - Enhanced Discord API Library for Lua
-- Version: 2.0.0
-- Modern, feature-rich Discord bot library

local Luacord = {
    VERSION = "2.0.0",
    API_VERSION = 10,
    GITHUB = "https://github.com/luacord/luacord"
}

-- =============================================================================
-- CORE UTILITIES & CONSTANTS
-- =============================================================================

-- Enhanced Logger with file output and formatting
local Logger = {}
Logger.__index = Logger

local LOG_LEVELS = {
    TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5
}

function Logger:new(options)
    options = options or {}
    return setmetatable({
        level = options.level or LOG_LEVELS.INFO,
        file = options.file,
        timestamp = options.timestamp ~= false,
        colors = options.colors ~= false and {
            TRACE = "\27[90m", DEBUG = "\27[36m", INFO = "\27[32m",
            WARN = "\27[33m", ERROR = "\27[31m", FATAL = "\27[35m",
            RESET = "\27[0m", BOLD = "\27[1m"
        } or {}
    }, self)
end

function Logger:log(level, message, ...)
    if LOG_LEVELS[level] < self.level then return end
    
    local timestamp = self.timestamp and ("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "]") or ""
    local color = self.colors[level] or ""
    local reset = self.colors.RESET or ""
    local bold = self.colors.BOLD or ""
    
    local formatted = string.format(message, ...)
    local output = string.format("%s %s[%s]%s %s%s%s", 
        timestamp, color, level, reset, bold, formatted, reset)
    
    print(output)
    
    if self.file then
        local file = io.open(self.file, "a")
        if file then
            file:write(timestamp .. " [" .. level .. "] " .. formatted .. "\n")
            file:close()
        end
    end
end

function Logger:trace(...) self:log("TRACE", ...) end
function Logger:debug(...) self:log("DEBUG", ...) end
function Logger:info(...) self:log("INFO", ...) end
function Logger:warn(...) self:log("WARN", ...) end
function Logger:error(...) self:log("ERROR", ...) end
function Logger:fatal(...) self:log("FATAL", ...) end

-- Enhanced Configuration Manager
local Config = {}
Config.__index = Config

function Config:new(data)
    return setmetatable({
        data = data or {},
        watchers = {},
        schema = {}
    }, self)
end

function Config:get(path, default)
    local keys = type(path) == "string" and self:_splitPath(path) or path
    local value = self.data
    
    for _, key in ipairs(keys) do
        if type(value) ~= "table" or value[key] == nil then
            return default
        end
        value = value[key]
    end
    
    return value
end

function Config:set(path, value)
    local keys = type(path) == "string" and self:_splitPath(path) or path
    local current = self.data
    
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    
    local lastKey = keys[#keys]
    local oldValue = current[lastKey]
    current[lastKey] = value
    
    -- Trigger watchers
    for _, watcher in ipairs(self.watchers[path] or {}) do
        watcher(value, oldValue, path)
    end
    
    return self
end

function Config:watch(path, callback)
    if not self.watchers[path] then
        self.watchers[path] = {}
    end
    table.insert(self.watchers[path], callback)
    return self
end

function Config:validate(schema)
    self.schema = schema
    return self:_validate(self.data, schema, "")
end

function Config:_splitPath(path)
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        table.insert(keys, key)
    end
    return keys
end

function Config:_validate(data, schema, path)
    for key, rule in pairs(schema) do
        local fullPath = path == "" and key or (path .. "." .. key)
        local value = data[key]
        
        if rule.required and value == nil then
            error("Missing required config: " .. fullPath)
        end
        
        if value ~= nil and rule.type and type(value) ~= rule.type then
            error("Invalid type for " .. fullPath .. ": expected " .. rule.type .. ", got " .. type(value))
        end
        
        if rule.validator and not rule.validator(value) then
            error("Validation failed for " .. fullPath)
        end
        
        if rule.children and type(value) == "table" then
            self:_validate(value, rule.children, fullPath)
        end
    end
    return true
end

-- Advanced Snowflake utilities
local Snowflake = {}

local DISCORD_EPOCH = 1420070400000
local WORKER_SHIFT = 17
local PROCESS_SHIFT = 12
local INCREMENT_MASK = 0xFFF

function Snowflake.parse(id)
    local num = tonumber(id)
    if not num then return nil end
    
    local timestamp = bit32.rshift(num, 22) + DISCORD_EPOCH
    local worker = bit32.band(bit32.rshift(num, WORKER_SHIFT), 0x1F)
    local process = bit32.band(bit32.rshift(num, PROCESS_SHIFT), 0x1F)
    local increment = bit32.band(num, INCREMENT_MASK)
    
    return {
        id = id,
        timestamp = timestamp,
        date = os.date("!%Y-%m-%d %H:%M:%S", timestamp / 1000),
        worker = worker,
        process = process,
        increment = increment,
        binary = string.format("%064s", Snowflake.toBinary(num))
    }
end

function Snowflake.generate(timestamp, worker, process, increment)
    timestamp = timestamp or (os.time() * 1000)
    worker = worker or 1
    process = process or 0
    increment = increment or 0
    
    local adjustedTimestamp = timestamp - DISCORD_EPOCH
    local id = bit32.lshift(adjustedTimestamp, 22)
    id = bit32.bor(id, bit32.lshift(worker, WORKER_SHIFT))
    id = bit32.bor(id, bit32.lshift(process, PROCESS_SHIFT))
    id = bit32.bor(id, increment)
    
    return tostring(id)
end

function Snowflake.toBinary(num)
    if num == 0 then return "0" end
    local binary = ""
    while num > 0 do
        binary = (num % 2) .. binary
        num = math.floor(num / 2)
    end
    return binary
end

function Snowflake.age(id)
    local parsed = Snowflake.parse(id)
    if not parsed then return nil end
    return os.time() * 1000 - parsed.timestamp
end

function Snowflake.isValid(id)
    local num = tonumber(id)
    return num and num > 0 and num < 9223372036854775807 -- Max int64
end

-- Enhanced Permission system
local Permissions = {
    -- Basic permissions
    CREATE_INSTANT_INVITE = 1,
    KICK_MEMBERS = 2,
    BAN_MEMBERS = 4,
    ADMINISTRATOR = 8,
    MANAGE_CHANNELS = 16,
    MANAGE_GUILD = 32,
    ADD_REACTIONS = 64,
    VIEW_AUDIT_LOG = 128,
    PRIORITY_SPEAKER = 256,
    STREAM = 512,
    VIEW_CHANNEL = 1024,
    SEND_MESSAGES = 2048,
    SEND_TTS_MESSAGES = 4096,
    MANAGE_MESSAGES = 8192,
    EMBED_LINKS = 16384,
    ATTACH_FILES = 32768,
    READ_MESSAGE_HISTORY = 65536,
    MENTION_EVERYONE = 131072,
    USE_EXTERNAL_EMOJIS = 262144,
    VIEW_GUILD_INSIGHTS = 524288,
    CONNECT = 1048576,
    SPEAK = 2097152,
    MUTE_MEMBERS = 4194304,
    DEAFEN_MEMBERS = 8388608,
    MOVE_MEMBERS = 16777216,
    USE_VAD = 33554432,
    CHANGE_NICKNAME = 67108864,
    MANAGE_NICKNAMES = 134217728,
    MANAGE_ROLES = 268435456,
    MANAGE_WEBHOOKS = 536870912,
    MANAGE_EMOJIS_AND_STICKERS = 1073741824,
    USE_APPLICATION_COMMANDS = 2147483648,
    REQUEST_TO_SPEAK = 4294967296,
    MANAGE_EVENTS = 8589934592,
    MANAGE_THREADS = 17179869184,
    CREATE_PUBLIC_THREADS = 34359738368,
    CREATE_PRIVATE_THREADS = 68719476736,
    USE_EXTERNAL_STICKERS = 137438953472,
    SEND_MESSAGES_IN_THREADS = 274877906944,
    USE_EMBEDDED_ACTIVITIES = 549755813888,
    MODERATE_MEMBERS = 1099511627776
}

function Permissions.has(permissions, permission)
    return bit32.band(permissions, permission) == permission
end

function Permissions.add(permissions, permission)
    return bit32.bor(permissions, permission)
end

function Permissions.remove(permissions, permission)
    return bit32.band(permissions, bit32.bnot(permission))
end

function Permissions.toArray(permissions)
    local result = {}
    for name, value in pairs(Permissions) do
        if type(value) == "number" and Permissions.has(permissions, value) then
            table.insert(result, name)
        end
    end
    return result
end

-- Enhanced Color utilities
local Colors = {
    -- Standard colors
    DEFAULT = 0x000000, WHITE = 0xFFFFFF, AQUA = 0x1ABC9C,
    GREEN = 0x57F287, BLUE = 0x3498DB, YELLOW = 0xFEE75C,
    PURPLE = 0x9B59B6, LUMINOUS_VIVID_PINK = 0xE91E63,
    FUCHSIA = 0xEB459E, GOLD = 0xF1C40F, ORANGE = 0xE67E22,
    RED = 0xED4245, GREY = 0x95A5A6, NAVY = 0x34495E,
    
    -- Discord brand colors
    BLURPLE = 0x5865F2, GREYPLE = 0x99AAB5,
    DARK_BUT_NOT_BLACK = 0x2C2D31, NOT_QUITE_BLACK = 0x23272A,
    
    -- Status colors
    ONLINE = 0x43B581, IDLE = 0xFAA61A, DND = 0xF04747,
    OFFLINE = 0x747F8D, INVISIBLE = 0x747F8D
}

function Colors.random()
    return math.random(0, 0xFFFFFF)
end

function Colors.fromHex(hex)
    return tonumber(hex:gsub("#", ""), 16)
end

function Colors.toHex(color)
    return string.format("#%06X", color)
end

function Colors.fromRGB(r, g, b)
    return bit32.lshift(r, 16) + bit32.lshift(g, 8) + b
end

function Colors.toRGB(color)
    return {
        r = bit32.rshift(color, 16),
        g = bit32.band(bit32.rshift(color, 8), 0xFF),
        b = bit32.band(color, 0xFF)
    }
end

-- Gateway Intents
local Intents = {
    GUILDS = 1,
    GUILD_MEMBERS = 2,
    GUILD_BANS = 4,
    GUILD_EMOJIS_AND_STICKERS = 8,
    GUILD_INTEGRATIONS = 16,
    GUILD_WEBHOOKS = 32,
    GUILD_INVITES = 64,
    GUILD_VOICE_STATES = 128,
    GUILD_PRESENCES = 256,
    GUILD_MESSAGES = 512,
    GUILD_MESSAGE_REACTIONS = 1024,
    GUILD_MESSAGE_TYPING = 2048,
    DIRECT_MESSAGES = 4096,
    DIRECT_MESSAGE_REACTIONS = 8192,
    DIRECT_MESSAGE_TYPING = 16384,
    MESSAGE_CONTENT = 32768,
    GUILD_SCHEDULED_EVENTS = 65536,
    AUTO_MODERATION_CONFIGURATION = 1048576,
    AUTO_MODERATION_EXECUTION = 2097152
}

Intents.ALL = 0
for _, value in pairs(Intents) do
    if type(value) == "number" then
        Intents.ALL = bit32.bor(Intents.ALL, value)
    end
end

Intents.DEFAULT = bit32.bor(
    Intents.GUILDS,
    Intents.GUILD_MESSAGES,
    Intents.GUILD_MESSAGE_REACTIONS,
    Intents.DIRECT_MESSAGES,
    Intents.DIRECT_MESSAGE_REACTIONS
)

-- =============================================================================
-- EVENT SYSTEM
-- =============================================================================

local EventEmitter = {}
EventEmitter.__index = EventEmitter

function EventEmitter:new()
    return setmetatable({
        _events = {},
        _maxListeners = 10,
        _captureRejections = false
    }, self)
end

function EventEmitter:on(event, listener)
    if type(listener) ~= "function" then
        error("Listener must be a function", 2)
    end
    
    if not self._events[event] then
        self._events[event] = {}
    end
    
    if #self._events[event] >= self._maxListeners then
        self:emit("maxListenersExceeded", event, #self._events[event])
    end
    
    table.insert(self._events[event], listener)
    self:emit("newListener", event, listener)
    return self
end

function EventEmitter:once(event, listener)
    local function wrapper(...)
        self:removeListener(event, wrapper)
        return listener(...)
    end
    wrapper._originalListener = listener
    return self:on(event, wrapper)
end

function EventEmitter:emit(event, ...)
    local listeners = self._events[event]
    if not listeners or #listeners == 0 then
        if event == "error" then
            local err = ...
            error("Unhandled error event: " .. tostring(err), 2)
        end
        return false
    end
    
    -- Copy listeners array to avoid issues if listeners are modified during emit
    local listenersCopy = {}
    for i, listener in ipairs(listeners) do
        listenersCopy[i] = listener
    end
    
    for _, listener in ipairs(listenersCopy) do
        local success, err = pcall(listener, ...)
        if not success then
            if self._captureRejections then
                self:emit("error", err)
            else
                error("Error in event listener for '" .. event .. "': " .. tostring(err), 2)
            end
        end
    end
    
    return true
end

function EventEmitter:removeListener(event, listener)
    local listeners = self._events[event]
    if not listeners then return self end
    
    for i, l in ipairs(listeners) do
        if l == listener or (l._originalListener == listener) then
            table.remove(listeners, i)
            self:emit("removeListener", event, listener)
            break
        end
    end
    
    if #listeners == 0 then
        self._events[event] = nil
    end
    
    return self
end

function EventEmitter:removeAllListeners(event)
    if event then
        local listeners = self._events[event]
        if listeners then
            for _, listener in ipairs(listeners) do
                self:emit("removeListener", event, listener)
            end
            self._events[event] = nil
        end
    else
        for eventName, listeners in pairs(self._events) do
            for _, listener in ipairs(listeners) do
                self:emit("removeListener", eventName, listener)
            end
        end
        self._events = {}
    end
    return self
end

function EventEmitter:setMaxListeners(n)
    self._maxListeners = n
    return self
end

function EventEmitter:listenerCount(event)
    local listeners = self._events[event]
    return listeners and #listeners or 0
end

function EventEmitter:listeners(event)
    local listeners = self._events[event]
    return listeners and {table.unpack(listeners)} or {}
end

-- =============================================================================
-- ADVANCED STRUCTURES
-- =============================================================================

-- Base structure with caching and validation
local Base = {}
Base.__index = Base

function Base:new(data, client)
    local obj = setmetatable({
        id = data.id,
        client = client,
        _data = data,
        _lastUpdated = os.time()
    }, self)
    obj:_patch(data)
    return obj
end

function Base:_patch(data)
    for key, value in pairs(data) do
        if key ~= "id" and key ~= "client" and key ~= "_data" then
            self[key] = value
        end
    end
    self._data = data
    self._lastUpdated = os.time()
end

function Base:equals(other)
    return other and self.id == other.id
end

function Base:toString()
    return self.id
end

function Base:valueOf()
    return self.id
end

function Base:toJSON()
    return self._data
end

function Base:_clone()
    return self.constructor and self.constructor:new(self._data, self.client) or nil
end

-- Enhanced User structure
local User = setmetatable({}, Base)
User.__index = User

function User:new(data, client)
    local user = Base.new(self, data, client)
    user.username = data.username
    user.discriminator = data.discriminator
    user.avatar = data.avatar
    user.bot = data.bot or false
    user.system = data.system or false
    user.mfaEnabled = data.mfa_enabled or false
    user.banner = data.banner
    user.accentColor = data.accent_color
    user.locale = data.locale
    user.verified = data.verified
    user.email = data.email
    user.flags = data.flags or 0
    user.premiumType = data.premium_type or 0
    user.publicFlags = data.public_flags or 0
    user.globalName = data.global_name
    return user
end

function User:get tag()
    if self.discriminator == "0" then
        return self.username
    end
    return string.format("%s#%s", self.username, self.discriminator)
end

function User:get displayName()
    return self.globalName or self.username
end

function User:avatarURL(options)
    options = options or {}
    if not self.avatar then
        local index = self.discriminator == "0" and 
            ((tonumber(self.id) >> 22) % 6) or 
            (tonumber(self.discriminator) % 5)
        return string.format("https://cdn.discordapp.com/embed/avatars/%d.png", index)
    end
    
    local format = options.format or (self.avatar:sub(1, 2) == "a_" and "gif" or "png")
    local size = math.min(options.size or 128, 4096)
    return string.format("https://cdn.discordapp.com/avatars/%s/%s.%s?size=%d",
        self.id, self.avatar, format, size)
end

function User:bannerURL(options)
    if not self.banner then return nil end
    options = options or {}
    local format = options.format or (self.banner:sub(1, 2) == "a_" and "gif" or "png")
    local size = math.min(options.size or 512, 4096)
    return string.format("https://cdn.discordapp.com/banners/%s/%s.%s?size=%d",
        self.id, self.banner, format, size)
end

function User:defaultAvatarURL()
    local index = self.discriminator == "0" and 
        ((tonumber(self.id) >> 22) % 6) or 
        (tonumber(self.discriminator) % 5)
    return string.format("https://cdn.discordapp.com/embed/avatars/%d.png", index)
end

function User:hasFlag(flag)
    return bit32.band(self.flags or 0, flag) == flag
end

function User:send(content, options)
    return self.client:createDM(self.id):then(function(channel)
        return channel:send(content, options)
    end)
end

-- Enhanced Channel structure
local Channel = setmetatable({}, Base)
Channel.__index = Channel

local ChannelTypes = {
    GUILD_TEXT = 0, DM = 1, GUILD_VOICE = 2, GROUP_DM = 3,
    GUILD_CATEGORY = 4, GUILD_NEWS = 5, GUILD_STORE = 6,
    GUILD_NEWS_THREAD = 10, GUILD_PUBLIC_THREAD = 11,
    GUILD_PRIVATE_THREAD = 12, GUILD_STAGE_VOICE = 13,
    GUILD_DIRECTORY = 14, GUILD_FORUM = 15
}

function Channel:new(data, client)
    local channel = Base.new(self, data, client)
    channel.type = data.type
    channel.name = data.name
    channel.position = data.position
    channel.permissionOverwrites = data.permission_overwrites or {}
    channel.topic = data.topic
    channel.nsfw = data.nsfw or false
    channel.lastMessageId = data.last_message_id
    channel.bitrate = data.bitrate
    channel.userLimit = data.user_limit
    channel.rateLimitPerUser = data.rate_limit_per_user or 0
    channel.recipients = data.recipients or {}
    channel.icon = data.icon
    channel.ownerId = data.owner_id
    channel.applicationId = data.application_id
    channel.parentId = data.parent_id
    channel.lastPinTimestamp = data.last_pin_timestamp
    channel.rtcRegion = data.rtc_region
    channel.videoQualityMode = data.video_quality_mode
    channel.messageCount = data.message_count
    channel.memberCount = data.member_count
    channel.threadMetadata = data.thread_metadata
    channel.guildId = data.guild_id
    return channel
end

function Channel:get guild()
    return self.guildId and self.client.guilds:get(self.guildId) or nil
end

function Channel:get parent()
    return self.parentId and self.client.channels:get(self.parentId) or nil
end

function Channel:isText()
    return self.type == ChannelTypes.GUILD_TEXT or 
           self.type == ChannelTypes.DM or 
           self.type == ChannelTypes.GROUP_DM or
           self.type == ChannelTypes.GUILD_NEWS
end

function Channel:isVoice()
    return self.type == ChannelTypes.GUILD_VOICE or 
           self.type == ChannelTypes.GUILD_STAGE_VOICE
end

function Channel:isDM()
    return self.type == ChannelTypes.DM or self.type == ChannelTypes.GROUP_DM
end

function Channel:isThread()
    return self.type >= 10 and self.type <= 12
end

function Channel:isCategory()
    return self.type == ChannelTypes.GUILD_CATEGORY
end

function Channel:isNews()
    return self.type == ChannelTypes.GUILD_NEWS
end

function Channel:send(content, options)
    if not self:isText() then
        error("Cannot send messages to this channel type")
    end
    return self.client.rest:createMessage(self.id, content, options)
end

function Channel:bulkDelete(messages, options)
    return self.client.rest:bulkDeleteMessages(self.id, messages, options)
end

function Channel:fetchMessage(messageId)
    return self.client.rest:getMessage(self.id, messageId)
end

function Channel:fetchMessages(options)
    return self.client.rest:getChannelMessages(self.id, options)
end

function Channel:startTyping()
    return self.client.rest:triggerTypingIndicator(self.id)
end

function Channel:createInvite(options)
    return self.client.rest:createChannelInvite(self.id, options)
end

function Channel:fetchInvites()
    return self.client.rest:getChannelInvites(self.id)
end

-- Enhanced Message structure
local Message = setmetatable({}, Base)
Message.__index = Message

function Message:new(data, client)
    local message = Base.new(self, data, client)
    message.channelId = data.channel_id
    message.guildId = data.guild_id
    message.content = data.content or ""
    message.timestamp = data.timestamp
    message.editedTimestamp = data.edited_timestamp
    message.tts = data.tts or false
    message.mentionEveryone = data.mention_everyone or false
    message.mentions = {}
    message.mentionRoles = data.mention_roles or {}
    message.mentionChannels = data.mention_channels or {}
    message.attachments = data.attachments or {}
    message.embeds = data.embeds or {}
    message.reactions = data.reactions or {}
    message.nonce = data.nonce
    message.pinned = data.pinned or false
    message.webhookId = data.webhook_id
    message.type = data.type or 0
    message.activity = data.activity
    message.application = data.application
    message.applicationId = data.application_id
    message.messageReference = data.message_reference
    message.flags = data.flags or 0
    message.referencedMessage = data.referenced_message
    message.interaction = data.interaction
    message.thread = data.thread
    message.components = data.components or {}
    message.stickerItems = data.sticker_items or {}
    
    -- Parse author
    if data.author then
        message.author = User:new(data.author, client)
    end
    
    -- Parse mentions
    if data.mentions then
        for _, userData in ipairs(data.mentions) do
            table.insert(message.mentions, User:new(userData, client))
        end
    end
    
    return message
end

function Message:get channel()
    return self.client.channels:get(self.channelId)
end

function Message:get guild()
    return self.guildId and self.client.guilds:get(self.guildId) or nil
end

function Message:get url()
    local guildPart = self.guildId and self.guildId or "@me"
    return string.format("https://discord.com/channels/%s/%s/%s",
        guildPart, self.channelId, self.id)
end

function Message:get createdAt()
    local snowflake = Snowflake.parse(self.id)
    return snowflake and snowflake.timestamp or nil
end

function Message:get editedAt()
    return self.editedTimestamp
end

function Message:get partial()
    return not self.content and not self.author
end

function Message:reply(content, options)
    options = options or {}
    options.messageReference = {
        messageId = self.id,
        channelId = self.channelId,
        guildId = self.guildId,
        failIfNotExists = options.failIfNotExists or false
    }
    return self.channel:send(content, options)
end

function Message:edit(content, options)
    if self.author.id ~= self.client.user.id then
        error("Cannot edit messages from other users")
    end
    return self.client.rest:editMessage(self.channelId, self.id, content, options)
end

function Message:delete(reason)
    return self.client.rest:deleteMessage(self.channelId, self.id, reason)
end

function Message:react(emoji)
    return self.client.rest:createReaction(self.channelId, self.id, emoji)
end

function Message:removeReaction(emoji, user)
    return self.client.rest:deleteReaction(self.channelId, self.id, emoji, user)
end

function Message:pin(reason)
    return self.client.rest:pinMessage(self.channelId, self.id, reason)
end

function Message:unpin(reason)
    return self.client.rest:unpinMessage(self.channelId, self.id, reason)
end

function Message:crosspost()
    return self.client.rest:crosspostMessage(self.channelId, self.id)
end

function Message:startThread(options)
    return self.client.rest:startThreadFromMessage(self.channelId, self.id, options)
end

function Message:fetchReference()
    if not self.messageReference then return nil end
    local ref = self.messageReference
    return self.client.rest:getMessage(ref.channelId, ref.messageId)
end

-- Enhanced Embed Builder
local Embed = {}
Embed.__index = Embed

function Embed:new(data)
    return setmetatable({
        title = data and data.title,
        type = "rich",
        description = data and data.description,
        url = data and data.url,
        timestamp = data and data.timestamp,
        color = data and data.color,
        footer = data and data.footer,
        image = data and data.image,
        thumbnail = data and data.thumbnail,
        video = data and data.video,
        provider = data and data.provider,
        author = data and data.author,
        fields = data and data.fields or {}
    }, self)
end

function Embed:setTitle(title)
    if title and #title > 256 then
        error("Embed title cannot exceed 256 characters")
    end
    self.title = title
    return self
end

function Embed:setDescription(description)
    if description and #description > 4096 then
        error("Embed description cannot exceed 4096 characters")
    end
    self.description = description
    return self
end

function Embed:setURL(url)
    self.url = url
    return self
end

function Embed:setTimestamp(timestamp)
    if timestamp == true then
        timestamp = os.time()
    elseif type(timestamp) == "number" then
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z", timestamp)
    end
    self.timestamp = timestamp
    return self
end

function Embed:setColor(color)
    if type(color) == "string" then
        color = Colors.fromHex(color)
    end
    self.color = color
    return self
end

function Embed:setFooter(text, iconURL)
    if text and #text > 2048 then
        error("Embed footer text cannot exceed 2048 characters")
    end
    self.footer = {
        text = text,
        icon_url = iconURL
    }
    return self
end

function Embed:setImage(url, height, width)
    self.image = {
        url = url,
        height = height,
        width = width
    }
    return self
end

function Embed:setThumbnail(url, height, width)
    self.thumbnail = {
        url = url,
        height = height,
        width = width
    }
    return self
end

function Embed:setAuthor(name, iconURL, url)
    if name and #name > 256 then
        error("Embed author name cannot exceed 256 characters")
    end
    self.author = {
        name = name,
        icon_url = iconURL,
        url = url
    }
    return self
end

function Embed:addField(name, value, inline)
    if not name or not value then
        error("Field name and value are required")
    end
    if #name > 256 then
        error("Field name cannot exceed 256 characters")
    end
    if #value > 1024 then
        error("Field value cannot exceed 1024 characters")
    end
    if #self.fields >= 25 then
        error("Embed cannot have more than 25 fields")
    end
    
    table.insert(self.fields, {
        name = name,
        value = value,
        inline = inline or false
    })
    return self
end

function Embed:addFields(...)
    local fields = {...}
    for _, field in ipairs(fields) do
        self:addField(field.name, field.value, field.inline)
    end
    return self
end

function Embed:spliceFields(index, deleteCount, ...)
    local newFields = {...}
    for i = 1, deleteCount do
        table.remove(self.fields, index)
    end
    for i, field in ipairs(newFields) do
        table.insert(self.fields, index + i - 1, field)
    end
    return self
end

function Embed:setFields(...)
    self.fields = {...}
    return self
end

function Embed:toJSON()
    local result = {}
    for k, v in pairs(self) do
        if v ~= nil and k ~= "new" then
            result[k] = v
        end
    end
    return result
end

function Embed:get length()
    local total = 0
    if self.title then total = total + #self.title end
    if self.description then total = total + #self.description end
    if self.footer and self.footer.text then total = total + #self.footer.text end
    if self.author and self.author.name then total = total + #self.author.name end
    for _, field in ipairs(self.fields) do
        total = total + #field.name + #field.value
    end
    return total
end

-- =============================================================================
-- REST API CLIENT
-- =============================================================================

local REST = {}
REST.__index = REST

function REST:new(options)
    options = options or {}
    return setmetatable({
        baseURL = "https://discord.com/api/v" .. (options.version or 10),
        token = options.token,
        userAgent = options.userAgent or ("Luacord/" .. Luacord.VERSION),
        rateLimits = {},
        globalRateLimit = false,
        retryLimit = options.retryLimit or 3,
        timeout = options.timeout or 30,
        logger = options.logger or Logger:new()
    }, self)
end

function REST:setToken(token)
    self.token = token
    return self
end

function REST:request(method, endpoint, data, options)
    options = options or {}
    local url = self.baseURL .. endpoint
    local headers = {
        ["User-Agent"] = self.userAgent,
        ["Content-Type"] = "application/json"
    }
    
    if self.token then
        headers["Authorization"] = "Bot " .. self.token
    end
    
    if options.headers then
        for k, v in pairs(options.headers) do
            headers[k] = v
        end
    end
    
    if options.reason then
        headers["X-Audit-Log-Reason"] = options.reason
    end
    
    -- Handle rate limiting
    local rateLimitKey = method .. ":" .. endpoint
    local rateLimit = self.rateLimits[rateLimitKey]
    
    if rateLimit and rateLimit.remaining <= 0 and os.time() < rateLimit.reset then
        local resetAfter = rateLimit.reset - os.time()
        self.logger:warn("Rate limited on %s, waiting %d seconds", rateLimitKey, resetAfter)
        -- In real implementation, you'd use actual HTTP library here
        -- This is a placeholder for the HTTP request logic
        os.execute("sleep " .. resetAfter)
    end
    
    -- Placeholder for actual HTTP request
    -- In real implementation, you'd use curl, LuaSocket, or similar
    self.logger:debug("Making %s request to %s", method, url)
    
    local response = {
        status = 200,
        headers = {},
        body = "{}"
    }
    
    -- Update rate limit info from response headers
    if response.headers["x-ratelimit-limit"] then
        self.rateLimits[rateLimitKey] = {
            limit = tonumber(response.headers["x-ratelimit-limit"]),
            remaining = tonumber(response.headers["x-ratelimit-remaining"]),
            reset = tonumber(response.headers["x-ratelimit-reset"]),
            bucket = response.headers["x-ratelimit-bucket"]
        }
    end
    
    return response
end

function REST:get(endpoint, options)
    return self:request("GET", endpoint, nil, options)
end

function REST:post(endpoint, data, options)
    return self:request("POST", endpoint, data, options)
end

function REST:put(endpoint, data, options)
    return self:request("PUT", endpoint, data, options)
end

function REST:patch(endpoint, data, options)
    return self:request("PATCH", endpoint, data, options)
end

function REST:delete(endpoint, options)
    return self:request("DELETE", endpoint, nil, options)
end

-- Channel endpoints
function REST:getChannel(channelId)
    return self:get("/channels/" .. channelId)
end

function REST:modifyChannel(channelId, data, reason)
    return self:patch("/channels/" .. channelId, data, {reason = reason})
end

function REST:deleteChannel(channelId, reason)
    return self:delete("/channels/" .. channelId, {reason = reason})
end

function REST:getChannelMessages(channelId, options)
    local query = ""
    if options then
        local params = {}
        if options.around then table.insert(params, "around=" .. options.around) end
        if options.before then table.insert(params, "before=" .. options.before) end
        if options.after then table.insert(params, "after=" .. options.after) end
        if options.limit then table.insert(params, "limit=" .. options.limit) end
        if #params > 0 then
            query = "?" .. table.concat(params, "&")
        end
    end
    return self:get("/channels/" .. channelId .. "/messages" .. query)
end

function REST:getMessage(channelId, messageId)
    return self:get("/channels/" .. channelId .. "/messages/" .. messageId)
end

function REST:createMessage(channelId, content, options)
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if options then
        if options.embed then data.embeds = {options.embed} end
        if options.embeds then data.embeds = options.embeds end
        if options.files then data.files = options.files end
        if options.components then data.components = options.components end
        if options.messageReference then data.message_reference = options.messageReference end
        if options.allowedMentions then data.allowed_mentions = options.allowedMentions end
        if options.tts then data.tts = options.tts end
        if options.flags then data.flags = options.flags end
    end
    
    return self:post("/channels/" .. channelId .. "/messages", data)
end

function REST:editMessage(channelId, messageId, content, options)
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if options then
        if options.embed then data.embeds = {options.embed} end
        if options.embeds then data.embeds = options.embeds end
        if options.components then data.components = options.components end
        if options.allowedMentions then data.allowed_mentions = options.allowedMentions end
        if options.flags then data.flags = options.flags end
    end
    
    return self:patch("/channels/" .. channelId .. "/messages/" .. messageId, data)
end

function REST:deleteMessage(channelId, messageId, reason)
    return self:delete("/channels/" .. channelId .. "/messages/" .. messageId, {reason = reason})
end

function REST:bulkDeleteMessages(channelId, messages, reason)
    local messageIds = {}
    for _, msg in ipairs(messages) do
        table.insert(messageIds, type(msg) == "string" and msg or msg.id)
    end
    
    return self:post("/channels/" .. channelId .. "/messages/bulk-delete", {
        messages = messageIds
    }, {reason = reason})
end

function REST:createReaction(channelId, messageId, emoji)
    local emojiStr = type(emoji) == "string" and emoji or (emoji.name .. ":" .. emoji.id)
    return self:put("/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. emojiStr .. "/@me")
end

function REST:deleteReaction(channelId, messageId, emoji, user)
    local emojiStr = type(emoji) == "string" and emoji or (emoji.name .. ":" .. emoji.id)
    local userStr = user and (type(user) == "string" and user or user.id) or "@me"
    return self:delete("/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. emojiStr .. "/" .. userStr)
end

function REST:pinMessage(channelId, messageId, reason)
    return self:put("/channels/" .. channelId .. "/pins/" .. messageId, nil, {reason = reason})
end

function REST:unpinMessage(channelId, messageId, reason)
    return self:delete("/channels/" .. channelId .. "/pins/" .. messageId, {reason = reason})
end

-- =============================================================================
-- GATEWAY CLIENT
-- =============================================================================

local Gateway = setmetatable({}, EventEmitter)
Gateway.__index = Gateway

local GatewayOpcodes = {
    DISPATCH = 0, HEARTBEAT = 1, IDENTIFY = 2, PRESENCE_UPDATE = 3,
    VOICE_STATE_UPDATE = 4, RESUME = 6, RECONNECT = 7, REQUEST_GUILD_MEMBERS = 8,
    INVALID_SESSION = 9, HELLO = 10, HEARTBEAT_ACK = 11
}

function Gateway:new(options)
    local gateway = EventEmitter.new(self)
    gateway.url = options.url or "wss://gateway.discord.gg/?v=10&encoding=json"
    gateway.token = options.token
    gateway.intents = options.intents or Intents.DEFAULT
    gateway.largeThreshold = options.largeThreshold or 50
    gateway.compress = options.compress or false
    gateway.properties = options.properties or {
        ["$os"] = "linux",
        ["$browser"] = "luacord",
        ["$device"] = "luacord"
    }
    gateway.presence = options.presence
    gateway.shard = options.shard or {0, 1}
    gateway.sessionId = nil
    gateway.sequence = nil
    gateway.heartbeatInterval = nil
    gateway.lastHeartbeatAck = true
    gateway.status = "disconnected"
    gateway.logger = options.logger or Logger:new()
    return gateway
end

function Gateway:connect()
    self.status = "connecting"
    self.logger:info("Connecting to Discord Gateway...")
    
    -- Placeholder for WebSocket connection
    -- In real implementation, you'd use lua-websockets or similar
    self.status = "connected"
    self:emit("open")
    
    -- Simulate receiving HELLO opcode
    self:_handleMessage({
        op = GatewayOpcodes.HELLO,
        d = {heartbeat_interval = 41250}
    })
    
    return self
end

function Gateway:disconnect(code, reason)
    self.status = "disconnecting"
    self.logger:info("Disconnecting from Gateway: %s", reason or "Unknown reason")
    
    -- Placeholder for WebSocket disconnection
    self.status = "disconnected"
    self:emit("close", code, reason)
    return self
end

function Gateway:send(data)
    if self.status ~= "connected" then
        self.logger:warn("Attempted to send data while not connected")
        return false
    end
    
    local payload = type(data) == "string" and data or self:_encode(data)
    self.logger:trace("Sending: %s", payload)
    
    -- Placeholder for WebSocket send
    return true
end

function Gateway:identify()
    local identifyPayload = {
        op = GatewayOpcodes.IDENTIFY,
        d = {
            token = self.token,
            intents = self.intents,
            properties = self.properties,
            compress = self.compress,
            large_threshold = self.largeThreshold,
            shard = self.shard
        }
    }
    
    if self.presence then
        identifyPayload.d.presence = self.presence
    end
    
    return self:send(identifyPayload)
end

function Gateway:resume()
    return self:send({
        op = GatewayOpcodes.RESUME,
        d = {
            token = self.token,
            session_id = self.sessionId,
            seq = self.sequence
        }
    })
end

function Gateway:heartbeat()
    self.lastHeartbeatAck = false
    return self:send({
        op = GatewayOpcodes.HEARTBEAT,
        d = self.sequence
    })
end

function Gateway:updatePresence(presence)
    return self:send({
        op = GatewayOpcodes.PRESENCE_UPDATE,
        d = presence
    })
end

function Gateway:_handleMessage(message)
    local data = type(message) == "string" and self:_decode(message) or message
    
    if data.s then
        self.sequence = data.s
    end
    
    self.logger:trace("Received opcode %d: %s", data.op, data.t or "N/A")
    
    if data.op == GatewayOpcodes.DISPATCH then
        self:_handleDispatch(data.t, data.d)
    elseif data.op == GatewayOpcodes.HELLO then
        self.heartbeatInterval = data.d.heartbeat_interval
        self:_startHeartbeat()
        self:identify()
    elseif data.op == GatewayOpcodes.HEARTBEAT_ACK then
        self.lastHeartbeatAck = true
    elseif data.op == GatewayOpcodes.RECONNECT then
        self.logger:info("Gateway requested reconnect")
        self:emit("reconnect")
    elseif data.op == GatewayOpcodes.INVALID_SESSION then
        self.logger:warn("Invalid session, identifying...")
        if data.d then
            -- Can resume
            self:resume()
        else
            -- Cannot resume, identify
            self.sessionId = nil
            self.sequence = nil
            self:identify()
        end
    elseif data.op == GatewayOpcodes.HEARTBEAT then
        self:heartbeat()
    end
end

function Gateway:_handleDispatch(event, data)
    self:emit("dispatch", event, data)
    
    if event == "READY" then
        self.sessionId = data.session_id
        self:emit("ready", data)
    elseif event == "RESUMED" then
        self:emit("resumed")
    elseif event == "MESSAGE_CREATE" then
        self:emit("messageCreate", data)
    elseif event == "MESSAGE_UPDATE" then
        self:emit("messageUpdate", data)
    elseif event == "MESSAGE_DELETE" then
        self:emit("messageDelete", data)
    elseif event == "GUILD_CREATE" then
        self:emit("guildCreate", data)
    elseif event == "GUILD_UPDATE" then
        self:emit("guildUpdate", data)
    elseif event == "GUILD_DELETE" then
        self:emit("guildDelete", data)
    end
    
    -- Emit the raw event as well
    self:emit(event:lower(), data)
end

function Gateway:_startHeartbeat()
    -- In real implementation, you'd use a proper timer
    self.logger:debug("Starting heartbeat with interval %dms", self.heartbeatInterval)
    -- Placeholder for heartbeat timer
end

function Gateway:_encode(data)
    -- Placeholder for JSON encoding
    -- In real implementation, you'd use a JSON library
    return "JSON_ENCODED_DATA"
end

function Gateway:_decode(data)
    -- Placeholder for JSON decoding
    -- In real implementation, you'd use a JSON library
    return {op = 0, d = {}, s = 1, t = "TEST"}
end

-- =============================================================================
-- MAIN CLIENT
-- =============================================================================

local Client = setmetatable({}, EventEmitter)
Client.__index = Client

function Client:new(options)
    options = options or {}
    local client = EventEmitter.new(self)
    
    client.token = options.token
    client.intents = options.intents or Intents.DEFAULT
    client.partials = options.partials or {}
    client.retryLimit = options.retryLimit or 3
    client.presence = options.presence
    client.sweepers = options.sweepers or {}
    client.ws = options.ws or {}
    client.rest = options.rest or {}
    client.jsonTransformer = options.jsonTransformer
    
    -- Initialize components
    client.rest = REST:new(client.rest)
    client.rest.token = client.token
    
    client.ws = Gateway:new({
        token = client.token,
        intents = client.intents,
        presence = client.presence,
        shard = client.ws.shard,
        logger = options.logger
    })
    
    -- Collections
    client.users = Collection:new()
    client.guilds = Collection:new()
    client.channels = Collection:new()
    client.emojis = Collection:new()
    
    -- State
    client.user = nil
    client.application = nil
    client.readyAt = nil
    client.uptime = 0
    
    -- Logger
    client.logger = options.logger or Logger:new()
    
    -- Setup event forwarding from gateway
    client.ws:on("ready", function(data) client:_handleReady(data) end)
    client.ws:on("messageCreate", function(data) client:_handleMessageCreate(data) end)
    client.ws:on("messageUpdate", function(data) client:_handleMessageUpdate(data) end)
    client.ws:on("messageDelete", function(data) client:_handleMessageDelete(data) end)
    client.ws:on("guildCreate", function(data) client:_handleGuildCreate(data) end)
    
    return client
end

function Client:login(token)
    if token then
        self.token = token
        self.rest:setToken(token)
        self.ws.token = token
    end
    
    if not self.token then
        error("No token provided")
    end
    
    self.logger:info("Logging in...")
    return self.ws:connect()
end

function Client:destroy()
    self.logger:info("Destroying client...")
    if self.ws then
        self.ws:disconnect(1000, "Client destroyed")
    end
    self:removeAllListeners()
    return self
end

function Client:isReady()
    return self.ws.status == "connected" and self.user ~= nil
end

function Client:_handleReady(data)
    self.user = User:new(data.user, self)
    self.application = data.application
    self.readyAt = os.time()
    
    -- Cache guilds
    for _, guildData in ipairs(data.guilds or {}) do
        local guild = Guild:new(guildData, self)
        self.guilds:set(guild.id, guild)
    end
    
    self.logger:info("Ready as %s", self.user.tag)
    self:emit("ready")
end

function Client:_handleMessageCreate(data)
    local message = Message:new(data, self)
    
    -- Cache channel if not already cached
    if not self.channels:has(message.channelId) then
        local channelData = {id = message.channelId, type = 0}
        self.channels:set(message.channelId, Channel:new(channelData, self))
    end
    
    self:emit("messageCreate", message)
end

function Client:_handleMessageUpdate(data)
    local message = Message:new(data, self)
    self:emit("messageUpdate", nil, message) -- Old message would be cached in real implementation
end

function Client:_handleMessageDelete(data)
    self:emit("messageDelete", data)
end

function Client:_handleGuildCreate(data)
    local guild = Guild:new(data, self)
    self.guilds:set(guild.id, guild)
    
    -- Cache channels
    for _, channelData in ipairs(data.channels or {}) do
        channelData.guild_id = guild.id
        local channel = Channel:new(channelData, self)
        self.channels:set(channel.id, channel)
    end
    
    self:emit("guildCreate", guild)
end

-- =============================================================================
-- COLLECTION CLASS
-- =============================================================================

local Collection = {}
Collection.__index = Collection

function Collection:new()
    return setmetatable({
        _items = {},
        _keys = {}
    }, self)
end

function Collection:set(key, value)
    if not self._items[key] then
        table.insert(self._keys, key)
    end
    self._items[key] = value
    return self
end

function Collection:get(key)
    return self._items[key]
end

function Collection:has(key)
    return self._items[key] ~= nil
end

function Collection:delete(key)
    if self._items[key] then
        self._items[key] = nil
        for i, k in ipairs(self._keys) do
            if k == key then
                table.remove(self._keys, i)
                break
            end
        end
        return true
    end
    return false
end

function Collection:clear()
    self._items = {}
    self._keys = {}
    return self
end

function Collection:size()
    return #self._keys
end

function Collection:first(amount)
    if not amount then
        return self._items[self._keys[1]]
    end
    local result = {}
    for i = 1, math.min(amount, #self._keys) do
        table.insert(result, self._items[self._keys[i]])
    end
    return result
end

function Collection:last(amount)
    if not amount then
        return self._items[self._keys[#self._keys]]
    end
    local result = {}
    local start = math.max(1, #self._keys - amount + 1)
    for i = start, #self._keys do
        table.insert(result, self._items[self._keys[i]])
    end
    return result
end

function Collection:random(amount)
    if not amount then
        local randomKey = self._keys[math.random(#self._keys)]
        return randomKey and self._items[randomKey] or nil
    end
    
    local shuffled = {}
    for _, key in ipairs(self._keys) do
        table.insert(shuffled, key)
    end
    
    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    local result = {}
    for i = 1, math.min(amount, #shuffled) do
        table.insert(result, self._items[shuffled[i]])
    end
    return result
end

function Collection:find(fn)
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if fn(value, key, self) then
            return value
        end
    end
    return nil
end

function Collection:filter(fn)
    local result = Collection:new()
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if fn(value, key, self) then
            result:set(key, value)
        end
    end
    return result
end

function Collection:map(fn)
    local result = {}
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        table.insert(result, fn(value, key, self))
    end
    return result
end

function Collection:some(fn)
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if fn(value, key, self) then
            return true
        end
    end
    return false
end

function Collection:every(fn)
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if not fn(value, key, self) then
            return false
        end
    end
    return true
end

function Collection:reduce(fn, initial)
    local accumulator = initial
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        accumulator = fn(accumulator, value, key, self)
    end
    return accumulator
end

function Collection:sort(compareFn)
    table.sort(self._keys, function(a, b)
        return compareFn(self._items[a], self._items[b], a, b)
    end)
    return self
end

function Collection:values()
    local result = {}
    for _, key in ipairs(self._keys) do
        table.insert(result, self._items[key])
    end
    return result
end

function Collection:keys()
    return {table.unpack(self._keys)}
end

function Collection:entries()
    local result = {}
    for _, key in ipairs(self._keys) do
        table.insert(result, {key, self._items[key]})
    end
    return result
end

-- =============================================================================
-- GUILD STRUCTURE
-- =============================================================================

local Guild = setmetatable({}, Base)
Guild.__index = Guild

function Guild:new(data, client)
    local guild = Base.new(self, data, client)
    guild.name = data.name
    guild.icon = data.icon
    guild.iconHash = data.icon_hash
    guild.splash = data.splash
    guild.discoverySplash = data.discovery_splash
    guild.owner = data.owner
    guild.ownerId = data.owner_id
    guild.permissions = data.permissions
    guild.region = data.region
    guild.afkChannelId = data.afk_channel_id
    guild.afkTimeout = data.afk_timeout
    guild.widgetEnabled = data.widget_enabled
    guild.widgetChannelId = data.widget_channel_id
    guild.verificationLevel = data.verification_level
    guild.defaultMessageNotifications = data.default_message_notifications
    guild.explicitContentFilter = data.explicit_content_filter
    guild.roles = data.roles or {}
    guild.emojis = data.emojis or {}
    guild.features = data.features or {}
    guild.mfaLevel = data.mfa_level
    guild.applicationId = data.application_id
    guild.systemChannelId = data.system_channel_id
    guild.systemChannelFlags = data.system_channel_flags
    guild.rulesChannelId = data.rules_channel_id
    guild.joinedAt = data.joined_at
    guild.large = data.large
    guild.unavailable = data.unavailable
    guild.memberCount = data.member_count
    guild.voiceStates = data.voice_states or {}
    guild.members = data.members or {}
    guild.channels = data.channels or {}
    guild.threads = data.threads or {}
    guild.presences = data.presences or {}
    guild.maxPresences = data.max_presences
    guild.maxMembers = data.max_members
    guild.vanityUrlCode = data.vanity_url_code
    guild.description = data.description
    guild.banner = data.banner
    guild.premiumTier = data.premium_tier
    guild.premiumSubscriptionCount = data.premium_subscription_count
    guild.preferredLocale = data.preferred_locale
    guild.publicUpdatesChannelId = data.public_updates_channel_id
    guild.maxVideoChannelUsers = data.max_video_channel_users
    guild.approximateMemberCount = data.approximate_member_count
    guild.approximatePresenceCount = data.approximate_presence_count
    guild.welcomeScreen = data.welcome_screen
    guild.nsfwLevel = data.nsfw_level
    guild.stickers = data.stickers or {}
    guild.premiumProgressBarEnabled = data.premium_progress_bar_enabled
    return guild
end

function Guild:iconURL(options)
    if not self.icon then return nil end
    options = options or {}
    local format = options.format or (self.icon:sub(1, 2) == "a_" and "gif" or "png")
    local size = math.min(options.size or = title
    return self
end

function Embed:setDescription(description)
    if description and #description > 4096 then
        error("Embed description cannot exceed 4096 characters")
    end
    self.description = description
    return self
end

function Embed:setURL(url)
    self.url = url
    return self
end

function Embed:setTimestamp(timestamp)
    if timestamp == true then
        timestamp = os.time()
    elseif type(timestamp) == "number" then
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z", timestamp)
    end
    self.timestamp = timestamp
    return self
end

function Embed:setColor(color)
    if type(color) == "string" then
        color = Colors.fromHex(color)
    end
    self.color = color
    return self
end

function Embed:setFooter(text, iconURL)
    if text and #text > 2048 then
        error("Embed footer text cannot exceed 2048 characters")
    end
    self.footer = {
        text = text,
        icon_url = iconURL
    }
    return self
end

function Embed:setImage(url, height, width)
    self.image = {
        url = url,
        height = height,
        width = width
    }
    return self
end

function Embed:setThumbnail(url, height, width)
    self.thumbnail = {
        url = url,
        height = height,
        width = width
    }
    return self
end

function Embed:setAuthor(name, iconURL, url)
    if name and #name > 256 then
        error("Embed author name cannot exceed 256 characters")
    end
    self.author = {
        name = name,
        icon_url = iconURL,
        url = url
    }
    return self
end

function Embed:addField(name, value, inline)
    if not name or not value then
        error("Field name and value are required")
    end
    if #name > 256 then
        error("Field name cannot exceed 256 characters")
    end
    if #value > 1024 then
        error("Field value cannot exceed 1024 characters")
    end
    if #self.fields >= 25 then
        error("Embed cannot have more than 25 fields")
    end
    
    table.insert(self.fields, {
        name = name,
        value = value,
        inline = inline or false
    })
    return self
end

function Embed:addFields(...)
    local fields = {...}
    for _, field in ipairs(fields) do
        self:addField(field.name, field.value, field.inline)
    end
    return self
end

function Embed:spliceFields(index, deleteCount, ...)
    local newFields = {...}
    for i = 1, deleteCount do
        table.remove(self.fields, index)
    end
    for i, field in ipairs(newFields) do
        table.insert(self.fields, index + i - 1, field)
    end
    return self
end

function Embed:setFields(...)
    self.fields = {...}
    return self
end

function Embed:toJSON()
    local result = {}
    for k, v in pairs(self) do
        if v ~= nil and k ~= "new" then
            result[k] = v
        end
    end
    return result
end

function Embed:get length()
    local total = 0
    if self.title then total = total + #self.title end
    if self.description then total = total + #self.description end
    if self.footer and self.footer.text then total = total + #self.footer.text end
    if self.author and self.author.name then total = total + #self.author.name end
    for _, field in ipairs(self.fields) do
        total = total + #field.name + #field.value
    end
    return total
end

-- =============================================================================
-- REST API CLIENT
-- =============================================================================

local REST = {}
REST.__index = REST

function REST:new(options)
    options = options or {}
    return setmetatable({
        baseURL = "https://discord.com/api/v" .. (options.version or 10),
        token = options.token,
        userAgent = options.userAgent or ("Luacord/" .. Luacord.VERSION),
        rateLimits = {},
        globalRateLimit = false,
        retryLimit = options.retryLimit or 3,
        timeout = options.timeout or 30,
        logger = options.logger or Logger:new()
    }, self)
end

function REST:setToken(token)
    self.token = token
    return self
end

function REST:request(method, endpoint, data, options)
    options = options or {}
    local url = self.baseURL .. endpoint
    local headers = {
        ["User-Agent"] = self.userAgent,
        ["Content-Type"] = "application/json"
    }
    
    if self.token then
        headers["Authorization"] = "Bot " .. self.token
    end
    
    if options.headers then
        for k, v in pairs(options.headers) do
            headers[k] = v
        end
    end
    
    if options.reason then
        headers["X-Audit-Log-Reason"] = options.reason
    end
    
    -- Handle rate limiting
    local rateLimitKey = method .. ":" .. endpoint
    local rateLimit = self.rateLimits[rateLimitKey]
    
    if rateLimit and rateLimit.remaining <= 0 and os.time() < rateLimit.reset then
        local resetAfter = rateLimit.reset - os.time()
        self.logger:warn("Rate limited on %s, waiting %d seconds", rateLimitKey, resetAfter)
        -- In real implementation, you'd use actual HTTP library here
        -- This is a placeholder for the HTTP request logic
        os.execute("sleep " .. resetAfter)
    end
    
    -- Placeholder for actual HTTP request
    -- In real implementation, you'd use curl, LuaSocket, or similar
    self.logger:debug("Making %s request to %s", method, url)
    
    local response = {
        status = 200,
        headers = {},
        body = "{}"
    }
    
    -- Update rate limit info from response headers
    if response.headers["x-ratelimit-limit"] then
        self.rateLimits[rateLimitKey] = {
            limit = tonumber(response.headers["x-ratelimit-limit"]),
            remaining = tonumber(response.headers["x-ratelimit-remaining"]),
            reset = tonumber(response.headers["x-ratelimit-reset"]),
            bucket = response.headers["x-ratelimit-bucket"]
        }
    end
    
    return response
end

function REST:get(endpoint, options)
    return self:request("GET", endpoint, nil, options)
end

function REST:post(endpoint, data, options)
    return self:request("POST", endpoint, data, options)
end

function REST:put(endpoint, data, options)
    return self:request("PUT", endpoint, data, options)
end

function REST:patch(endpoint, data, options)
    return self:request("PATCH", endpoint, data, options)
end

function REST:delete(endpoint, options)
    return self:request("DELETE", endpoint, nil, options)
end

-- Channel endpoints
function REST:getChannel(channelId)
    return self:get("/channels/" .. channelId)
end

function REST:modifyChannel(channelId, data, reason)
    return self:patch("/channels/" .. channelId, data, {reason = reason})
end

function REST:deleteChannel(channelId, reason)
    return self:delete("/channels/" .. channelId, {reason = reason})
end

function REST:getChannelMessages(channelId, options)
    local query = ""
    if options then
        local params = {}
        if options.around then table.insert(params, "around=" .. options.around) end
        if options.before then table.insert(params, "before=" .. options.before) end
        if options.after then table.insert(params, "after=" .. options.after) end
        if options.limit then table.insert(params, "limit=" .. options.limit) end
        if #params > 0 then
            query = "?" .. table.concat(params, "&")
        end
    end
    return self:get("/channels/" .. channelId .. "/messages" .. query)
end

function REST:getMessage(channelId, messageId)
    return self:get("/channels/" .. channelId .. "/messages/" .. messageId)
end

function REST:createMessage(channelId, content, options)
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if options then
        if options.embed then data.embeds = {options.embed} end
        if options.embeds then data.embeds = options.embeds end
        if options.files then data.files = options.files end
        if options.components then data.components = options.components end
        if options.messageReference then data.message_reference = options.messageReference end
        if options.allowedMentions then data.allowed_mentions = options.allowedMentions end
        if options.tts then data.tts = options.tts end
        if options.flags then data.flags = options.flags end
    end
    
    return self:post("/channels/" .. channelId .. "/messages", data)
end

function REST:editMessage(channelId, messageId, content, options)
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if options then
        if options.embed then data.embeds = {options.embed} end
        if options.embeds then data.embeds = options.embeds end
        if options.components then data.components = options.components end
        if options.allowedMentions then data.allowed_mentions = options.allowedMentions end
        if options.flags then data.flags = options.flags end
    end
    
    return self:patch("/channels/" .. channelId .. "/messages/" .. messageId, data)
end

function REST:deleteMessage(channelId, messageId, reason)
    return self:delete("/channels/" .. channelId .. "/messages/" .. messageId, {reason = reason})
end

function REST:bulkDeleteMessages(channelId, messages, reason)
    local messageIds = {}
    for _, msg in ipairs(messages) do
        table.insert(messageIds, type(msg) == "string" and msg or msg.id)
    end
    
    return self:post("/channels/" .. channelId .. "/messages/bulk-delete", {
        messages = messageIds
    }, {reason = reason})
end

function REST:createReaction(channelId, messageId, emoji)
    local emojiStr = type(emoji) == "string" and emoji or (emoji.name .. ":" .. emoji.id)
    return self:put("/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. emojiStr .. "/@me")
end

function REST:deleteReaction(channelId, messageId, emoji, user)
    local emojiStr = type(emoji) == "string" and emoji or (emoji.name .. ":" .. emoji.id)
    local userStr = user and (type(user) == "string" and user or user.id) or "@me"
    return self:delete("/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. emojiStr .. "/" .. userStr)
end

function REST:pinMessage(channelId, messageId, reason)
    return self:put("/channels/" .. channelId .. "/pins/" .. messageId, nil, {reason = reason})
end

function REST:unpinMessage(channelId, messageId, reason)
    return self:delete("/channels/" .. channelId .. "/pins/" .. messageId, {reason = reason})
end

-- =============================================================================
-- GATEWAY CLIENT
-- =============================================================================

local Gateway = setmetatable({}, EventEmitter)
Gateway.__index = Gateway

local GatewayOpcodes = {
    DISPATCH = 0, HEARTBEAT = 1, IDENTIFY = 2, PRESENCE_UPDATE = 3,
    VOICE_STATE_UPDATE = 4, RESUME = 6, RECONNECT = 7, REQUEST_GUILD_MEMBERS = 8,
    INVALID_SESSION = 9, HELLO = 10, HEARTBEAT_ACK = 11
}

function Gateway:new(options)
    local gateway = EventEmitter.new(self)
    gateway.url = options.url or "wss://gateway.discord.gg/?v=10&encoding=json"
    gateway.token = options.token
    gateway.intents = options.intents or Intents.DEFAULT
    gateway.largeThreshold = options.largeThreshold or 50
    gateway.compress = options.compress or false
    gateway.properties = options.properties or {
        ["$os"] = "linux",
        ["$browser"] = "luacord",
        ["$device"] = "luacord"
    }
    gateway.presence = options.presence
    gateway.shard = options.shard or {0, 1}
    gateway.sessionId = nil
    gateway.sequence = nil
    gateway.heartbeatInterval = nil
    gateway.lastHeartbeatAck = true
    gateway.status = "disconnected"
    gateway.logger = options.logger or Logger:new()
    return gateway
end

function Gateway:connect()
    self.status = "connecting"
    self.logger:info("Connecting to Discord Gateway...")
    
    -- Placeholder for WebSocket connection
    -- In real implementation, you'd use lua-websockets or similar
    self.status = "connected"
    self:emit("open")
    
    -- Simulate receiving HELLO opcode
    self:_handleMessage({
        op = GatewayOpcodes.HELLO,
        d = {heartbeat_interval = 41250}
    })
    
    return self
end

function Gateway:disconnect(code, reason)
    self.status = "disconnecting"
    self.logger:info("Disconnecting from Gateway: %s", reason or "Unknown reason")
    
    -- Placeholder for WebSocket disconnection
    self.status = "disconnected"
    self:emit("close", code, reason)
    return self
end

function Gateway:send(data)
    if self.status ~= "connected" then
        self.logger:warn("Attempted to send data while not connected")
        return false
    end
    
    local payload = type(data) == "string" and data or self:_encode(data)
    self.logger:trace("Sending: %s", payload)
    
    -- Placeholder for WebSocket send
    return true
end

function Gateway:identify()
    local identifyPayload = {
        op = GatewayOpcodes.IDENTIFY,
        d = {
            token = self.token,
            intents = self.intents,
            properties = self.properties,
            compress = self.compress,
            large_threshold = self.largeThreshold,
            shard = self.shard
        }
    }
    
    if self.presence then
        identifyPayload.d.presence = self.presence
    end
    
    return self:send(identifyPayload)
end

function Gateway:resume()
    return self:send({
        op = GatewayOpcodes.RESUME,
        d = {
            token = self.token,
            session_id = self.sessionId,
            seq = self.sequence
        }
    })
end

function Gateway:heartbeat()
    self.lastHeartbeatAck = false
    return self:send({
        op = GatewayOpcodes.HEARTBEAT,
        d = self.sequence
    })
end

function Gateway:updatePresence(presence)
    return self:send({
        op = GatewayOpcodes.PRESENCE_UPDATE,
        d = presence
    })
end

function Gateway:_handleMessage(message)
    local data = type(message) == "string" and self:_decode(message) or message
    
    if data.s then
        self.sequence = data.s
    end
    
    self.logger:trace("Received opcode %d: %s", data.op, data.t or "N/A")
    
    if data.op == GatewayOpcodes.DISPATCH then
        self:_handleDispatch(data.t, data.d)
    elseif data.op == GatewayOpcodes.HELLO then
        self.heartbeatInterval = data.d.heartbeat_interval
        self:_startHeartbeat()
        self:identify()
    elseif data.op == GatewayOpcodes.HEARTBEAT_ACK then
        self.lastHeartbeatAck = true
    elseif data.op == GatewayOpcodes.RECONNECT then
        self.logger:info("Gateway requested reconnect")
        self:emit("reconnect")
    elseif data.op == GatewayOpcodes.INVALID_SESSION then
        self.logger:warn("Invalid session, identifying...")
        if data.d then
            -- Can resume
            self:resume()
        else
            -- Cannot resume, identify
            self.sessionId = nil
            self.sequence = nil
            self:identify()
        end
    elseif data.op == GatewayOpcodes.HEARTBEAT then
        self:heartbeat()
    end
end

function Gateway:_handleDispatch(event, data)
    self:emit("dispatch", event, data)
    
    if event == "READY" then
        self.sessionId = data.session_id
        self:emit("ready", data)
    elseif event == "RESUMED" then
        self:emit("resumed")
    elseif event == "MESSAGE_CREATE" then
        self:emit("messageCreate", data)
    elseif event == "MESSAGE_UPDATE" then
        self:emit("messageUpdate", data)
    elseif event == "MESSAGE_DELETE" then
        self:emit("messageDelete", data)
    elseif event == "GUILD_CREATE" then
        self:emit("guildCreate", data)
    elseif event == "GUILD_UPDATE" then
        self:emit("guildUpdate", data)
    elseif event == "GUILD_DELETE" then
        self:emit("guildDelete", data)
    end
    
    -- Emit the raw event as well
    self:emit(event:lower(), data)
end

function Gateway:_startHeartbeat()
    -- In real implementation, you'd use a proper timer
    self.logger:debug("Starting heartbeat with interval %dms", self.heartbeatInterval)
    -- Placeholder for heartbeat timer
end

function Gateway:_encode(data)
    -- Placeholder for JSON encoding
    -- In real implementation, you'd use a JSON library
    return "JSON_ENCODED_DATA"
end

function Gateway:_decode(data)
    -- Placeholder for JSON decoding
    -- In real implementation, you'd use a JSON library
    return {op = 0, d = {}, s = 1, t = "TEST"}
end

-- =============================================================================
-- MAIN CLIENT
-- =============================================================================

local Client = setmetatable({}, EventEmitter)
Client.__index = Client

function Client:new(options)
    options = options or {}
    local client = EventEmitter.new(self)
    
    client.token = options.token
    client.intents = options.intents or Intents.DEFAULT
    client.partials = options.partials or {}
    client.retryLimit = options.retryLimit or 3
    client.presence = options.presence
    client.sweepers = options.sweepers or {}
    client.ws = options.ws or {}
    client.rest = options.rest or {}
    client.jsonTransformer = options.jsonTransformer
    
    -- Initialize components
    client.rest = REST:new(client.rest)
    client.rest.token = client.token
    
    client.ws = Gateway:new({
        token = client.token,
        intents = client.intents,
        presence = client.presence,
        shard = client.ws.shard,
        logger = options.logger
    })
    
    -- Collections
    client.users = Collection:new()
    client.guilds = Collection:new()
    client.channels = Collection:new()
    client.emojis = Collection:new()
    
    -- State
    client.user = nil
    client.application = nil
    client.readyAt = nil
    client.uptime = 0
    
    -- Logger
    client.logger = options.logger or Logger:new()
    
    -- Setup event forwarding from gateway
    client.ws:on("ready", function(data) client:_handleReady(data) end)
    client.ws:on("messageCreate", function(data) client:_handleMessageCreate(data) end)
    client.ws:on("messageUpdate", function(data) client:_handleMessageUpdate(data) end)
    client.ws:on("messageDelete", function(data) client:_handleMessageDelete(data) end)
    client.ws:on("guildCreate", function(data) client:_handleGuildCreate(data) end)
    
    return client
end

function Client:login(token)
    if token then
        self.token = token
        self.rest:setToken(token)
        self.ws.token = token
    end
    
    if not self.token then
        error("No token provided")
    end
    
    self.logger:info("Logging in...")
    return self.ws:connect()
end

function Client:destroy()
    self.logger:info("Destroying client...")
    if self.ws then
        self.ws:disconnect(1000, "Client destroyed")
    end
    self:removeAllListeners()
    return self
end

function Client:isReady()
    return self.ws.status == "connected" and self.user ~= nil
end

function Client:_handleReady(data)
    self.user = User:new(data.user, self)
    self.application = data.application
    self.readyAt = os.time()
    
    -- Cache guilds
    for _, guildData in ipairs(data.guilds or {}) do
        local guild = Guild:new(guildData, self)
        self.guilds:set(guild.id, guild)
    end
    
    self.logger:info("Ready as %s", self.user.tag)
    self:emit("ready")
end

function Client:_handleMessageCreate(data)
    local message = Message:new(data, self)
    
    -- Cache channel if not already cached
    if not self.channels:has(message.channelId) then
        local channelData = {id = message.channelId, type = 0}
        self.channels:set(message.channelId, Channel:new(channelData, self))
    end
    
    self:emit("messageCreate", message)
end

function Client:_handleMessageUpdate(data)
    local message = Message:new(data, self)
    self:emit("messageUpdate", nil, message) -- Old message would be cached in real implementation
end

function Client:_handleMessageDelete(data)
    self:emit("messageDelete", data)
end

function Client:_handleGuildCreate(data)
    local guild = Guild:new(data, self)
    self.guilds:set(guild.id, guild)
    
    -- Cache channels
    for _, channelData in ipairs(data.channels or {}) do
        channelData.guild_id = guild.id
        local channel = Channel:new(channelData, self)
        self.channels:set(channel.id, channel)
    end
    
    self:emit("guildCreate", guild)
end

-- =============================================================================
-- COLLECTION CLASS
-- =============================================================================

local Collection = {}
Collection.__index = Collection

function Collection:new()
    return setmetatable({
        _items = {},
        _keys = {}
    }, self)
end

function Collection:set(key, value)
    if not self._items[key] then
        table.insert(self._keys, key)
    end
    self._items[key] = value
    return self
end

function Collection:get(key)
    return self._items[key]
end

function Collection:has(key)
    return self._items[key] ~= nil
end

function Collection:delete(key)
    if self._items[key] then
        self._items[key] = nil
        for i, k in ipairs(self._keys) do
            if k == key then
                table.remove(self._keys, i)
                break
            end
        end
        return true
    end
    return false
end

function Collection:clear()
    self._items = {}
    self._keys = {}
    return self
end

function Collection:size()
    return #self._keys
end

function Collection:first(amount)
    if not amount then
        return self._items[self._keys[1]]
    end
    local result = {}
    for i = 1, math.min(amount, #self._keys) do
        table.insert(result, self._items[self._keys[i]])
    end
    return result
end

function Collection:last(amount)
    if not amount then
        return self._items[self._keys[#self._keys]]
    end
    local result = {}
    local start = math.max(1, #self._keys - amount + 1)
    for i = start, #self._keys do
        table.insert(result, self._items[self._keys[i]])
    end
    return result
end

function Collection:random(amount)
    if not amount then
        local randomKey = self._keys[math.random(#self._keys)]
        return randomKey and self._items[randomKey] or nil
    end
    
    local shuffled = {}
    for _, key in ipairs(self._keys) do
        table.insert(shuffled, key)
    end
    
    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    local result = {}
    for i = 1, math.min(amount, #shuffled) do
        table.insert(result, self._items[shuffled[i]])
    end
    return result
end

function Collection:find(fn)
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if fn(value, key, self) then
            return value
        end
    end
    return nil
end

function Collection:filter(fn)
    local result = Collection:new()
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if fn(value, key, self) then
            result:set(key, value)
        end
    end
    return result
end

function Collection:map(fn)
    local result = {}
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        table.insert(result, fn(value, key, self))
    end
    return result
end

function Collection:some(fn)
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if fn(value, key, self) then
            return true
        end
    end
    return false
end

function Collection:every(fn)
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        if not fn(value, key, self) then
            return false
        end
    end
    return true
end

function Collection:reduce(fn, initial)
    local accumulator = initial
    for _, key in ipairs(self._keys) do
        local value = self._items[key]
        accumulator = fn(accumulator, value, key, self)
    end
    return accumulator
end

function Collection:sort(compareFn)
    table.sort(self._keys, function(a, b)
        return compareFn(self._items[a], self._items[b], a, b)
    end)
    return self
end

function Collection:values()
    local result = {}
    for _, key in ipairs(self._keys) do
        table.insert(result, self._items[key])
    end
    return result
end

function Collection:keys()
    return {table.unpack(self._keys)}
end

function Collection:entries()
    local result = {}
    for _, key in ipairs(self._keys) do
        table.insert(result, {key, self._items[key]})
    end
    return result
end

-- =============================================================================
-- GUILD STRUCTURE
-- =============================================================================

local Guild = setmetatable({}, Base)
Guild.__index = Guild

function Guild:new(data, client)
    local guild = Base.new(self, data, client)
    guild.name = data.name
    guild.icon = data.icon
    guild.iconHash = data.icon_hash
    guild.splash = data.splash
    guild.discoverySplash = data.discovery_splash
    guild.owner = data.owner
    guild.ownerId = data.owner_id
    guild.permissions = data.permissions
    guild.region = data.region
    guild.afkChannelId = data.afk_channel_id
    guild.afkTimeout = data.afk_timeout
    guild.widgetEnabled = data.widget_enabled
    guild.widgetChannelId = data.widget_channel_id
    guild.verificationLevel = data.verification_level
    guild.defaultMessageNotifications = data.default_message_notifications
    guild.explicitContentFilter = data.explicit_content_filter
    guild.roles = data.roles or {}
    guild.emojis = data.emojis or {}
    guild.features = data.features or {}
    guild.mfaLevel = data.mfa_level
    guild.applicationId = data.application_id
    guild.systemChannelId = data.system_channel_id
    guild.systemChannelFlags = data.system_channel_flags
    guild.rulesChannelId = data.rules_channel_id
    guild.joinedAt = data.joined_at
    guild.large = data.large
    guild.unavailable = data.unavailable
    guild.memberCount = data.member_count
    guild.voiceStates = data.voice_states or {}
    guild.members = data.members or {}
    guild.channels = data.channels or {}
    guild.threads = data.threads or {}
    guild.presences = data.presences or {}
    guild.maxPresences = data.max_presences
    guild.maxMembers = data.max_members
    guild.vanityUrlCode = data.vanity_url_code
    guild.description = data.description
    guild.banner = data.banner
    guild.premiumTier = data.premium_tier
    guild.premiumSubscriptionCount = data.premium_subscription_count
    guild.preferredLocale = data.preferred_locale
    guild.publicUpdatesChannelId = data.public_updates_channel_id
    guild.maxVideoChannelUsers = data.max_video_channel_users
    guild.approximateMemberCount = data.approximate_member_count
    guild.approximatePresenceCount = data.approximate_presence_count
    guild.welcomeScreen = data.welcome_screen
    guild.nsfwLevel = data.nsfw_level
    guild.stickers = data.stickers or {}
    guild.premiumProgressBarEnabled = data.premium_progress_bar_enabled
    return guild
end

function Guild:iconURL(options)
    if not self.icon then return nil end
    options = options or {}
    local format = options.format or (self.icon:sub(1, 2) == "a_" and "gif" or "png")
    local size = math.min(options.size or 128, 4096)
    return string.format("https://cdn.discordapp.com/icons/%s/%s.%s?size=%d",
        self.id, self.icon, format, size)
end

function Guild:splashURL(options)
    if not self.splash then return nil end
    options = options or {}
    local format = options.format or "png"
    local size = math.min(options.size or 512, 4096)
    return string.format("https://cdn.discordapp.com/splashes/%s/%s.%s?size=%d",
        self.id, self.splash, format, size)
end

function Guild:bannerURL(options)
    if not self.banner then return nil end
    options = options or {}
    local format = options.format or (self.banner:sub(1, 2) == "a_" and "gif" or "png")
    local size = math.min(options.size or 512, 4096)
    return string.format("https://cdn.discordapp.com/banners/%s/%s.%s?size=%d",
        self.id, self.banner, format, size)
end

function Guild:fetchOwner()
    return self.client.rest:getGuildMember(self.id, self.ownerId)
end

function Guild:fetchMembers(options)
    return self.client.rest:getGuildMembers(self.id, options)
end

function Guild:fetchMember(userId)
    return self.client.rest:getGuildMember(self.id, userId)
end

function Guild:fetchBans()
    return self.client.rest:getGuildBans(self.id)
end

function Guild:fetchChannels()
    return self.client.rest:getGuildChannels(self.id)
end

function Guild:createChannel(name, options)
    local data = {name = name}
    if options then
        if options.type then data.type = options.type end
        if options.topic then data.topic = options.topic end
        if options.bitrate then data.bitrate = options.bitrate end
        if options.userLimit then data.user_limit = options.userLimit end
        if options.rateLimitPerUser then data.rate_limit_per_user = options.rateLimitPerUser end
        if options.position then data.position = options.position end
        if options.permissionOverwrites then data.permission_overwrites = options.permissionOverwrites end
        if options.parent then data.parent_id = options.parent end
        if options.nsfw then data.nsfw = options.nsfw end
    end
    return self.client.rest:createGuildChannel(self.id, data, options and options.reason)
end

function Guild:leave()
    return self.client.rest:leaveGuild(self.id)
end

function Guild:delete()
    return self.client.rest:deleteGuild(self.id)
end

-- =============================================================================
-- ADVANCED FEATURES
-- =============================================================================

-- Slash Command Builder
local SlashCommandBuilder = {}
SlashCommandBuilder.__index = SlashCommandBuilder

function SlashCommandBuilder:new()
    return setmetatable({
        name = nil,
        description = nil,
        options = {},
        defaultMemberPermissions = nil,
        dmPermission = true,
        defaultPermission = true,
        nsfw = false
    }, self)
end

function SlashCommandBuilder:setName(name)
    if not name or #name < 1 or #name > 32 then
        error("Command name must be between 1-32 characters")
    end
    if not name:match("^[%w_-]+$") then
        error("Command name must only contain alphanumeric characters, dashes, and underscores")
    end
    self.name = name:lower()
    return self
end

function SlashCommandBuilder:setDescription(description)
    if not description or #description < 1 or #description > 100 then
        error("Command description must be between 1-100 characters")
    end
    self.description = description
    return self
end

function SlashCommandBuilder:addStringOption(fn)
    return self:_addOption("STRING", fn)
end

function SlashCommandBuilder:addIntegerOption(fn)
    return self:_addOption("INTEGER", fn)
end

function SlashCommandBuilder:addBooleanOption(fn)
    return self:_addOption("BOOLEAN", fn)
end

function SlashCommandBuilder:addUserOption(fn)
    return self:_addOption("USER", fn)
end

function SlashCommandBuilder:addChannelOption(fn)
    return self:_addOption("CHANNEL", fn)
end

function SlashCommandBuilder:addRoleOption(fn)
    return self:_addOption("ROLE", fn)
end

function SlashCommandBuilder:addMentionableOption(fn)
    return self:_addOption("MENTIONABLE", fn)
end

function SlashCommandBuilder:addNumberOption(fn)
    return self:_addOption("NUMBER", fn)
end

function SlashCommandBuilder:addAttachmentOption(fn)
    return self:_addOption("ATTACHMENT", fn)
end

function SlashCommandBuilder:addSubcommand(fn)
    return self:_addOption("SUB_COMMAND", fn)
end

function SlashCommandBuilder:addSubcommandGroup(fn)
    return self:_addOption("SUB_COMMAND_GROUP", fn)
end

function SlashCommandBuilder:_addOption(type, fn)
    if #self.options >= 25 then
        error("Cannot add more than 25 options to a command")
    end
    
    local option = SlashCommandOptionBuilder:new(type)
    if fn then fn(option) end
    table.insert(self.options, option:toJSON())
    return self
end

function SlashCommandBuilder:setDefaultMemberPermissions(permissions)
    self.defaultMemberPermissions = permissions
    return self
end

function SlashCommandBuilder:setDMPermission(enabled)
    self.dmPermission = enabled
    return self
end

function SlashCommandBuilder:setNSFW(nsfw)
    self.nsfw = nsfw
    return self
end

function SlashCommandBuilder:toJSON()
    if not self.name then
        error("Command name is required")
    end
    if not self.description then
        error("Command description is required")
    end
    
    return {
        name = self.name,
        description = self.description,
        options = #self.options > 0 and self.options or nil,
        default_member_permissions = self.defaultMemberPermissions,
        dm_permission = self.dmPermission,
        nsfw = self.nsfw
    }
end

-- Slash Command Option Builder
local SlashCommandOptionBuilder = {}
SlashCommandOptionBuilder.__index = SlashCommandOptionBuilder

local OptionTypes = {
    SUB_COMMAND = 1, SUB_COMMAND_GROUP = 2, STRING = 3, INTEGER = 4,
    BOOLEAN = 5, USER = 6, CHANNEL = 7, ROLE = 8, MENTIONABLE = 9,
    NUMBER = 10, ATTACHMENT = 11
}

function SlashCommandOptionBuilder:new(type)
    return setmetatable({
        type = OptionTypes[type] or type,
        name = nil,
        description = nil,
        required = false,
        choices = {},
        options = {},
        channelTypes = {},
        minValue = nil,
        maxValue = nil,
        minLength = nil,
        maxLength = nil,
        autocomplete = false
    }, self)
end

function SlashCommandOptionBuilder:setName(name)
    if not name or #name < 1 or #name > 32 then
        error("Option name must be between 1-32 characters")
    end
    if not name:match("^[%w_-]+$") then
        error("Option name must only contain alphanumeric characters, dashes, and underscores")
    end
    self.name = name:lower()
    return self
end

function SlashCommandOptionBuilder:setDescription(description)
    if not description or #description < 1 or #description > 100 then
        error("Option description must be between 1-100 characters")
    end
    self.description = description
    return self
end

function SlashCommandOptionBuilder:setRequired(required)
    self.required = required
    return self
end

function SlashCommandOptionBuilder:addChoices(...)
    local choices = {...}
    for _, choice in ipairs(choices) do
        self:addChoice(choice.name, choice.value)
    end
    return self
end

function SlashCommandOptionBuilder:addChoice(name, value)
    if #self.choices >= 25 then
        error("Cannot add more than 25 choices to an option")
    end
    table.insert(self.choices, {name = name, value = value})
    return self
end

function SlashCommandOptionBuilder:setAutocomplete(autocomplete)
    if #self.choices > 0 then
        error("Cannot set autocomplete on option with choices")
    end
    self.autocomplete = autocomplete
    return self
end

function SlashCommandOptionBuilder:setMinValue(min)
    self.minValue = min
    return self
end

function SlashCommandOptionBuilder:setMaxValue(max)
    self.maxValue = max
    return self
end

function SlashCommandOptionBuilder:setMinLength(min)
    self.minLength = min
    return self
end

function SlashCommandOptionBuilder:setMaxLength(max)
    self.maxLength = max
    return self
end

function SlashCommandOptionBuilder:addChannelTypes(...)
    local types = {...}
    for _, channelType in ipairs(types) do
        table.insert(self.channelTypes, channelType)
    end
    return self
end

function SlashCommandOptionBuilder:toJSON()
    if not self.name then
        error("Option name is required")
    end
    if not self.description and self.type ~= OptionTypes.SUB_COMMAND and self.type ~= OptionTypes.SUB_COMMAND_GROUP then
        error("Option description is required")
    end
    
    local result = {
        type = self.type,
        name = self.name,
        description = self.description,
        required = self.required
    }
    
    if #self.choices > 0 then
        result.choices = self.choices
    end
    
    if #self.options > 0 then
        result.options = self.options
    end
    
    if #self.channelTypes > 0 then
        result.channel_types = self.channelTypes
    end
    
    if self.minValue then result.min_value = self.minValue end
    if self.maxValue then result.max_value = self.maxValue end
    if self.minLength then result.min_length = self.minLength end
    if self.maxLength then result.max_length = self.maxLength end
    if self.autocomplete then result.autocomplete = self.autocomplete end
    
    return result
end

-- Button Builder
local ButtonBuilder = {}
ButtonBuilder.__index = ButtonBuilder

local ButtonStyles = {
    PRIMARY = 1, SECONDARY = 2, SUCCESS = 3, DANGER = 4, LINK = 5
}

function ButtonBuilder:new()
    return setmetatable({
        type = 2, -- Button component type
        style = nil,
        label = nil,
        emoji = nil,
        customId = nil,
        url = nil,
        disabled = false
    }, self)
end

function ButtonBuilder:setCustomId(customId)
    if self.url then
        error("Cannot set custom ID on link button")
    end
    self.customId = customId
    return self
end

function ButtonBuilder:setLabel(label)
    if #label > 80 then
        error("Button label cannot exceed 80 characters")
    end
    self.label = label
    return self
end

function ButtonBuilder:setStyle(style)
    self.style = ButtonStyles[style] or style
    return self
end

function ButtonBuilder:setEmoji(emoji)
    self.emoji = emoji
    return self
end

function ButtonBuilder:setURL(url)
    if self.customId then
        error("Cannot set URL on button with custom ID")
    end
    self.url = url
    self.style = ButtonStyles.LINK
    return self
end

function ButtonBuilder:setDisabled(disabled)
    self.disabled = disabled
    return self
end

function ButtonBuilder:toJSON()
    if not self.style then
        error("Button style is required")
    end
    if not self.label and not self.emoji then
        error("Button must have either label or emoji")
    end
    if self.style == ButtonStyles.LINK and not self.url then
        error("Link button must have URL")
    end
    if self.style ~= ButtonStyles.LINK and not self.customId then
        error("Non-link button must have custom ID")
    end
    
    local result = {
        type = self.type,
        style = self.style,
        disabled = self.disabled
    }
    
    if self.label then result.label = self.label end
    if self.emoji then result.emoji = self.emoji end
    if self.customId then result.custom_id = self.customId end
    if self.url then result.url = self.url end
    
    return result
end

-- Action Row Builder
local ActionRowBuilder = {}
ActionRowBuilder.__index = ActionRowBuilder

function ActionRowBuilder:new()
    return setmetatable({
        type = 1, -- Action Row component type
        components = {}
    }, self)
end

function ActionRowBuilder:addComponents(...)
    local components = {...}
    for _, component in ipairs(components) do
        self:addComponent(component)
    end
    return self
end

function ActionRowBuilder:addComponent(component)
    if #self.components >= 5 then
        error("Action row cannot have more than 5 components")
    end
    
    local componentData = component.toJSON and component:toJSON() or component
    table.insert(self.components, componentData)
    return self
end

function ActionRowBuilder:toJSON()
    return {
        type = self.type,
        components = self.components
    }
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

-- Mention utilities
local Mentions = {}

function Mentions.user(userId)
    return "<@" .. userId .. ">"
end

function Mentions.member(userId)
    return "<@!" .. userId .. ">"
end

function Mentions.channel(channelId)
    return "<#" .. channelId .. ">"
end

function Mentions.role(roleId)
    return "<@&" .. roleId .. ">"
end

function Mentions.slash(commandName, subcommandGroup, subcommand)
    local mention = "</" .. commandName
    if subcommandGroup then
        mention = mention .. " " .. subcommandGroup
    end
    if subcommand then
        mention = mention .. " " .. subcommand
    end
    return mention .. ":0>"
end

function Mentions.timestamp(timestamp, style)
    local ts = timestamp
    if type(timestamp) == "number" then
        ts = math.floor(timestamp / 1000)
    end
    local mention = "<t:" .. ts
    if style then
        mention = mention .. ":" .. style
    end
    return mention .. ">"
end

-- Webhook utilities
local WebhookClient = {}
WebhookClient.__index = WebhookClient

function WebhookClient:new(url, options)
    options = options or {}
    local webhook = setmetatable({
        url = url,
        token = nil,
        id = nil,
        rest = REST:new(options.rest or {})
    }, self)
    
    -- Parse webhook URL
    local id, token = url:match("https://discord%.com/api/webhooks/(%d+)/([%w%-_]+)")
    if not id or not token then
        error("Invalid webhook URL")
    end
    
    webhook.id = id
    webhook.token = token
    return webhook
end

function WebhookClient:send(content, options)
    options = options or {}
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if options.username then data.username = options.username end
    if options.avatarURL then data.avatar_url = options.avatarURL end
    if options.tts then data.tts = options.tts end
    if options.embeds then data.embeds = options.embeds end
    if options.allowedMentions then data.allowed_mentions = options.allowedMentions end
    if options.components then data.components = options.components end
    if options.files then data.files = options.files end
    if options.threadId then
        data.thread_id = options.threadId
    end
    
    return self.rest:post("/webhooks/" .. self.id .. "/" .. self.token, data)
end

function WebhookClient:edit(messageId, content, options)
    options = options or {}
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if options.embeds then data.embeds = options.embeds end
    if options.allowedMentions then data.allowed_mentions = options.allowedMentions end
    if options.components then data.components = options.components end
    if options.files then data.files = options.files end
    
    return self.rest:patch("/webhooks/" .. self.id .. "/" .. self.token .. "/messages/" .. messageId, data)
end

function WebhookClient:delete(messageId)
    return self.rest:delete("/webhooks/" .. self.id .. "/" .. self.token .. "/messages/" .. messageId)
end

-- =============================================================================
-- MODULE EXPORTS
-- =============================================================================

-- Set up the main Luacord object
Luacord.Client = Client
Luacord.Gateway = Gateway
Luacord.REST = REST
Luacord.EventEmitter = EventEmitter
Luacord.Collection = Collection

-- Structures
Luacord.User = User
Luacord.Guild = Guild
Luacord.Channel = Channel
Luacord.Message = Message
Luacord.Embed = Embed

-- Builders
Luacord.SlashCommandBuilder = SlashCommandBuilder
Luacord.SlashCommandOptionBuilder = SlashCommandOptionBuilder
Luacord.ButtonBuilder = ButtonBuilder
Luacord.ActionRowBuilder = ActionRowBuilder
Luacord.WebhookClient = WebhookClient

-- Utilities
Luacord.Colors = Colors
Luacord.Permissions = Permissions
Luacord.Intents = Intents
Luacord.Snowflake = Snowflake
Luacord.Mentions = Mentions
Luacord.Logger = Logger
Luacord.Config = Config

-- Constants
Luacord.ChannelTypes = ChannelTypes
Luacord.ButtonStyles = ButtonStyles
Luacord.OptionTypes = OptionTypes

-- Version info
function Luacord.version()
    return {
        library = Luacord.VERSION,
        api = Luacord.API_VERSION,
        lua = _VERSION
    }
end

-- Quick start helper
function Luacord.create(options)
    return Client:new(options)
end

-- =============================================================================
-- EXAMPLE USAGE
-- =============================================================================

--[[
Example bot implementation:

local Luacord = require("luacord")

-- Create client with intents
local client = Luacord.create({
    intents = bit32.bor(
        Luacord.Intents.GUILDS,
        Luacord.Intents.GUILD_MESSAGES,
        Luacord.Intents.MESSAGE_CONTENT
    )
})

-- Event handlers
client:on("ready", function()
    print("Bot is ready! Logged in as " .. client.user.tag)
end)

client:on("messageCreate", function(message)
    if message.content == "!ping" then
        message:reply("Pong! 🏓")
    end
    
    if message.content == "!embed" then
        local embed = Luacord.Embed:new()
            :setTitle("Example Embed")
            :setDescription("This is an example embed created with Luacord!")
            :setColor(Luacord.Colors.BLUE)
            :addField("Field 1", "Value 1", true)
            :addField("Field 2", "Value 2", true)
            :setFooter("Footer text", message.author:avatarURL())
            :setTimestamp(true)
        
        message.channel:send({embeds = {embed}})
    end
    
    if message.content == "!button" then
        local button = Luacord.ButtonBuilder:new()
            :setCustomId("test_button")
            :setLabel("Click me!")
            :setStyle("PRIMARY")
        
        local row = Luacord.ActionRowBuilder:new()
            :addComponent(button)
        
        message.channel:send({
            content = "Here's a button:",
            components = {row}
        })
    end
end)

-- Login
client:login("YOUR_BOT_TOKEN")

-- Slash command example
local ping = Luacord.SlashCommandBuilder:new()
    :setName("ping")
    :setDescription("Replies with Pong!")

local echo = Luacord.SlashCommandBuilder:new()
    :setName("echo")
    :setDescription("Echoes your message")
    :addStringOption(function(option)
        option:setName("message")
              :setDescription("The message to echo")
              :setRequired(true)
    end)

-- Register commands (you'd need to implement this with REST API)
--]]

return Luacord
