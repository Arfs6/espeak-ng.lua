--[[
--tts module.
--Only espeak-ng will be supported in mana.nvim.
--]]

local m = {}

local log = require('plenary.log').new({
	plugin = 'mana',
	level = 'debug',
	use_console = false,
})

local ffi = require('ffi')
ffi.cdef [[
typedef enum {
	/* PLAYBACK mode: plays the audio data, supplies events to the calling program*/
	AUDIO_OUTPUT_PLAYBACK,

	/* RETRIEVAL mode: supplies audio data and events to the calling program */
	AUDIO_OUTPUT_RETRIEVAL,

	/* SYNCHRONOUS mode: as RETRIEVAL but doesn't return until synthesis is completed */
	AUDIO_OUTPUT_SYNCHRONOUS,

	/* Synchronous playback */
	AUDIO_OUTPUT_SYNCH_PLAYBACK

} espeak_AUDIO_OUTPUT
]]
ffi.cdef [[
typedef enum {
	EE_OK=0,
	EE_INTERNAL_ERROR=-1,
	EE_BUFFER_FULL=1,
	EE_NOT_FOUND=2
} espeak_ERROR;
]]
ffi.cdef [[
int espeak_Initialize(espeak_AUDIO_OUTPUT output, int buflength, const char *path, int options)
]]
ffi.cdef [[
espeak_ERROR espeak_SetVoiceByName(const char *name)
]]
ffi.cdef [[
typedef enum {
	POS_CHARACTER = 1,
	POS_WORD,
	POS_SENTENCE
} espeak_POSITION_TYPE;
]]
ffi.cdef [[
espeak_ERROR espeak_Synth(const void *text,
	size_t size,
	unsigned int position,
	espeak_POSITION_TYPE position_type,
	unsigned int end_position,
	unsigned int flags,
	unsigned int* unique_identifier,
	void* user_data);
]]
ffi.cdef [[
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
]]
ffi.cdef [[
typedef enum {
  espeakPUNCT_NONE=0,
  espeakPUNCT_ALL=1,
  espeakPUNCT_SOME=2
} espeak_PUNCT_TYPE;
]]
ffi.cdef [[
espeak_ERROR espeak_SetParameter(espeak_PARAMETER parameter, int value, int relative)
]]
ffi.cdef [[
espeak_ERROR espeak_Cancel(void)
]]
ffi.cdef [[
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
]]
ffi.cdef [[
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
ffi.cdef [[
espeak_ERROR espeak_Char(wchar_t character)
]]

local lib_espeak_ng_path = 'libespeak-ng.so'

if jit.os == 'Windows' then
	lib_espeak_ng_path =[[C:\Program Files\eSpeak NG\libespeak-ng.dll]]
elseif jit.os == 'Linux' then
	lib_espeak_ng_path = '/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1'
else
	lib_espeak_ng_path = 'espeak-ng.so'
end
local libespeak_ng = ffi.load(lib_espeak_ng_path)

-- Initializing libspeak-ng
local output = ffi.new('espeak_AUDIO_OUTPUT', 'AUDIO_OUTPUT_PLAYBACK')
libespeak_ng.espeak_Initialize(output, 0, nil, 0)
libespeak_ng.espeak_SetVoiceByName('en+Gene')
libespeak_ng.espeak_SetParameter(ffi.new('espeak_PARAMETER', 'espeakRATE'), 300, 0)
libespeak_ng.espeak_SetParameter(
	ffi.new('espeak_PARAMETER', 'espeakPUNCTUATION'),
	ffi.new('espeak_PUNCT_TYPE', 'espeakPUNCT_ALL'),
	0
)

local identifier = ffi.new('unsigned int*')
local flags = require('bit').bor(0X0, 0X100, 0X1000)
local position_type = ffi.new('espeak_POSITION_TYPE', 'POS_CHARACTER')
local user_data = ffi.new('void *')

m.speak = function(text, opts)
	if text == nil then
		text = ''
	end
	log.debug('Speaking: ' .. vim.inspect(text))
	if #text == 1 then
		libespeak_ng.espeak_Char(string.byte(text))
		return
	end
	libespeak_ng.espeak_Synth(
		text,
		#text + 1,
		0, -- Where to start synth
		position_type,
		0,
		flags,
		identifier,
		user_data
	)
end

m.stop = function()
	libespeak_ng.espeak_Cancel()
end

return m
