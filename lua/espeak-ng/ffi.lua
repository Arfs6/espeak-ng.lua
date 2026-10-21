--[[
--ffi binding for libspeak-ng.
--]]

local m = {}

local log = require('espeak-ng.log')

local ffi = require('ffi')

--type definitions
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
]]

-- function definitions
ffi.cdef [[
int espeak_Initialize(espeak_AUDIO_OUTPUT output, int buflength, const char *path, int options)

espeak_ERROR espeak_SetVoiceByName(const char *name)

espeak_ERROR espeak_Synth(const void *text,
	size_t size,
	unsigned int position,
	espeak_POSITION_TYPE position_type,
	unsigned int end_position,
	unsigned int flags,
	unsigned int* unique_identifier,
	void* user_data);

espeak_ERROR espeak_SetParameter(espeak_PARAMETER parameter, int value, int relative)

espeak_ERROR espeak_Cancel(void)

espeak_ERROR espeak_Char(wchar_t character)
]]

-- Load libespeak-ng
local lib_espeak_ng_path = 'libespeak-ng.so'
if jit.os == 'Windows' then
	lib_espeak_ng_path =[[C:\Program Files\eSpeak NG\libespeak-ng.dll]]
elseif jit.os == 'Linux' then
	lib_espeak_ng_path = '/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1'
else
	lib_espeak_ng_path = 'espeak-ng.so'
end
local libespeak_ng = ffi.load(lib_espeak_ng_path)

m.error = {
	EE_OK = 0,
	EE_INTERNAL_ERROR = -1,
	EE_BUFFER_FULL = 1,
	EE_NOT_FOUND = 2,
}

m.audio_output = {
	AUDIO_OUTPUT_PLAYBACK = 0,
	AUDIO_OUTPUT_RETRIEVAL = 1,
	AUDIO_OUTPUT_SYNCHRONOUS = 2,
	AUDIO_OUTPUT_SYNCH_PLAYBACK = 3,
}

m.position_type = {
	POS_CHARACTER = 1,
	POS_WORD = 2,
	POS_SENTENCE = 3,
}

m.parameter = {
  espeakSILENCE=0,
  espeakRATE=1,
  espeakVOLUME=2,
  espeakPITCH=3,
  espeakRANGE=4,
  espeakPUNCTUATION=5,
  espeakCAPITALS=6,
  espeakWORDGAP=7,
  espeakOPTIONS=8,
  espeakINTONATION=9,
  espeakSSML_BREAK_MUL=10,
  espeakRESERVED2=11,
  espeakEMPHASIS = 12,
  espeakLINELENGTH = 13,
  espeakVOICETYPE = 14,
  N_SPEECH_PARAM = 15,
}

m.punct_type = {
  espeakPUNCT_NONE=0,
  espeakPUNCT_ALL=1,
  espeakPUNCT_SOME=2,
}

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

--Structs
m.event = ffi.typeof('espeak_EVENT')

m.initialize = libespeak_ng.espeak_Initialize


return m
