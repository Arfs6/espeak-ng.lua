/**
 * Audio playback for the Lua binding.
 *
 * This is the only translation unit that includes miniaudio's implementation.
 * Lua queues samples with mana_audio_buffer_write(), and miniaudio consumes
 * them in data_callback() on its audio thread.
 */
#include <assert.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

_Static_assert(sizeof(short) == 2, "Audio requires 16-bit short");

_Static_assert(SHRT_MAX == 32767, "Audio requires signed 16-bit short");

/* Result codes shared with lua/espeak-ng/audio.lua. */
typedef enum {
  MANA_AUDIO_SUCCESS,
  MANA_AUDIO_ERR,
  MANA_AUDIO_ERR_MEMORY,
  MANA_AUDIO_ERR_BUFFER,
} ManaAudioResult;

/*
 * readPos/writePos are monotonically increasing sample counters, not array
 * indexes. The array index is always the counter modulo bufferCapacity.
 * Absolute counters avoid the full/empty ambiguity of a plain ring buffer.
 */
typedef struct {
  bool initialized;
  ma_device device;
  bool deviceInitialized;
  short *buffer;
  uint32_t bufferCapacity;
  _Atomic uint64_t readPos;
  _Atomic uint64_t writePos;
} ManaAudioState;

/* Process-wide playback state; miniaudio's callback receives a pointer to it. */
static ManaAudioState g_state;

/*
 * Audio-thread callback. It never blocks: it copies whatever is queued, pads
 * the rest of the output with silence, then publishes how far it has read.
 * The Lua producer is the only writer to writePos; this callback is the only
 * writer to readPos.
 */
static void data_callback(ma_device *pDevice, void *pOutput, const void *pInput,
                          ma_uint32 frame_count) {
  short *pOut = (short *)pOutput;
  ManaAudioState *state = (ManaAudioState *)pDevice->pUserData;

  memset(pOut, 0, frame_count * sizeof(*pOut)); // reset to silence.

  if (state == NULL) {
    return;
  }

  uint64_t readPos =
      atomic_load_explicit(&state->readPos, memory_order_relaxed);
  uint64_t writePos =
      atomic_load_explicit(&state->writePos, memory_order_acquire);
  assert(readPos <= writePos);

  if (readPos == writePos) {
    // empty buffer.
    return;
  }

  // Never read past the queued samples or past the requested frame count.
  uint32_t available = writePos - readPos;

  if (available > frame_count) {
    available = frame_count;
  }
  // Split the copy when the queued range wraps around the buffer end.
  uint32_t first = state->bufferCapacity - (readPos % state->bufferCapacity);
  if (available < first) {
    first = available;
  }
  uint32_t second = available - first;
  memcpy(pOut, &state->buffer[readPos % state->bufferCapacity],
         first * sizeof(short));
  if (second > 0) {
    memcpy(pOut + first, &state->buffer[0], second * sizeof(short));
  }
  atomic_store_explicit(&state->readPos, readPos + available,
                        memory_order_release);

  (void)pInput;
}

/*
 * Stop playback and release all owned resources. Safe to call when only part
 * of initialization succeeded, and safe to call more than once.
 */
void mana_audio_uninit(void) {
  if (g_state.deviceInitialized == true) {
    ma_device_uninit(&g_state.device);
  }
  if (g_state.buffer != NULL) {
    free(g_state.buffer);
    g_state.buffer = NULL;
  }
  memset(&g_state, 0, sizeof(g_state));
}

/*
 * Initialize a mono signed-16-bit playback device and its ring buffer.
 * Returns success if already initialized. Any failure unwinds partial state
 * and leaves the module ready for another attempt.
 */
ManaAudioResult mana_audio_init(uint32_t sampleRate) {
  if (g_state.initialized == true) {
    return MANA_AUDIO_SUCCESS;
  }
  ma_device_config deviceConfig;
  ma_device *device = &g_state.device;

  // Playback is mono s16; the sample rate comes from espeak's initialization.
  deviceConfig = ma_device_config_init(ma_device_type_playback);
  deviceConfig.playback.format = ma_format_s16;
  deviceConfig.playback.channels = 1;
  deviceConfig.sampleRate = sampleRate;
  deviceConfig.dataCallback = data_callback;
  deviceConfig.pUserData = &g_state;

  if (ma_device_init(NULL, &deviceConfig, device) != MA_SUCCESS) {
    mana_audio_uninit();
    return MANA_AUDIO_ERR;
  }
  g_state.deviceInitialized = true;

  // Space for 1,048,576 mono samples (about 21 seconds at 48 kHz).
  g_state.bufferCapacity = 1048576;
  g_state.buffer = calloc(g_state.bufferCapacity, sizeof(*g_state.buffer));
  if (g_state.buffer == NULL) {
    mana_audio_uninit();
    return MANA_AUDIO_ERR_MEMORY;
  }
  atomic_init(&g_state.readPos, 0);
  atomic_init(&g_state.writePos, 0);
  if (atomic_is_lock_free(&g_state.writePos) == false ||
      atomic_is_lock_free(&g_state.readPos) == false) {
    mana_audio_uninit(); // todo: tell the user to create an issue.
    return MANA_AUDIO_ERR;
  }

  if (ma_device_start(device) != MA_SUCCESS) {
    mana_audio_uninit();
    return MANA_AUDIO_ERR;
  }
  g_state.initialized = true;

  return MANA_AUDIO_SUCCESS;
}

/*
 * Producer side called from Lua. It either queues all requested samples or
 * returns MANA_AUDIO_ERR_BUFFER without writing a partial block, so the caller
 * can retry later when the audio thread has drained space.
 */
ManaAudioResult mana_audio_buffer_write(const short *samples,
                                        uint32_t numSamples) {
  if (g_state.initialized == false || (samples == NULL && numSamples != 0)) {
    return MANA_AUDIO_ERR;
  }
  if (numSamples == 0) {
    return MANA_AUDIO_SUCCESS;
  }

  uint64_t writePos =
      atomic_load_explicit(&g_state.writePos, memory_order_relaxed);
  uint64_t readPos =
      atomic_load_explicit(&g_state.readPos, memory_order_acquire);
  assert(readPos <= writePos);
  uint32_t writeIdx = writePos % g_state.bufferCapacity;

  if (writePos - readPos == g_state.bufferCapacity) {
    return MANA_AUDIO_ERR_BUFFER; // buffer is full.
  }
  if (g_state.bufferCapacity - (writePos - readPos) < numSamples) {
    return MANA_AUDIO_ERR_BUFFER; // Not enough space to write samples.
  }
  // Copy in at most two pieces when the write wraps past the array end.
  uint32_t first = g_state.bufferCapacity - writeIdx;
  if (numSamples < first) {
    first = numSamples;
  }
  uint32_t second = numSamples - first;
  memcpy(g_state.buffer + writeIdx, samples, first * sizeof(short));
  if (second > 0) {
    memcpy(g_state.buffer, samples + first, second * sizeof(short));
  }
  atomic_store_explicit(&g_state.writePos, writePos + numSamples,
                        memory_order_release);

      return MANA_AUDIO_SUCCESS;
}
