# wayvnc — VNC access to the live Hyprland session, for the laptop and the
# phone on the LAN/tailnet. wayvnc captures ONE output per process (or every
# output composited side-by-side with --desktop, added in 0.10), so this
# module runs one instance per "view", each on its own port. Pick the monitor
# from the client by picking the port — no VNC client can switch the captured
# output itself; that is a server-side concept (`wayvncctl output-set`).
#
# There is deliberately NO authentication: the instances bind 0.0.0.0 but the
# firewall only opens the ports on the physical LAN interface (see the host's
# configuration.nix), the same stance as the T3 Code web UI on 3773. Tailnet
# devices come in through the subnet router, so they arrive on that same
# interface. If this box ever gets an interface facing an untrusted network,
# that firewall line is the thing to revisit, not this file.
#
# Not enabled on purpose:
#   --gpu          hardware H.264 needs the Open H.264 RFB extension, which
#                  neither TigerVNC nor AVNC decode — and wayvnc can crash
#                  outright when GPU init fails (any1/wayvnc#327).
#   --render-cursor  compositing the cursor into every frame costs bandwidth;
#                  clients render the cursor themselves. Turn it on if the
#                  pointer turns out to be invisible from some client.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.wayvnc = {
    instances = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              example = "desktop";
            };
            port = lib.mkOption {
              type = lib.types.port;
              example = 5900;
            };
            output = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "DP-3";
              description = "Output to capture. null captures all outputs composited into one framebuffer (--desktop).";
            };
          };
        }
      );
      default = [ ];
    };
  };

  config =
    let
      cfg = config.wayvnc;
    in
    lib.mkIf (cfg.instances != [ ]) {
      # wayvncctl on PATH, for poking a running instance
      # (`wayvncctl -S $XDG_RUNTIME_DIR/wayvnc-<name>.sock output-list`).
      home.packages = [ pkgs.wayvnc ];

      # hyprland-session.target rather than graphical-session.target for the
      # same reason erikshell.nix gives: it is the target Hyprland itself
      # starts right after WAYLAND_DISPLAY lands in the user manager's
      # environment, so it is the honest "compositor is up and reachable"
      # signal — and wayvnc dies without a compositor to capture.
      systemd.user.services = lib.listToAttrs (
        map (
          i:
          lib.nameValuePair "wayvnc-${i.name}" {
            Unit = {
              Description = "wayvnc VNC server (${
                if i.output == null then "all outputs" else i.output
              }, port ${toString i.port})";
              After = [ "hyprland-session.target" ];
              PartOf = [ "hyprland-session.target" ];
            };

            Service = {
              # Each instance needs its own control socket — they would all
              # try to bind $XDG_RUNTIME_DIR/wayvncctl otherwise. %t is
              # XDG_RUNTIME_DIR.
              #
              # --keyboard pins the virtual keyboard's xkb layout instead of
              # inheriting whatever the unit environment happens to hold.
              # VNC clients send keysyms, so this mostly only matters for
              # keys the layout cannot express.
              ExecStart =
                "${pkgs.wayvnc}/bin/wayvnc"
                + (if i.output == null then " --desktop" else " --output=${i.output}")
                + " --keyboard=us"
                + " --socket=%t/wayvnc-${i.name}.sock"
                + " 0.0.0.0 ${toString i.port}";
              Restart = "on-failure";
              RestartSec = 2;
            };

            Install.WantedBy = [ "hyprland-session.target" ];
          }
        ) cfg.instances
      );
    };
}
