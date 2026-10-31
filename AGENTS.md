# AGENTS.md

LuaJIT/Neovim bindings for espeak-ng, with a small C audio layer built on miniaudio.

## Build

- `just build` compiles **`c/audio.c` only** into `lua/espeak-ng/audio.so`:
  `gcc -Wall -Werror -shared -fPIC c/audio.c -ldl -lpthread -lm -o lua/espeak-ng/audio.so`
- Run it after every C change. Warnings are errors (`-Werror`).
- `c/miniaudio.h` is header-only; only `c/audio.c` defines `MINIAUDIO_IMPLEMENTATION`. Do not define it in another translation unit.
- The `.so` is gitignored and loaded from its module directory by `lua/espeak-ng/audio.lua`, so no install step is needed.

## Run

- Load modules from the repo root with:
  `LUA_PATH='./lua/?.lua;;' nvim -l lua/main.lua`
- `lua/main.lua` is the demo entrypoint; it requires a working audio device.
- `lib.lua` loads libespeak-ng from a hardcoded Linux path, `/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1`. The system package must be installed.
- Logging goes to `espeak-ng.log` (or Neovim's log dir), not stdout.

## Boundaries

- `c/audio.c` exposes a C ABI consumed via LuaJIT FFI in `lua/espeak-ng/audio.lua`. Keep `ffi.cdef` signatures and result codes in sync with `ManaAudioResult` (`0` success, `1` error, `2` memory, `3` buffer full).
- `data_callback` runs on miniaudio's audio thread and reads a fixed 1,048,576-sample ring buffer using atomics.
- `lua/espeak-ng/mana.lua` is the integration layer: espeak-ng init -> synth callback -> audio buffer; `lib.lua` is the raw espeak-ng FFI binding.

## Tests

- `tests/` exists but is empty; no test runner is configured yet.
- When adding tests, record the test path and the exact single-test command here.

## Commit messages

Use `type(scope) - Summary` for the first line, then a blank line and details.
Keep related files in one commit.

```text
docs(README.md) - Added new instruction ...
description / details
```

## Keeping this file current

Update AGENTS.md in the same change whenever you add durable, non-obvious information: a test (path + command), a build/lint/format step, a new module entrypoint, or a setup/toolchain quirk. Keep it short; omit generic advice and facts obvious from filenames.

Planning notes currently live in `docs/TODO.md` and the `todo` files under `c/` and `lua/espeak-ng/`.
