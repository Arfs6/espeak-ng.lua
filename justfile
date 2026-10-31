build:
    gcc -Wall -Werror -shared -fPIC c/audio.c -ldl -lpthread -lm -o lua/espeak-ng/audio.so
