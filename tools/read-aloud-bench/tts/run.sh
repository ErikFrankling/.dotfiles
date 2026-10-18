#!/usr/bin/env bash
# run.sh IMAGE ENGINE_SPEC TEXT_FILE OUT_WAV  (GPU, HF cache shared with the host)
img=$1; shift
exec docker run --rm --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --ipc=host \
  --user 1000:100 --group-add "$(getent group render | cut -d: -f3)" --group-add "$(getent group video | cut -d: -f3)" \
  -e HOME=/tmp -e TTS_SPEED="${TTS_SPEED:-1.0}" -e HF_HOME=/hf -e HF_HUB_DISABLE_TELEMETRY=1 -e PYTHONWARNINGS=ignore -e NUMBA_CACHE_DIR=/tmp/numba -e MIOPEN_FIND_MODE=FAST -e MIOPEN_USER_DB_PATH=/miopen -e MIOPEN_CUSTOM_CACHE_DIR=/miopen \
  -v "$HOME/.cache/huggingface:/hf" -v /mnt/data/read-aloud-bench:/mnt/data/read-aloud-bench \
  -v /mnt/data/tts/cache/miopen:/miopen \
  -v "$(dirname "$(realpath "$0")"):/bench:ro" --entrypoint python "$img" /bench/synth.py "$@"
