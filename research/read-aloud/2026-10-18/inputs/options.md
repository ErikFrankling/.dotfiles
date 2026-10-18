I've finished looking around your setup. The answer depends on a few things already on your machines, so here's what I found and what I'd build.

## What you already have, and the problem with it

- **Dictation** (`local-stt`) keeps a ~10 GB recogniser loaded on the PC's GPU.
- **Breeze TTS 2** is already in llama-swap. It needs ~7.7 GB of video memory, and when it starts it unloads dictation first (`releaseStt` in `modules/nixos/llama-swap.nix`).
- 10 + 7.7 + ~3.5 GB for Hyprland is more than the 20 GB card has. So "dictate, listen, dictate, listen" with Breeze would keep unloading and reloading both models. Every reload is a cold start: Docker plus loading the model, likely tens of seconds.
- **The homelab GPU** is a GTX 1060 with **3 GB**, passed into k3s and sitting idle. Breeze and any useful LLM are too big for it. A small TTS model fits easily.

## Step 1: the summary (rewrite the message for listening)

| Option | Speed | Problem |
|---|---|---|
| **A. One API call to a cheap cloud model** (Haiku 5.5) from the T3 server, outside the chat | ~1 s to first words, streams | Costs a fraction of a cent per message. The text already goes to a cloud model anyway. |
| B. Headless `claude -p` / `codex exec` / opencode session | 5–15 s to start each time, ~0.5–1 GB RAM | Slow for a quick "read this", and heavier than it needs to be |
| C. Tiny local LLM (Qwen 4B, ~3 GB) on the PC | Fast once loaded | Takes video memory from dictation, so the same reload problem |
| D. Tiny LLM on the 1060 | Fits only ~1.5B models | Takes the room TTS needs, and 1.5B models write poor summaries |

**Recommendation: A.** It never touches the chat's context, because it's a separate one-shot request whose result is never written into the conversation. The system prompt would be the `/bro` skill plus spoken-style rules: no markdown, lists, paths or code, just what happened, what it means for you and what's next. It also scales with the message: a few sentences normally, longer when there's more to say.

## Step 2: the voice

| Option | Quality | Problem |
|---|---|---|
| **Kokoro (82M) on the homelab 1060**, always loaded | Good, not Breeze-level | Doesn't touch the PC's GPU and is faster than real time |
| Breeze on the PC | Best | Fights dictation and starts cold, as above |
| Browser built-in speech | Robotic | No setup at all, so it works as a fallback |

**Recommendation: Kokoro on the homelab.** I haven't tested it on the 1060 yet. The card is old (Pascal), and new PyTorch builds may no longer support it, so I'd use the ONNX version of Kokoro or an older CUDA build. Breeze can stay as an optional "nice voice" for when you aren't dictating.

## Step 3: putting it together

The summary streams in, and each finished sentence goes straight to Kokoro. Audio starts about 1–2 s after you click, not after the whole summary is written.

**UI in the T3 Code fork:**
- A speaker icon in each message's action row (next to copy) that reads that message.
- A pinned floating "read latest" button near the composer, plus a keyboard shortcut.
- A subtitle panel at the bottom that shows the summary with the current sentence highlighted, with pause, skip sentence, speed, and "read full message instead". Word-by-word highlighting may also be possible: some Kokoro servers return word timings, but I haven't checked.
- Summaries and audio are cached per message, so replays are instant.

**The work:** a Kokoro deployment in the homelab repo, plus a `/api/read-aloud` endpoint and the UI in the T3 Code fork. I'd need a Claude API key (through `request_secret`) unless you'd rather pay through opencode's cheap models.

Want me to build A + Kokoro, or would you rather keep everything local and accept the GPU tradeoffs?
