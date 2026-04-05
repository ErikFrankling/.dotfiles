# AGENTS.md

## Rebuild command

```shell
nh os switch /home/${username}/.dotfiles --hostname ${hostName}
```

## Local LLM Guidelines

### Background

The local LLM server runs on a desktop shared with Hyprland (the compositor). GPU VRAM is a shared resource — if the LLM uses too much VRAM, it will conflict with Hyprland and crash the entire system.

### Target Model Size

- **Target weights size: ~15.7 GB**
- This is based on `Qwen3.5-27B-IQ4_NL` running at 128k context, which barely fits in available VRAM.
- Always check the model's weight size on HuggingFace before downloading or loading a new model.
- Choose a quantization level that keeps the model size around **15.7 GB**.

### Workflow: Loading a New or Modified Model

Follow these steps **every time** to avoid crashing the system:

1. **Check model size** — Verify the model's weight size on HuggingFace. It should be around **15.7 GB**.
2. **Start with 4096 context** — Load the model with a low context length (4k) for the first run.
3. **Verify VRAM usage** — Use a monitoring tool (e.g., `nvtop`, `nvidia-smi`) to check how much VRAM is being used and how much is left.
4. **Confirm system stability** — Make sure Hyprland is still responsive and there are no graphical glitches.
5. **Increase context gradually** — Only after confirming the model works at 4k context and VRAM headroom is sufficient, increase to 128k context.
6. **Re-check VRAM** — After increasing context, verify VRAM usage again to ensure there is still headroom.

### Quick Reference

| Step | Action |
|------|--------|
| 1 | Check model weights size on HuggingFace (~15.7 GB target) |
| 2 | Start model at 4096 context |
| 3 | Monitor VRAM with `nvtop` or `nvidia-smi` |
| 4 | Confirm Hyprland is stable |
| 5 | Increase to 128k context only if VRAM allows |
| 6 | Re-check VRAM after increasing context |
