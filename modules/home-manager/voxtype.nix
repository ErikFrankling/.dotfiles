{
  pkgs,
  inputs,
  config,
  ...
}:

let
  voxtypeTranscriptCleanup = pkgs.writeTextFile {
    name = "voxtype-transcript-cleanup";
    destination = "/bin/voxtype-transcript-cleanup";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import json
      import os
      import re
      import sys
      import urllib.request

      transcript = sys.stdin.read()
      if not transcript.strip():
          sys.exit(0)

      endpoint = os.environ.get(
          "VOXTYPE_LLM_ENDPOINT",
          "http://192.168.50.232:8000/v1/chat/completions",
      )
      model = os.environ.get("VOXTYPE_LLM_MODEL", "qwen3.5-27b")
      timeout = int(os.environ.get("VOXTYPE_LLM_TIMEOUT_SECS", "55"))
      context = os.environ.get("VOXTYPE_CONTEXT", "").strip()

      system_prompt = """You are the final cleanup pass for technical voice dictation.
      Correct speech-recognition errors, punctuation, capitalization, paragraph breaks, and obvious filler words.
      Preserve the speaker's meaning and wording. Do not summarize. Do not answer. Do not add facts.
      Preserve technical tokens exactly when recognizable: file paths, URLs, package names, commands, flags, code symbols, versions, acronyms, and identifiers.
      Prefer programmer vocabulary when plausible: NixOS, Hyprland, PipeWire, systemd, llama.cpp, vLLM, Qwen, Parakeet, flake.nix, Home Manager, JavaScript, TypeScript, Python, Kubernetes, PostgreSQL.
      Return only the cleaned dictation text."""

      if context:
          user_prompt = (
              "Previous nearby dictation for context only:\n"
              + context
              + "\n\nCurrent dictation to clean:\n"
              + transcript
          )
      else:
          user_prompt = "Current dictation to clean:\n" + transcript

      payload = {
          "model": model,
          "temperature": 0,
          "max_tokens": 4096,
          "messages": [
              {"role": "system", "content": system_prompt},
              {"role": "user", "content": user_prompt},
          ],
      }

      request = urllib.request.Request(
          endpoint,
          data=json.dumps(payload).encode("utf-8"),
          headers={"Content-Type": "application/json"},
          method="POST",
      )

      try:
          with urllib.request.urlopen(request, timeout=timeout) as response:
              data = json.loads(response.read().decode("utf-8"))
          cleaned = data["choices"][0]["message"]["content"]
      except Exception as exc:
          print(f"voxtype cleanup failed: {exc}", file=sys.stderr)
          sys.exit(1)

      cleaned = re.sub(r"<think>.*?</think>", "", cleaned, flags=re.DOTALL).strip()
      if not cleaned:
          sys.exit(2)

      sys.stdout.write(cleaned)
    '';
  };
in
{
  imports = [ inputs.voxtype.homeManagerModules.default ];

  # On-screen recording indicator. The daemon prefers `voxtype-osd-gtk4`;
  # without it on PATH it logs an error and runs with no overlay.
  home.packages = [
    inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.osd-gtk4
    voxtypeTranscriptCleanup
  ];

  # Taken from: https://github.com/peteonrails/voxtype/blob/dev/nix/home-manager-module.nix
  programs.voxtype = {
    enable = true;
    engine = "parakeet";
    # Parakeet ONNX build. CPU/AVX is fast enough for local fallback dictation.
    # The final-output path uses the more accurate non-streaming TDT model and
    # a local/LAN Qwen cleanup pass instead of typing mutable partials.
    package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.parakeet;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.parakeet-rocm;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.rocm;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default;
    # model.name = "base.en";
    service.enable = true;
    settings = {
      # Recording is driven from Hyprland via `voxtype record toggle`, not
      # voxtype's own hotkey. Keep toggle mode so the compositor binding owns
      # session boundaries.
      hotkey.enabled = false;
      hotkey.mode = "toggle";

      # Final-output-first mode: do not stream mutable partial hypotheses into
      # the target app. Paste only the final cleaned transcript and restore the
      # clipboard after the paste lands.
      output.mode = "paste";
      output.restore_clipboard = true;
      output.restore_clipboard_delay_ms = 300;
      output.pre_type_delay_ms = 250;
      output.post_process.command = "${voxtypeTranscriptCleanup}/bin/voxtype-transcript-cleanup";
      output.post_process.timeout_ms = 60000;

      # Guard the final paste keystroke with the empty Hyprland submap used by
      # the existing `voxtype_suppress` integration.
      output.pre_output_command = "hyprctl dispatch submap voxtype_suppress";
      output.post_output_command = "hyprctl dispatch submap reset";

      # Voice-activity detection auto-cancels the recording after a few seconds
      # of "no speech", so any pause to think ends dictation. Disable it; we
      # start/stop explicitly from Hyprland.
      vad.enabled = false;
      # Default cap is 60s. Raise it so multi-minute dictation is not truncated.
      audio.max_duration_secs = 1800;
      parakeet = {
        # Better final-quality local fallback than the streaming unified model.
        # Download once into ~/.local/share/voxtype/models/parakeet-tdt-0.6b-v3.
        model = "parakeet-tdt-0.6b-v3";
        streaming = false;
      };
    };
  };

  xdg.configFile."voxtype/config.toml".force = true;

  # Restart the daemon on `home-manager switch` whenever the generated
  # config.toml changes. sd-switch only restarts a unit when the unit *text*
  # changes, and the voxtype unit never references config.toml — so without
  # this the daemon keeps running the config it loaded at startup.
  systemd.user.services.voxtype.Unit.X-Restart-Triggers = [
    config.xdg.configFile."voxtype/config.toml".source
  ];
}
