#!/usr/bin/env bash
# Every voice of the TTS models small enough for the homelab GTX 1060 (3 GB),
# on CPU, at TTS_SPEED. Output: $D/raw/<engine>-<voice>.wav and results.jsonl
set -u
D=${1:-/mnt/data/read-aloud-bench/small-voices}
export TTS_SPEED=${TTS_SPEED:-1.2}
cd "$(dirname "$(realpath "$0")")"
run() { # image engine voice
  local out="$D/raw/$2-$3.wav"
  [ -s "$out" ] && return
  r=$(tts/run.sh "$1" "$2:@$3" "$D/text.txt" "$out" 2>&1 | grep '^RESULT' | cut -c8-)
  echo "{\"engine\":\"$2\",\"voice\":\"$3\",\"result\":${r:-null}}" >> "$D/results.jsonl"
}
for v in af_alloy af_aoede af_bella af_heart af_jessica af_kore af_nicole af_nova af_river af_sarah af_sky am_adam am_echo am_eric am_fenrir am_liam am_michael am_onyx am_puck am_santa bf_alice bf_emma bf_isabella bf_lily bm_daniel bm_fable bm_george bm_lewis; do
  [[ $v == b* ]] && eng=kokoro-cpu-gb || eng=kokoro-cpu
  run rab-kokoro "$eng" "$v"
done
for v in M1 M2 M3 M4 M5 F1 F2 F3 F4 F5; do run rab-supertonic supertonic "$v"; done
for v in cosette marius javert alba jean anna vera fantine charles paul eponine azelma george mary jane michael eve; do run rab-pocket pocket "$v"; done
echo DONE
