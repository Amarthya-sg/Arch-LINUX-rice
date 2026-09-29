#!/usr/bin/env bash
# Launch the status bar with settings that trade a little speed for RAM.
#   LEAN_SOFTWARE=1 ./run-lean.sh   # also use software rendering (biggest saving)
cd "$(dirname "$(readlink -f "$0")")" || exit 1

export MALLOC_ARENA_MAX=2                 # fewer glibc arenas for Qt's threads
export MALLOC_TRIM_THRESHOLD_=131072      # give freed heap back sooner
export QT_QUICK_CONTROLS_STYLE=Basic      # lightest Controls style

if [ "${LEAN_SOFTWARE:-1}" = "1" ]; then
    export QT_QUICK_BACKEND=software      # skips loading the GPU driver stack
fi

exec quickshell -p ./shell.qml "$@"
