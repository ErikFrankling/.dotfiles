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

  # Opens the "Recording now" window in the running T3 desktop app.
  replyWindow = pkgs.writeShellScript "speak-reply-window" ''
    exec ${pkgs.t3code}/bin/t3 app speak-reply "$@"
  '';
in
{
  options.speak.speakers = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "This host has Erik's speakers: run the speak daemon here (the PC only).";
  };

  config = lib.mkMerge [
    {
      home.packages = [ speak ];

      # Only the personal agent gets the tool. Project MCP servers need
      # approval; the project's settings.json gives it for this one server.
      home.file.".t3/personal/.mcp.json".text = builtins.toJSON {
        mcpServers.speak = {
          type = "stdio";
          command = lib.getExe speak;
          args = [ "mcp" ];
        };
      };
      home.file.".t3/personal/.claude/settings.json".text = builtins.toJSON {
        enabledMcpjsonServers = [ "speak" ];
      };
    }

    (lib.mkIf cfg.speakers {
      systemd.user.services.speak = {
        Unit = {
          Description = "Speak the personal agent's messages on the PC's speakers";
          After = [ "pipewire.service" ];
        };
        Service = {
          StateDirectory = "speak";
          ExecStart = "${lib.getExe speak} daemon";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "SPEAK_CHIME=${chime}"
            "SPEAK_VOXTYPE=${config.home.profileDirectory}/bin/voxtype"
            # Turned on once the fork ships `t3 app speak-reply` (the "Recording now" window).
            # "SPEAK_REPLY_COMMAND=${replyWindow}"
            "SPEAK_AWAY_NOTIFY=${config.home.profileDirectory}/bin/notify-erik"
            # Same small voice as T3's read-aloud (hosts/pc/home.nix).
            "SPEAK_SMALL_TTS_URL=http://192.168.50.100:8880/v1/audio/speech"
            "SPEAK_SMALL_VOICE=af_heart"
            "SPEAK_SMALL_SPEED=1.2"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };

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
