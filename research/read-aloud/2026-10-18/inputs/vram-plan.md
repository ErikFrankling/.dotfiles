The key fact: with nothing loaded in llama-swap, the PC is using **14.2 GB right now**. That's dictation plus the desktop, so 5.7 GB is free. A small summary model fits next to dictation permanently. The voice model goes on the homelab, so the two models you switch between never push each other out.

**How the plan works:**

1. **Dictation stays loaded all the time,** same as today.
2. **A ~4B summary model (around 3 GB with its context memory) stays loaded too,** in its own llama-swap group set to never swap out and stay loaded. It must not use the `releaseStt` wrapper, or it would kick dictation out. Once it's always loaded, there's no load time when you click. On the 7900 XT a 4B model reads a long message in about a second.
3. **Kokoro runs on the 1060 in the homelab, always loaded.** It doesn't touch the PC's GPU at all.
4. **The 27B models and Breeze stay "big mode", exclusive like now.** Loading one unloads dictation and the summary model, and both come back when it times out. If you never ask for a 27B or Breeze, nothing ever gets kicked out.

**Risks:**

- **The worst case leaves only ~1.2 GB of room.** The tightest moment is your dictation finishing its final pass while a summary runs. If browsers take more GPU memory than usual, the monitor that stops dictation above 19.5 GiB could kill it. The fallback is a ~2B model (~1.8 GB), which leaves about 2.5 GB of room but writes weaker summaries. I'd test the 4B first and measure.
- **Some numbers are estimates.** The ~3.5 GB desktop / ~10.7 GB dictation split is my estimate from the 14.2 GB measurement. The Kokoro size isn't measured, and I still need to check that Kokoro runs on the 1060 (the ONNX build is the likely route). The 3 GB for the 4B model is from typical sizes, not tested here.
- **The chart above wasn't checked before showing.** The HTML preview tool needs browser libraries this host doesn't have, so I couldn't render it first.

**All-local vs. the cloud option:** this plan gives up ~3 GB of the PC's GPU and gets summaries that are a bit weaker than Haiku's. In return nothing leaves your network and nothing costs money. If the 4B summaries turn out bad, switching only that step to the cloud keeps the rest of the plan the same.

Should I build it this way: summary-model group in `modules/nixos/llama-swap.nix`, Kokoro in the homelab repo, then the endpoint and UI in the T3 Code fork?
