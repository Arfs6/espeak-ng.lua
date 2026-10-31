# Todo

- Remove the assert in c/audio.c:data_callback - replace it with a reset of buffer and logging the information.
- Remove the assert in c/audio.c:mana_audio_write and replace with a reset of the buffer, and logging the issue.
- Write a documentation stating that a full buffer expects the caller to try again.
