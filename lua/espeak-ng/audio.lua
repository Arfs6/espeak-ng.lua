--[[
-- LuaJIT FFI wrapper around the C audio layer in c/audio.c.
-- audio.so is loaded from this module's directory, next to this file.
--]]

local ffi = require("ffi")

-- Keep these declarations in sync with the exported functions in c/audio.c.
ffi.cdef[[
int mana_audio_init(uint32_t sampleRate);
void mana_audio_uninit(void);
int mana_audio_buffer_write(const short *samples, uint32_t numSamples);
]]

local source = debug.getinfo(1, "S").source
local directory = source:sub(1, 1) == "@"
    and source:sub(2):match("(.*/)")
    or nil

local library_path = directory and (directory .. "audio.so") or "./audio.so"
local lib = ffi.load(library_path)

local M = {}

-- Must match ManaAudioResult in c/audio.c.
local SUCCESS = 0
local ERR = 1
local ERR_MEMORY = 2

local initialized = false

-- Initialize playback at espeak's sample rate. Idempotent on success.
-- Returns true, or nil plus an error message.
function M.init(sample_rate)
    assert(type(sample_rate) == "number", "sample_rate must be a number")
    assert(sample_rate > 0 and sample_rate % 1 == 0,
        "sample_rate must be a positive integer")

    if initialized then
        return true
    end

    local result = lib.mana_audio_init(sample_rate)

    if result ~= SUCCESS then
        if result == ERR_MEMORY then
            return nil, "Failed to allocate the audio buffer"
        end

        return nil, "Failed to initialize the audio device (error "
            .. tonumber(result) .. ")"
    end

    initialized = true
    return true
end

-- Queue `num_samples` mono s16 samples. The C side either accepts the whole
-- block or rejects it, so a full buffer is reported as an error the caller may
-- retry after playback drains it.
function M.write(samples, num_samples)
    assert(initialized, "Audio is not initialized")
    assert(samples ~= nil, "samples must not be nil")
    assert(type(num_samples) == "number"
        and num_samples >= 0
        and num_samples % 1 == 0
        and num_samples <= 4294967295,
        "num_samples must be a valid uint32_t value")

    if num_samples == 0 then
        return true
    end

    local result = lib.mana_audio_buffer_write(samples, num_samples)

    if result ~= SUCCESS then
        return nil, "Failed to write audio samples (error "
            .. tonumber(result) .. ")"
    end

    return true
end

-- Stop playback and release the C device and buffer. Safe when not initialized.
function M.uninit()
    if not initialized then
        return
    end

    lib.mana_audio_uninit()
    initialized = false
end

return M
