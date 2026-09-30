---
name: screen-recording
description: Screen recordings and video demos on Erik's PC. Load whenever Erik asks for a recording, video, screencast, demo, walkthrough, or "show me" of something done in an app or browser, or for QA evidence as video. Covers recording the agent monitor, arranging windows for a clean shot, and adding captions/title cards so the video explains itself.
---

# Screen recordings and video demos

Erik likes it when you **communicate with video demos that explain themselves**:
record what you do on your monitor and burn short captions into the video
saying what is happening and why. Use this for QA evidence, feature demos, bug
reproductions and walkthroughs. Read **computer-use** (and **browser-use** for
web apps) first.

## 1. Set the stage

AGENT-1 is 1920x1080 and records exactly what workspace `agent` shows.

- Put **only the window you're demonstrating** on workspace `agent`; park
  everything else: `hyprctl -i 0 dispatch movetoworkspacesilent
  name:agent-park,address:0xADDR` (see computer-use). One window fills the
  screen and looks clean.
- Browser demos: the agent Chromium window. Close extra Playwright pages and
  navigate to the starting point before recording.
- Get the app into its starting state first, and check it with a screenshot
  (`agent-desktop screenshot ~/Videos/agent/check.png`) so the video doesn't open with
  setup noise.

## 2. Record

Use one folder per recording and keep everything in it:

```sh
D=~/Videos/agent/$(date +%F-%H%M)-short-name; mkdir -p "$D"
agent-desktop exec-session wf-recorder -D -r 30 -o AGENT-1 -f "$D/raw.mp4" > "$D/wf.log" 2>&1 &
echo $! > "$D/pid"; date +%s.%N > "$D/start"      # t=0 for captions
```

- Always `-o AGENT-1`: never record Erik's monitors.
- Always `-D -r 30`: constant 30 fps. Without it a static screen produces no
  frames and wf-recorder hangs when you stop it.
- `agent-desktop exec-session` provides the Wayland session variables your
  shell may lack. Start it as a background process, then do the task.
- Shell state may not persist between your tool calls: re-set `D=...` to the
  same folder each time (or use the absolute path).

While acting, **log a caption for each step** with its offset from the start:

```sh
cap() { awk -v s="$(cat "$D/start")" -v n="$(date +%s.%N)" -v t="$*" 'BEGIN{printf "%.2f\t%s\n", n-s, t}' >> "$D/captions.tsv"; }
cap "Open the settings page"
```

Pause ~1 s between steps so viewers can follow; the tools are faster than eyes.

Stop cleanly (SIGINT lets it finalize the file), then check the length:

```sh
kill -INT "$(cat "$D/pid")"; sleep 1
ffprobe -v error -show_entries format=duration -of csv=p=0 "$D/raw.mp4"
```

Alternative for a single window regardless of what else is on screen:
`mcp__agent-seat__record_window` / `stop_recording` (window-only MP4, max 10
min; needs a separate `record` permission that Erik approves manually, so
prefer wf-recorder).

## 3. Add captions and titles (ffmpeg)

Turn the caption log into an SRT (each caption lasts until the next one):

```sh
END=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$D/raw.mp4")
awk -F'\t' -v end="$END" '
  function ts(x){ return sprintf("%02d:%02d:%02d,%03d", x/3600, (x%3600)/60, x%60, (x-int(x))*1000) }
  { t[NR]=$1; c[NR]=$2 }
  END { for (i=1;i<=NR;i++) printf "%d\n%s --> %s\n%s\n\n", i, ts(t[i]), ts(i<NR ? t[i+1] : end), c[i] }
' "$D/captions.tsv" > "$D/captions.srt"
```

Burn captions (bottom, readable box) plus a title card for the first 3 s:

```sh
ffmpeg -y -i "$D/raw.mp4" -vf "\
subtitles=$D/captions.srt:force_style='FontSize=24,PrimaryColour=&H00FFFFFF,BackColour=&H20000000,BorderStyle=4,Outline=0,Shadow=0,MarginV=40',\
drawtext=text='Demo\: password reset flow':fontsize=44:fontcolor=white:box=1:boxcolor=black@0.7:boxborderw=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='lt(t,3)'" \
  -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart "$D/demo.mp4"
```

- Escape `:` as `\:` and `'` carefully inside drawtext text.
- Timed callouts anywhere: add more `drawtext=...:x=..:y=..:enable='between(t,5,8)'`.
- Highlight an area: `drawbox=x=100:y=200:w=400:h=80:color=yellow@0.8:t=4:enable='between(t,5,8)'`.
- Speed up boring waits: `ffmpeg -i in.mp4 -vf "setpts=0.5*PTS" out.mp4`
  (2x), or cut with `-ss START -to END`.
- Short GIF for a PR: `ffmpeg -i demo.mp4 -vf "fps=12,scale=960:-1:flags=lanczos" demo.gif`.

## 4. Check and deliver

- Grab frames to verify captions line up:
  `ffmpeg -ss 5 -i "$D/demo.mp4" -frames:v 1 "$D/frame5.png"`, then look at it.
- Deliver the final file path (`$D/demo.mp4`) with a 2-3 line summary of
  what the video shows. Keep the raw recording unless Erik says otherwise.
- Move parked windows back if the task continues.
