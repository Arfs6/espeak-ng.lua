--[[
--mana.lua is the integration layer for mana.nvim.
--It connects espeak-ng synthesis in retrieval mode to the C audio buffer.
--Public functions: init, uninit, speak, and stop.
--]]
local m = {}

local audio = require('espeak-ng.audio')
local log = require('espeak-ng.log')
local lib = require('espeak-ng.lib')

local initialized = false

-- Initialize espeak-ng and matching audio output. Safe to call repeatedly.
m.init = function()
	if initialized then
		return
	end
	log.info('Initializing espeak-ng.')
	-- Retrieval mode hands synthesized samples to the callback below instead
	-- of playing them itself. The 300 ms buffer is espeak's internal queue.
	local sampleRate = lib.initialize(lib.audioOutput.AUDIO_OUTPUT_RETRIEVAL, 300, nil, 0)
	audio.init(sampleRate)

	-- espeak calls this on its synthesis thread with mono s16 samples.
	-- Store the cast callback on this module so LuaJIT keeps it alive.
	m.synthCallback = lib.synthCallback(function(wav, numsamples, events)
		if wav ~= nil then
			audio.write(wav, numsamples)
		end
		return 0
	end)
	lib.setSynthCallback(m.synthCallback)
	lib.setParameter(lib.parameter.espeakPUNCTUATION, lib.punctType.espeakPUNCT_ALL, 0)
	initialized = true
	log.info('Finished initializing espeak-ng.')
end

m.uninit = function()
	if not initialized then
		return
	end
	initialized = false
	-- Stop espeak before releasing audio so no callback can write to freed state.
	lib.terminate()
	audio.uninit()
end

m.speak = function(text)
	log.debug('speaking:' .. text)
	-- Wrap plain input in SSML so punctuation and markup are handled by espeak.
	text = '<speak>' .. text .. '</speak>'
	-- In retrieval mode the synthesized audio arrives through synthCallback.
	local err = lib.synth(
		lib.toPVoid(text),
		-- espeak uses this size to allocate its internal text buffer.
		-- In RETRIEVAL (async) mode a size of 0 makes espeak_Synth fail.
		#text + 1,
		0,
		lib.position_type.POS_CHARACTER,
		0,
		require('bit').bor(lib.flags.espeakCHARS_UTF8, lib.flags.espeakSSML, lib.flags.espeakPHONEMES),
		nil,
		nil
	)
	if err ~= lib.error.EE_OK then
		log.error('espeak_Synth failed with error ' .. tostring(tonumber(err)))
	end
	log.info('Done speaking.')
end

-- Cancel current speech without tearing down playback.
m.stop = function()
	lib.cancel()
end

return m
