# speak: the personal agent may talk to Erik out loud, unprompted, but only on
# the PC's speakers (Erik, 2026-10-23: "In speakers, you're allowed to talk to
# me [on the desktop] ... on the laptop and on the phone [never]"), and never
# while he is talking: a message made while he dictates plays right after he
# sends. Afterwards the T3 desktop app opens a small "Recording now" window so
# he answers by voice.
#
# - `speak mcp`: stdio MCP server (tools `speak`, `speak_status`), registered
#   only in the personal agent's project (~/.t3/personal/.mcp.json). It
#   refuses on every host but the PC.
# - `speak daemon` (PC, `speak.speakers = true`): queue, audio made at once
#   with the read-aloud voices, plays on the default PipeWire sink. Log:
#   ~/.local/state/speak/utterances.jsonl.
# - speak-presence: swayidle marks Erik away after 5 idle minutes.
#   Rules in speak.py (`gate`); tests run at build time.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.speak;
  python = pkgs.python3;

  src = pkgs.runCommand "speak-src" { nativeBuildInputs = [ python ]; } ''
    mkdir -p $out
    cp ${./speak.py} $out/speak.py
    cp ${./test_speak.py} test_speak.py
    cp ${./speak.py} speak.py
    PYTHONDONTWRITEBYTECODE=1 python -m unittest -v test_speak
  '';

  # A soft two-note chime (E6 then B6), quiet, ~0.45 s.
  chime = pkgs.runCommand "speak-chime.wav" { nativeBuildInputs = [ pkgs.ffmpeg-headless ]; } ''
    ffmpeg -hide_banner -loglevel error \
      -f lavfi -i "sine=frequency=1318.5:duration=0.22" \
      -f lavfi -i "sine=frequency=1975.5:duration=0.4" \
      -filter_complex "[0]afade=t=in:d=0.01,afade=t=out:st=0.03:d=0.19,volume=0.12[a];[1]afade=t=in:d=0.01,afade=t=out:st=0.05:d=0.35,volume=0.09[b];[a][b]concat=n=2:v=0:a=1,apad=pad_dur=0.15" \
      -ar 24000 -ac 1 $out
  '';

  speak = pkgs.writeShellApplication {
    name = "speak";
    runtimeInputs = [
      pkgs.pipewire
      pkgs.wireplumber
      pkgs.coreutils
    ];
    text = ''exec ${python}/bin/python3 ${src}/speak.py "$@"'';
  };

  # The T3 desktop app runs this (T3CODE_DICTATION_HOOK, overlays/t3code.nix)
  # with `recording` / `stopped` while any dictation records, the reply window
  # included: plain Enter anywhere sends it (Erik: "I'm never going to be
  # writing while recording"). Enter is plain Enter again the moment it stops.
  dictationHook = pkgs.writeShellApplication {
    name = "t3-dictation-hook";
    text = ''
      hyprctl=/run/current-system/sw/bin/hyprctl
      case "''${1-}" in
        recording) "$hyprctl" keyword bind ", Return, exec, ${pkgs.t3code}/bin/t3 app dictation --send" >/dev/null ;;
        *) "$hyprctl" keyword unbind ", Return" >/dev/null ;;
      esac
    '';
  };

  # Opens the "Recording now" window in the running T3 desktop app.
  replyWindow = pkgs.writeShellScript "speak-reply-window" ''
    exec ${pkgs.t3code}/bin/t3 app speak-reply "$@"
  '';
in
{
  imports = [ ../personal-agent-mcp.nix ];

  options.speak.speakers = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "This host has Erik's speakers: run the speak daemon here (the PC only).";
  };

  config = lib.mkMerge [
    {
      home.packages = [ speak ];

      # Only the personal agent gets the tool.
      personalAgent.mcpServers.speak = {
        type = "stdio";
        command = lib.getExe speak;
        args = [ "mcp" ];
      };
    }

    (lib.mkIf cfg.speakers {
      home.packages = [ dictationHook ];

      systemd.user.services.speak = {
        Unit = {
          Description = "Speak the personal agent's messages on the PC's speakers";
          After = [ "pipewire.service" ];
        };
        Service = {
          StateDirectory = "speak";
          # While a dictation records, t3-dictation-hook binds plain Enter to
          # "send". A safety net: Enter is plain Enter again whenever speak
          # starts or stops, however a recording ended.
          ExecStartPre = "-/run/current-system/sw/bin/hyprctl keyword unbind \", Return\"";
          ExecStart = "${lib.getExe speak} daemon";
          ExecStopPost = "-/run/current-system/sw/bin/hyprctl keyword unbind \", Return\"";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "SPEAK_CHIME=${chime}"
            "SPEAK_NOTIFY_SEND=${pkgs.libnotify}/bin/notify-send"
            "SPEAK_VOXTYPE=${config.home.profileDirectory}/bin/voxtype"
            "SPEAK_REPLY_COMMAND=${replyWindow}"
            # notify-erik is a system package (modules/nixos/notify).
            "SPEAK_AWAY_NOTIFY=/run/current-system/sw/bin/notify-erik"
            # Same small voice as T3's read-aloud (hosts/pc/home.nix).
            "SPEAK_SMALL_TTS_URL=http://192.168.50.100:8880/v1/audio/speech"
            "SPEAK_SMALL_VOICE=af_heart"
            "SPEAK_SMALL_SPEED=1.2"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };

      # The "Recording now" reply window (`t3 app speak-reply`, T3 fork): a
      # small card in the top-left corner of the monitor it opens on (beside
      # erikshell's 58 px rail; notifications keep the top right), above
      # everything, never taking focus. Its app-id is the main window's, so
      # it is matched by title. Send/cancel without clicking into it.
      wayland.windowManager.hyprland.extraConfig =
        lib.concatMapStrings
          (rule: ''
            windowrule = ${rule}, match:title ^(T3 Code — Speak reply)$
          '')
          [
            "float 1"
            "pin 1"
            "no_initial_focus 1"
            "size 420 240"
            "move 70 12"
          ];
      wayland.windowManager.hyprland.settings.bindd = [
        "$mod ALT, Return, Send the spoken reply, exec, ${replyWindow} --send"
        "$mod ALT, Escape, Close the spoken-reply window, exec, ${replyWindow} --cancel"
      ];

      # ext-idle-notify: no input for 5 minutes = Erik is away from the PC.
      systemd.user.services.speak-presence = {
        Unit = {
          Description = "Tell speak whether Erik is at the PC";
          After = [ "hyprland-session.target" ];
          PartOf = [ "hyprland-session.target" ];
        };
        Service = {
          StateDirectory = "speak";
          ExecStartPre = "${pkgs.coreutils}/bin/rm -f %S/speak/away";
          ExecStart = lib.concatStringsSep " " [
            "${lib.getExe pkgs.swayidle}"
            "-w"
            "timeout 300 '${pkgs.coreutils}/bin/touch %S/speak/away'"
            "resume '${pkgs.coreutils}/bin/rm -f %S/speak/away'"
          ];
          ExecStopPost = "${pkgs.coreutils}/bin/rm -f %S/speak/away";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "hyprland-session.target" ];
      };
    })
  ];
}
