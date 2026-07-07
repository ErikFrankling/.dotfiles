{
  pkgs,
  inputs,
  config,
  ...
}:

{
  imports = [ inputs.voxtype.homeManagerModules.default ];

  # On-screen recording indicator. The daemon prefers `voxtype-osd-gtk4`;
  # without it on PATH it logs an error and runs with no overlay.
  home.packages = [ inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.osd-gtk4 ];

  # Taken from: https://github.com/peteonrails/voxtype/blob/dev/nix/home-manager-module.nix
  programs.voxtype = {
    enable = true;
    engine = "parakeet";
    # Parakeet ONNX build. CPU/AVX runs ~30x realtime — plenty for live
    # streaming, and avoids GPU-driver fragility. Swap to parakeet-rocm /
    # parakeet-cuda if you ever want to offload to the GPU.
    package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.parakeet;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.parakeet-rocm;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.rocm;
    # package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default;
    # model.name = "base.en";
    service.enable = true;
    settings = {
      # Recording is driven from Hyprland via `voxtype record start/stop`,
      # not voxtype's own hotkey. mode = "toggle" silences the "auto-promoting
      # to toggle" warning streaming emits (the only mode streaming supports).
      hotkey.enabled = false;
      hotkey.mode = "toggle";
      output.pre_type_delay_ms = 250;

      # Before/after each streamed-text injection, drop Hyprland into an empty
      # submap so the synthetic keystrokes (letters, BackSpace, …) can't trigger
      # any keybind — no window shortcuts firing, no accidental stop/cancel, no
      # modifier-fusion freeze. The hooks fire per chunk in streaming mode.
      # Pairs with the `voxtype_suppress` submap in the Hyprland config.
      # hyprctl is on the user-service PATH with HYPRLAND_INSTANCE_SIGNATURE set.
      output.pre_output_command = "hyprctl dispatch submap voxtype_suppress";
      output.post_output_command = "hyprctl dispatch submap reset";

      # Voice-activity detection auto-cancels the recording after a few seconds
      # of "no speech", so any pause to think ends dictation. Disable it — we
      # start/stop explicitly from Hyprland, and Parakeet (a transducer) emits
      # nothing during silence anyway, so there's no hallucination to filter.
      vad.enabled = false;
      # Default cap is 60s. Raise it so multi-minute dictation isn't truncated.
      audio.max_duration_secs = 1800;
      parakeet = {
        # English-only, cache-aware streaming model. Download once with:
        #   voxtype setup model parakeet-unified-en-0.6b
        # (the tdt-0.6b-v3 model is more accurate but does NOT support streaming).
        model = "parakeet-unified-en-0.6b";
        # Type text incrementally, live as you speak.
        streaming = true;
        # These must be set explicitly: voxtype's internal default
        # left_context maps to a mel-frame count not divisible by 8 and the
        # daemon refuses to start. 5.6 / 0.32 / 0.32 are the documented values
        # that satisfy the constraint. (chunk = how often partials are emitted,
        # left = history per chunk, right = lookahead.)
        streaming_chunk_secs = 0.32;
        streaming_left_context_secs = 5.6;
        streaming_right_context_secs = 0.32;
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
