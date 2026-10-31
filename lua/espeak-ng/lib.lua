--[[
--ffi binding for libspeak-ng.
--]]
--The goal with this module is to make using the libespeak-ng library straight
--forward in lua.
--
-- This module only declares the C ABI and exposes it. Higher-level behavior
-- such as audio routing and lifecycle ordering belongs in mana.lua.

local m = {}

local log = require('espeak-ng.log')
log.info('loading espeak-ng library.')

local ffi = require('ffi')

-- Type definitions from espeak-ng's public API. Values and layouts must match
-- the installed library's headers.
ffi.cdef [[
typedef enum {
	EE_OK=0,
	EE_INTERNAL_ERROR=-1,
	EE_BUFFER_FULL=1,
	EE_NOT_FOUND=2
} espeak_ERROR;

typedef enum {
	/* PLAYBACK mode: plays the audio data, supplies events to the calling program*/
	AUDIO_OUTPUT_PLAYBACK,

	/* RETRIEVAL mode: supplies audio data and events to the calling program */
	AUDIO_OUTPUT_RETRIEVAL,

	/* SYNCHRONOUS mode: as RETRIEVAL but doesn't return until synthesis is completed */
	AUDIO_OUTPUT_SYNCHRONOUS,

	/* Synchronous playback */
	AUDIO_OUTPUT_SYNCH_PLAYBACK

} espeak_AUDIO_OUTPUT;

typedef enum {
	POS_CHARACTER = 1,
	POS_WORD,
	POS_SENTENCE
} espeak_POSITION_TYPE;

typedef enum {
  espeakSILENCE=0, /* internal use */
  espeakRATE=1,
  espeakVOLUME=2,
  espeakPITCH=3,
  espeakRANGE=4,
  espeakPUNCTUATION=5,
  espeakCAPITALS=6,
  espeakWORDGAP=7,
  espeakOPTIONS=8,   // reserved for misc. options.  not yet used
  espeakINTONATION=9,
  espeakSSML_BREAK_MUL=10,

  espeakRESERVED2=11,
  espeakEMPHASIS,   /* internal use */
  espeakLINELENGTH, /* internal use */
  espeakVOICETYPE,  // internal, 1=mbrola
  N_SPEECH_PARAM    /* last enum */
} espeak_PARAMETER;

typedef enum {
  espeakPUNCT_NONE=0,
  espeakPUNCT_ALL=1,
  espeakPUNCT_SOME=2
} espeak_PUNCT_TYPE;

typedef enum {
  espeakEVENT_LIST_TERMINATED = 0, // Retrieval mode: terminates the event list.
  espeakEVENT_WORD = 1,            // Start of word
  espeakEVENT_SENTENCE = 2,        // Start of sentence
  espeakEVENT_MARK = 3,            // Mark
  espeakEVENT_PLAY = 4,            // Audio element
  espeakEVENT_END = 5,             // End of sentence or clause
  espeakEVENT_MSG_TERMINATED = 6,  // End of message
  espeakEVENT_PHONEME = 7,         // Phoneme, if enabled in espeak_Initialize()
  espeakEVENT_SAMPLERATE = 8       // Set sample rate
} espeak_EVENT_TYPE;

typedef struct {
	espeak_EVENT_TYPE type;
	unsigned int unique_identifier; // message identifier (or 0 for key or character)
	int text_position;    // the number of characters from the start of the text
	int length;           // word length, in characters (for espeakEVENT_WORD)
	int audio_position;   // the time in mS within the generated speech output data
	int sample;           // sample id (internal use)
	void* user_data;      // pointer supplied by the calling program
	union {
		int number;        // used for WORD and SENTENCE events.
		const char *name;  // used for MARK and PLAY events.  UTF8 string
		char string[8];    // used for phoneme names (UTF8). Terminated by a zero byte unless the name needs the full 8 bytes.
	} id;
} espeak_EVENT;

typedef int (t_espeak_callback)(short*, int, espeak_EVENT*);
]]

-- espeak invokes t_espeak_callback from its synthesis thread. A Lua callback
-- cast to this type must stay reachable while it is registered with espeak.
-- The following declarations are functions exported by libespeak-ng.
ffi.cdef [[
int espeak_Initialize(espeak_AUDIO_OUTPUT output, int buflength, const char *path, int options);

void espeak_SetSynthCallback(t_espeak_callback* SynthCallback);

espeak_ERROR espeak_SetVoiceByName(const char *name);

espeak_ERROR espeak_Synth(const void *text,
	size_t size,
	unsigned int position,
	espeak_POSITION_TYPE position_type,
	unsigned int end_position,
	unsigned int flags,
	unsigned int* unique_identifier,
	void* user_data);

espeak_ERROR espeak_SetParameter(espeak_PARAMETER parameter, int value, int relative);

espeak_ERROR espeak_Cancel(void);

espeak_ERROR espeak_SetParameter(espeak_PARAMETER parameter, int value, int relative);

espeak_ERROR espeak_Terminate(void);
]]

-- Load libespeak-ng. Linux uses the distribution's versioned shared object,
-- so the system package must already be installed.
local lib_espeak_ng_path = 'libespeak-ng.so'
if jit.os == 'Windows' then
	lib_espeak_ng_path = [[C:\Program Files\eSpeak NG\libespeak-ng.dll]]
elseif jit.os == 'Linux' then
	lib_espeak_ng_path = '/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1'
else
	lib_espeak_ng_path = 'espeak-ng.so'
end
m.cLib = ffi.load(lib_espeak_ng_path)

-- Values returned by espeak_* functions.
m.error = {
	EE_OK = 0,
	EE_INTERNAL_ERROR = -1,
	EE_BUFFER_FULL = 1,
	EE_NOT_FOUND = 2,
}

-- How espeak delivers synthesized audio (playback, retrieval, synchronous).
m.audioOutput = {
	AUDIO_OUTPUT_PLAYBACK = 0,
	AUDIO_OUTPUT_RETRIEVAL = 1,
	AUDIO_OUTPUT_SYNCHRONOUS = 2,
	AUDIO_OUTPUT_SYNCH_PLAYBACK = 3,
}

-- Units used by the text position arguments of espeak_Synth.
m.position_type = {
	POS_CHARACTER = 1,
	POS_WORD = 2,
	POS_SENTENCE = 3,
}

-- Voice and synthesis parameters accepted by espeak_SetParameter.
m.parameter = {
	espeakSILENCE = 0,
	espeakRATE = 1,
	espeakVOLUME = 2,
	espeakPITCH = 3,
	espeakRANGE = 4,
	espeakPUNCTUATION = 5,
	espeakCAPITALS = 6,
	espeakWORDGAP = 7,
	espeakOPTIONS = 8,
	espeakINTONATION = 9,
	espeakSSML_BREAK_MUL = 10,
	espeakRESERVED2 = 11,
	espeakEMPHASIS = 12,
	espeakLINELENGTH = 13,
	espeakVOICETYPE = 14,
	N_SPEECH_PARAM = 15,
}

-- Punctuation levels for the espeakPUNCTUATION parameter.
m.punctType = {
	espeakPUNCT_NONE = 0,
	espeakPUNCT_ALL = 1,
	espeakPUNCT_SOME = 2,
}

-- Event types delivered in the espeak_EVENT array passed to the callback.
m.event_type = {
	espeakEVENT_LIST_TERMINATED = 0,
	espeakEVENT_WORD = 1,
	espeakEVENT_SENTENCE = 2,
	espeakEVENT_MARK = 3,
	espeakEVENT_PLAY = 4,
	espeakEVENT_END = 5,
	espeakEVENT_MSG_TERMINATED = 6,
	espeakEVENT_PHONEME = 7,
	espeakEVENT_SAMPLERATE = 8,
}

-- Bit flags for espeak_Synth.
m.flags = {
	espeakCHARS_AUTO = 0,
	espeakCHARS_UTF8 = 1,
	espeakCHARS_8BIT = 2,
	espeakCHARS_WCHAR = 3,
	espeakCHARS_16BIT = 4,
	espeakSSML = 0x10,
	espeakPHONEMES = 0x100,
	espeakENDPAUSE = 0x1000,
	espeakKEEP_NAMEDATA = 0x2000
}

-- Structs
-- FFI type used to construct or inspect espeak_EVENT values.
m.event = ffi.typeof('espeak_EVENT')

-- Cast a Lua function to a C callback pointer. Keep the returned cdata alive
-- (for example on this module) while espeak may invoke it.
m.synthCallback = function(callback)
	return ffi.cast('t_espeak_callback*', callback)
end

-- Initialize espeak and return its selected sample rate.
m.initialize = m.cLib.espeak_Initialize

-- Register the synthesis callback used in audio retrieval mode.
m.setSynthCallback = m.cLib.espeak_SetSynthCallback

-- Wrap an identifier in FFI memory for espeak_Synth's optional
-- unique_identifier argument.
m.uniqueIdentifier = function(num)
	assert(type(num) == 'number' and num >= 0, 'num must be a positive integer.')
	local cNum = ffi.new('unsigned int[1]', num)
	return ffi.cast('unsigned int*', cNum)
end

-- Cast a Lua string's bytes to the const void* expected by espeak_Synth.
m.toPVoid = function(text)
	assert(type(text) == 'string')
return ffi.cast('const void *', text)
end

-- Raw espeak-ng entry points; they return the C types declared above.
m.synth = m.cLib.espeak_Synth

m.setParameter = m.cLib.espeak_SetParameter

m.cancel = m.cLib.espeak_Cancel

m.terminate = m.cLib.espeak_Terminate

log.info('Finished loading espeak-ng library.')

return m
