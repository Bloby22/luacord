--[[
    Luacord HTTP Client - Enterprise Grade HTTP Client
    Advanced HTTP client for Discord REST API communication with comprehensive features
    
    Features:
    - Advanced rate limiting with hierarchical bucket system
    - Intelligent retry mechanisms with jitter and circuit breakers
    - Request/response middleware pipeline with priority system
    - Connection pooling with health checks and load balancing
    - Comprehensive error handling and recovery mechanisms
    - Request cancellation and timeout management
    - Extensive metrics, logging, and monitoring capabilities
    - JSON/FormData/Multipart serialization support
    - Cookie and session management
    - Caching layer with TTL and invalidation
    - Request deduplication and batching
    - WebSocket upgrade support
    - Proxy support with authentication
    - Request/response compression (gzip, deflate, brotli)
    - Advanced authentication mechanisms (OAuth2, JWT, API Keys)
    - Request signing and verification
    - Performance profiling and debugging tools
    - Memory and resource optimization
    - Thread-safe operations with coroutine support
]]

local json = require('json')
local socket = require('socket')
local ssl = require('ssl')
local ltn12 = require('ltn12')
local url = require('socket.url')
local mime = require('mime')
local zlib = require('zlib')
local crypto = require('crypto')
local base64 = require('base64')

-- Version and build info
local VERSION = "2.1.0"
local BUILD_DATE = "2025-01-15"
local API_VERSION = "v10"

local HttpClient = {}
HttpClient.__index = HttpClient

-- Constants and Configuration
local DISCORD_API_BASE = "https://discord.com/api/" .. API_VERSION
local CDN_BASE = "https://cdn.discordapp.com"
local GATEWAY_BASE = "wss://gateway.discord.gg"

local USER_AGENT = string.format("Luacord/%s (https://github.com/luacord/luacord, %s) Lua/%s", 
                                VERSION, BUILD_DATE, _VERSION)

local DEFAULT_TIMEOUT = 30
local MAX_RETRIES = 5
local RATE_LIMIT_BUFFER = 250 -- ms buffer for rate limits
local MAX_REDIRECT_COUNT = 10
local CONNECTION_TIMEOUT = 10
local READ_TIMEOUT = 30
local KEEPALIVE_TIMEOUT = 300
local MAX_IDLE_TIME = 600
local DEFAULT_MAX_CONNECTIONS = 20
local REQUEST_QUEUE_SIZE = 1000
local MEMORY_CLEANUP_INTERVAL = 300

-- Compression levels
local COMPRESSION_LEVELS = {
    NONE = 0,
    FAST = 1,
    BALANCED = 6,
    BEST = 9
}

-- HTTP Status Codes with detailed information
local HTTP_STATUS = {
    -- 1xx Informational
    CONTINUE = 100,
    SWITCHING_PROTOCOLS = 101,
    PROCESSING = 102,
    EARLY_HINTS = 103,
    
    -- 2xx Success  
    OK = 200,
    CREATED = 201,
    ACCEPTED = 202,
    NON_AUTHORITATIVE = 203,
    NO_CONTENT = 204,
    RESET_CONTENT = 205,
    PARTIAL_CONTENT = 206,
    MULTI_STATUS = 207,
    ALREADY_REPORTED = 208,
    IM_USED = 226,
    
    -- 3xx Redirection
    MULTIPLE_CHOICES = 300,
    MOVED_PERMANENTLY = 301,
    FOUND = 302,
    SEE_OTHER = 303,
    NOT_MODIFIED = 304,
    USE_PROXY = 305,
    TEMPORARY_REDIRECT = 307,
    PERMANENT_REDIRECT = 308,
    
    -- 4xx Client Errors
    BAD_REQUEST = 400,
    UNAUTHORIZED = 401,
    PAYMENT_REQUIRED = 402,
    FORBIDDEN = 403,
    NOT_FOUND = 404,
    METHOD_NOT_ALLOWED = 405,
    NOT_ACCEPTABLE = 406,
    PROXY_AUTHENTICATION_REQUIRED = 407,
    REQUEST_TIMEOUT = 408,
    CONFLICT = 409,
    GONE = 410,
    LENGTH_REQUIRED = 411,
    PRECONDITION_FAILED = 412,
    PAYLOAD_TOO_LARGE = 413,
    URI_TOO_LONG = 414,
    UNSUPPORTED_MEDIA_TYPE = 415,
    RANGE_NOT_SATISFIABLE = 416,
    EXPECTATION_FAILED = 417,
    IM_A_TEAPOT = 418,
    MISDIRECTED_REQUEST = 421,
    UNPROCESSABLE_ENTITY = 422,
    LOCKED = 423,
    FAILED_DEPENDENCY = 424,
    TOO_EARLY = 425,
    UPGRADE_REQUIRED = 426,
    PRECONDITION_REQUIRED = 428,
    TOO_MANY_REQUESTS = 429,
    REQUEST_HEADER_FIELDS_TOO_LARGE = 431,
    UNAVAILABLE_FOR_LEGAL_REASONS = 451,
    
    -- 5xx Server Errors
    INTERNAL_SERVER_ERROR = 500,
    NOT_IMPLEMENTED = 501,
    BAD_GATEWAY = 502,
    SERVICE_UNAVAILABLE = 503,
    GATEWAY_TIMEOUT = 504,
    HTTP_VERSION_NOT_SUPPORTED = 505,
    VARIANT_ALSO_NEGOTIATES = 506,
    INSUFFICIENT_STORAGE = 507,
    LOOP_DETECTED = 508,
    NOT_EXTENDED = 510,
    NETWORK_AUTHENTICATION_REQUIRED = 511
}

-- Error types for better error handling
local ERROR_TYPES = {
    NETWORK = "NETWORK_ERROR",
    TIMEOUT = "TIMEOUT_ERROR", 
    RATE_LIMIT = "RATE_LIMIT_ERROR",
    AUTH = "AUTHENTICATION_ERROR",
    VALIDATION = "VALIDATION_ERROR",
    PARSE = "PARSE_ERROR",
    CANCELLED = "CANCELLED_ERROR",
    REDIRECT = "REDIRECT_ERROR",
    COMPRESSION = "COMPRESSION_ERROR",
    SSL = "SSL_ERROR"
}

-- Priority levels for middleware and requests
local PRIORITY = {
    CRITICAL = 1,
    HIGH = 2,
    NORMAL = 3,
    LOW = 4,
    BACKGROUND = 5
}

-- Circuit breaker states
local CIRCUIT_STATES = {
    CLOSED = "CLOSED",
    OPEN = "OPEN", 
    HALF_OPEN = "HALF_OPEN"
}

-- Advanced rate limit bucket with hierarchical support
local RateLimitBucket = {}
RateLimitBucket.__index = RateLimitBucket

function RateLimitBucket.new(route, options)
    options = options or {}
    
    return setmetatable({
        route = route,
        hash = options.hash or "global",
        limit = options.limit or 1,
        remaining = options.remaining or 1,
        reset_after = options.reset_after or 0,
        reset_at = socket.gettime() + (options.reset_after or 0),
        window_start = socket.gettime(),
        queue = {},
        processing = false,
        
        -- Hierarchical rate limiting
        parent_bucket = options.parent_bucket,
        child_buckets = {},
        
        -- Advanced features
        burst_capacity = options.burst_capacity or (options.limit or 1) * 2,
        burst_used = 0,
        priority_queue = {
            [PRIORITY.CRITICAL] = {},
            [PRIORITY.HIGH] = {},
            [PRIORITY.NORMAL] = {},
            [PRIORITY.LOW] = {},
            [PRIORITY.BACKGROUND] = {}
        },
        
        -- Statistics
        stats = {
            requests_made = 0,
            requests_queued = 0,
            requests_dropped = 0,
            total_wait_time = 0,
            average_wait_time = 0,
            hits_per_window = 0,
            last_reset = socket.gettime()
        },
        
        -- Configuration
        drop_on_limit = options.drop_on_limit or false,
        max_queue_size = options.max_queue_size or 1000,
        jitter_factor = options.jitter_factor or 0.1
    }, RateLimitBucket)
end

function RateLimitBucket:can_execute(priority)
    priority = priority or PRIORITY.NORMAL
    local now = socket.gettime()
    
    -- Reset window if needed
    if now >= self.reset_at then
        self.remaining = self.limit
        self.reset_at = now + self.reset_after
        self.window_start = now
        self.burst_used = 0
        self.stats.hits_per_window = 0
        self.stats.last_reset = now
    end
    
    -- Check if we have remaining requests
    if self.remaining > 0 then
        return true
    end
    
    -- Check burst capacity for high priority requests
    if priority <= PRIORITY.HIGH and self.burst_used < self.burst_capacity then
        return true
    end
    
    return false
end

function RateLimitBucket:consume(priority)
    priority = priority or PRIORITY.NORMAL
    
    if not self:can_execute(priority) then
        return false
    end
    
    if self.remaining > 0 then
        self.remaining = self.remaining - 1
    else if priority <= PRIORITY.HIGH then
        self.burst_used = self.burst_used + 1
    end
    
    self.stats.requests_made = self.stats.requests_made + 1
    self.stats.hits_per_window = self.stats.hits_per_window + 1
    
    -- Update parent bucket if exists
    if self.parent_bucket then
        return self.parent_bucket:consume(priority)
    end
    
    return true
end

function RateLimitBucket:add_to_queue(request, priority)
    priority = priority or PRIORITY.NORMAL
    
    -- Check if queue is full
    local total_queued = 0
    for _, queue in pairs(self.priority_queue) do
        total_queued = total_queued + #queue
    end
    
    if total_queued >= self.max_queue_size then
        if self.drop_on_limit then
            self.stats.requests_dropped = self.stats.requests_dropped + 1
            return false
        else
            -- Remove lowest priority request
            for p = PRIORITY.BACKGROUND, PRIORITY.CRITICAL, -1 do
                if #self.priority_queue[p] > 0 then
                    table.remove(self.priority_queue[p], 1)
                    self.stats.requests_dropped = self.stats.requests_dropped + 1
                    break
                end
            end
        end
    end
    
    table.insert(self.priority_queue[priority], {
        request = request,
        queued_at = socket.gettime(),
        priority = priority
    })
    
    self.stats.requests_queued = self.stats.requests_queued + 1
    return true
end

function RateLimitBucket:get_next_request()
    -- Get highest priority request
    for priority = PRIORITY.CRITICAL, PRIORITY.BACKGROUND do
        local queue = self.priority_queue[priority]
        if #queue > 0 then
            local item = table.remove(queue, 1)
            local wait_time = socket.gettime() - item.queued_at
            self.stats.total_wait_time = self.stats.total_wait_time + wait_time
            self.stats.average_wait_time = self.stats.total_wait_time / self.stats.requests_made
            return item.request, item.priority
        end
    end
    return nil
end

function RateLimitBucket:get_wait_time(with_jitter)
    local base_wait = math.max(0, self.reset_at - socket.gettime())
    
    if with_jitter == false then
        return base_wait
    end
    
    -- Add jitter to prevent thundering herd
    local jitter = (math.random() * 2 - 1) * self.jitter_factor * base_wait
    return math.max(0, base_wait + jitter)
end

function RateLimitBucket:get_statistics()
    return {
        route = self.route,
        hash = self.hash,
        limit = self.limit,
        remaining = self.remaining,
        reset_after = self.reset_after,
        queue_size = self:get_total_queue_size(),
        stats = self.stats,
        burst_available = self.burst_capacity - self.burst_used
    }
end

function RateLimitBucket:get_total_queue_size()
    local total = 0
    for _, queue in pairs(self.priority_queue) do
        total = total + #queue
    end
    return total
end

-- Circuit breaker for handling failing services
local CircuitBreaker = {}
CircuitBreaker.__index = CircuitBreaker

function CircuitBreaker.new(options)
    options = options or {}
    
    return setmetatable({
        state = CIRCUIT_STATES.CLOSED,
        failure_count = 0,
        success_count = 0,
        last_failure_time = 0,
        
        -- Configuration
        failure_threshold = options.failure_threshold or 5,
        success_threshold = options.success_threshold or 3,
        timeout = options.timeout or 60, -- seconds
        
        -- Statistics
        stats = {
            total_requests = 0,
            failed_requests = 0,
            rejected_requests = 0,
            state_changes = 0
        }
    }, CircuitBreaker)
end

function CircuitBreaker:can_execute()
    local now = socket.gettime()
    
    if self.state == CIRCUIT_STATES.CLOSED then
        return true
    elseif self.state == CIRCUIT_STATES.OPEN then
        if now - self.last_failure_time >= self.timeout then
            self:transition_to_half_open()
        end
        return self.state ~= CIRCUIT_STATES.OPEN
    else -- HALF_OPEN
        return true
    end
end

function CircuitBreaker:record_success()
    self.stats.total_requests = self.stats.total_requests + 1
    
    if self.state == CIRCUIT_STATES.HALF_OPEN then
        self.success_count = self.success_count + 1
        if self.success_count >= self.success_threshold then
            self:transition_to_closed()
        end
    elseif self.state == CIRCUIT_STATES.CLOSED then
        self.failure_count = 0
    end
end

function CircuitBreaker:record_failure()
    self.stats.total_requests = self.stats.total_requests + 1
    self.stats.failed_requests = self.stats.failed_requests + 1
    
    self.failure_count = self.failure_count + 1
    self.last_failure_time = socket.gettime()
    
    if self.state == CIRCUIT_STATES.CLOSED and self.failure_count >= self.failure_threshold then
        self:transition_to_open()
    elseif self.state == CIRCUIT_STATES.HALF_OPEN then
        self:transition_to_open()
    end
end

function CircuitBreaker:record_rejection()
    self.stats.rejected_requests = self.stats.rejected_requests + 1
end

function CircuitBreaker:transition_to_open()
    self.state = CIRCUIT_STATES.OPEN
    self.stats.state_changes = self.stats.state_changes + 1
end

function CircuitBreaker:transition_to_half_open()
    self.state = CIRCUIT_STATES.HALF_OPEN
    self.success_count = 0
    self.stats.state_changes = self.stats.state_changes + 1
end

function CircuitBreaker:transition_to_closed()
    self.state = CIRCUIT_STATES.CLOSED
    self.failure_count = 0
    self.success_count = 0
    self.stats.state_changes = self.stats.state_changes + 1
end

-- Enhanced request object with advanced features
local HttpRequest = {}
HttpRequest.__index = HttpRequest

function HttpRequest.new(method, path, options)
    options = options or {}
    
    local request = setmetatable({
        method = method:upper(),
        path = path,
        headers = options.headers or {},
        body = options.body,
        query = options.query,
        
        -- Timing configuration
        timeout = options.timeout or DEFAULT_TIMEOUT,
        connect_timeout = options.connect_timeout or CONNECTION_TIMEOUT,
        read_timeout = options.read_timeout or READ_TIMEOUT,
        
        -- Retry configuration
        retries = options.retries or MAX_RETRIES,
        retry_delay = options.retry_delay or 1000,
        retry_backoff = options.retry_backoff or 2.0,
        retry_jitter = options.retry_jitter or true,
        retry_condition = options.retry_condition,
        
        -- Advanced options
        follow_redirects = options.follow_redirects ~= false,
        max_redirects = options.max_redirects or MAX_REDIRECT_COUNT,
        allow_compression = options.allow_compression ~= false,
        compression_level = options.compression_level or COMPRESSION_LEVELS.BALANCED,
        
        -- Request metadata
        priority = options.priority or PRIORITY.NORMAL,
        tags = options.tags or {},
        context = options.context or {},
        
        -- State management
        cancelled = false,
        started_at = nil,
        completed_at = nil,
        attempt = 0,
        redirects_followed = 0,
        
        -- Identification
        id = options.id or string.format("%x-%x", socket.gettime() * 1000000, math.random(1000000)),
        trace_id = options.trace_id,
        span_id = options.span_id,
        
        -- Callbacks
        on_upload_progress = options.on_upload_progress,
        on_download_progress = options.on_download_progress,
        on_redirect = options.on_redirect,
        on_retry = options.on_retry,
        
        -- Authentication
        auth = options.auth,
        
        -- Caching
        cache_key = options.cache_key,
        cache_ttl = options.cache_ttl,
        
        -- Middleware hooks
        middleware = options.middleware or {}
    }, HttpRequest)
    
    -- Validate method
    local valid_methods = {GET=true, POST=true, PUT=true, DELETE=true, PATCH=true, HEAD=true, OPTIONS=true}
    if not valid_methods[request.method] then
        error("Invalid HTTP method: " .. request.method)
    end
    
    -- Set default headers
    if not request.headers["User-Agent"] then
        request.headers["User-Agent"] = USER_AGENT
    end
    
    return request
end

function HttpRequest:cancel(reason)
    self.cancelled = true
    self.cancel_reason = reason or "Cancelled by user"
end

function HttpRequest:is_cancelled()
    return self.cancelled
end

function HttpRequest:start()
    if not self.started_at then
        self.started_at = socket.gettime()
    end
end

function HttpRequest:complete()
    if not self.completed_at then
        self.completed_at = socket.gettime()
    end
end

function HttpRequest:get_duration()
    if self.started_at and self.completed_at then
        return self.completed_at - self.started_at
    elseif self.started_at then
        return socket.gettime() - self.started_at
    end
    return 0
end

function HttpRequest:add_tag(key, value)
    self.tags[key] = value
end

function HttpRequest:get_tag(key)
    return self.tags[key]
end

function HttpRequest:set_context(key, value)
    self.context[key] = value
end

function HttpRequest:get_context(key)
    return self.context[key]
end

function HttpRequest:get_full_url(base_url)
    local full_url = base_url .. self.path
    if self.query and type(self.query) == "table" then
        local query_params = {}
        for k, v in pairs(self.query) do
            if type(v) == "table" then
                for _, item in ipairs(v) do
                    table.insert(query_params, k .. "=" .. url.escape(tostring(item)))
                end
            else
                table.insert(query_params, k .. "=" .. url.escape(tostring(v)))
            end
        end
        if #query_params > 0 then
            full_url = full_url .. "?" .. table.concat(query_params, "&")
        end
    elseif type(self.query) == "string" then
        full_url = full_url .. "?" .. self.query
    end
    return full_url
end

function HttpRequest:clone()
    local cloned_headers = {}
    for k, v in pairs(self.headers) do
        cloned_headers[k] = v
    end
    
    local cloned_tags = {}
    for k, v in pairs(self.tags) do
        cloned_tags[k] = v
    end
    
    local cloned_context = {}
    for k, v in pairs(self.context) do
        cloned_context[k] = v
    end
    
    return HttpRequest.new(self.method, self.path, {
        headers = cloned_headers,
        body = self.body,
        query = self.query,
        timeout = self.timeout,
        retries = self.retries,
        priority = self.priority,
        tags = cloned_tags,
        context = cloned_context,
        auth = self.auth,
        cache_key = self.cache_key,
        cache_ttl = self.cache_ttl
    })
end

function HttpRequest:should_retry_on_status(status_code)
    if self.retry_condition then
        return self.retry_condition(status_code, self.attempt)
    end
    
    -- Default retry logic
    return status_code >= 500 or status_code == HTTP_STATUS.TOO_MANY_REQUESTS
end

-- Enhanced response object with rich metadata
local HttpResponse = {}
HttpResponse.__index = HttpResponse

function HttpResponse.new(status, headers, body, request, options)
    options = options or {}
    
    return setmetatable({
        status = status,
        headers = headers or {},
        body = body,
        request = request,
        
        -- Response metadata
        ok = status >= 200 and status < 300,
        redirected = options.redirected or false,
        url = options.url,
        final_url = options.final_url,
        
        -- Timing information
        timing = options.timing or {},
        
        -- Network information
        remote_address = options.remote_address,
        connection_reused = options.connection_reused,
        
        -- Compression info
        compressed = options.compressed,
        compression_type = options.compression_type,
        original_size = options.original_size,
        compressed_size = options.compressed_size,
        
        -- Caching
        from_cache = options.from_cache or false,
        cache_key = options.cache_key,
        
        -- Internal caches
        _json_cache = nil,
        _text_cache = nil,
        _cookies_cache = nil
    }, HttpResponse)
end

function HttpResponse:json()
    if not self._json_cache then
        if self.body and self.body ~= "" then
            local success, result = pcall(json.decode, self.body)
            if success then
                self._json_cache = result
            else
                error(string.format("Failed to parse JSON response: %s\nBody: %s", 
                      tostring(result), tostring(self.body):sub(1, 500)))
            end
        else
            self._json_cache = nil
        end
    end
    return self._json_cache
end

function HttpResponse:text()
    if not self._text_cache then
        self._text_cache = tostring(self.body or "")
    end
    return self._text_cache
end

function HttpResponse:get_header(name, case_sensitive)
    if case_sensitive then
        return self.headers[name]
    end
    
    name = name:lower()
    for k, v in pairs(self.headers) do
        if k:lower() == name then
            return v
        end
    end
    return nil
end

function HttpResponse:get_all_headers(name, case_sensitive)
    local headers = {}
    if case_sensitive then
        local value = self.headers[name]
        if value then
            table.insert(headers, value)
        end
    else
        name = name:lower()
        for k, v in pairs(self.headers) do
            if k:lower() == name then
                table.insert(headers, v)
            end
        end
    end
    return headers
end

function HttpResponse:get_cookies()
    if not self._cookies_cache then
        self._cookies_cache = {}
        local set_cookie_headers = self:get_all_headers("Set-Cookie")
        
        for _, cookie_header in ipairs(set_cookie_headers) do
            local cookie = self:parse_cookie(cookie_header)
            if cookie then
                self._cookies_cache[cookie.name] = cookie
            end
        end
    end
    return self._cookies_cache
end

function HttpResponse:parse_cookie(cookie_string)
    local parts = {}
    for part in cookie_string:gmatch("[^;]+") do
        table.insert(parts, part:match("^%s*(.-)%s*$")) -- trim whitespace
    end
    
    if #parts == 0 then
        return nil
    end
    
    -- Parse name=value
    local name, value = parts[1]:match("^([^=]+)=(.*)$")
    if not name then
        return nil
    end
    
    local cookie = {
        name = name,
        value = value,
        attributes = {}
    }
    
    -- Parse attributes
    for i = 2, #parts do
        local attr_name, attr_value = parts[i]:match("^([^=]+)=?(.*)$")
        if attr_name then
            cookie.attributes[attr_name:lower()] = attr_value ~= "" and attr_value or true
        end
    end
    
    return cookie
end

function HttpResponse:is_success()
    return self.ok
end

function HttpResponse:is_client_error()
    return self.status >= 400 and self.status < 500
end

function HttpResponse:is_server_error()
    return self.status >= 500 and self.status < 600
end

function HttpResponse:is_redirect()
    return self.status >= 300 and self.status < 400
end

function HttpResponse:get_content_type()
    return self:get_header("Content-Type")
end

function HttpResponse:get_content_length()
    local length = self:get_header("Content-Length")
    return length and tonumber(length) or nil
end

function HttpResponse:get_compression_ratio()
    if self.original_size and self.compressed_size then
        return 1 - (self.compressed_size / self.original_size)
    end
    return nil
end

-- Advanced connection pool with health checks and load balancing
local ConnectionPool = {}
ConnectionPool.__index = ConnectionPool

function ConnectionPool.new(options)
    options = options or {}
    
    return setmetatable({
        max_connections = options.max_connections or DEFAULT_MAX_CONNECTIONS,
        max_idle_time = options.max_idle_time or MAX_IDLE_TIME,
        keepalive_timeout = options.keepalive_timeout or KEEPALIVE_TIMEOUT,
        
        connections = {}, -- host:port -> connection list
        active_connections = {}, -- connection_id -> connection
        connection_stats = {}, -- host:port -> stats
        
        -- Load balancing
        load_balancer = options.load_balancer or "round_robin", -- round_robin, least_connections, random
        
        -- Health checking
        health_check_interval = options.health_check_interval or 60,
        health_check_timeout = options.health_check_timeout or 5,
        last_health_check = 0,
        
        -- Statistics
        stats = {
            total_connections = 0,
            active_connections = 0,
            failed_connections = 0,
            connections_created = 0,
            connections_reused = 0,
            connections_closed = 0,
            health_checks_performed = 0,
            health_check_failures = 0
        },
        
        -- Configuration
        enable_health_checks = options.enable_health_checks ~= false,
        connection_timeout = options.connection_timeout or CONNECTION_TIMEOUT,
        
        -- Connection factory
        connection_factory = options.connection_factory
    }, ConnectionPool)
end

function ConnectionPool:get_connection_key(host, port)
    return host .. ":" .. port
end

function ConnectionPool:get_connection(host, port, ssl_params, priority)
    local key = self:get_connection_key(host, port)
    priority = priority or PRIORITY.NORMAL
    
    -- Initialize connection list for this endpoint
    if not self.connections[key] then
        self.connections[key] = {}
        self.connection_stats[key] = {
            total_requests = 0,
            failed_requests = 0,
            avg_response_time = 0,
            last_used = 0,
            created_count = 0
        }
    end
    
    -- Perform periodic health checks
    self:perform_health_checks()
    
    -- Try to reuse existing connection
    local conn = self:find_available_connection(key)
    if conn then
        conn.last_used = socket.gettime()
        conn.requests_handled = conn.requests_handled + 1
        self.stats.connections_reused = self.stats.connections_reused + 1
        return conn
    end
    
    -- Create new connection if under limit
    if self:can_create_connection() then
        conn = self:create_connection(host, port, ssl_params, key)
        if conn then
            self.stats.connections_created = self.stats.connections_created + 1
            self.connection_stats[key].created_count = self.connection_stats[key].created_count + 1
            return conn
        end
    end
    
    -- Wait for available connection or create emergency connection for high priority
    if priority <= PRIORITY.HIGH then
        conn = self:create_connection(host, port, ssl_params, key, true) -- emergency
        if conn then
            conn.emergency = true
            return conn
        end
    end
    
    return nil, "Connection pool exhausted"
end

function ConnectionPool:find_available_connection(key)
    local connections = self.connections[key]
    if not connections then
        return nil
    end
    
    -- Remove stale connections
    self:cleanup_stale_connections(key)
    
    local available = {}
    for _, conn in ipairs(connections) do
        if not conn.in_use and self:is_connection_healthy(conn) then
            table.insert(available, conn)
        end
    end
    
    if #available == 0 then
        return nil
    end
