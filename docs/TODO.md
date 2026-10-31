# Todo

- Remove the assert in c/audio.c:data_callback - replace it with a reset of buffer and logging the information.
- Remove the assert in c/audio.c:mana_audio_write and replace with a reset of the buffer, and logging the issue.
- Write a documentation stating that a full buffer expects the caller to try again.

## Planned API

- Create `voices.lua` so picking and changing the espeak-ng voice from Lua is straightforward.
- Create `setup.lua` with a setup function that initializes the library with a voice.
- Create `parameters.lua` for setting espeak-ng parameters.
- Add a field to `setup.lua` for configuring espeak-ng with default parameters.
- Design a Lua-style API for initializing and terminating espeak-ng.
- Add initialization variables such as audio output to `setup.lua`, so a user can call setup, then init, then use the parameters and voices APIs.
- Create a `speak` wrapper that ensures the library is initialized before speaking (`speak` is preferred over `speach`).
