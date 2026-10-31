{
  config,
  pkgs,
  lib,
  username,
  ...
}:

let
  sig = "Mvh Erik Frankling";
  # Erik's one way into Thunderbird: the launcher entry, `thunderbird` on the
  # command line and mailto: links all run this. It starts the background
  # instance if needed, hands it any arguments (a mailto: opens a compose
  # window), then moves every Thunderbird window to the workspace Erik is
  # looking at and focuses it. Nothing else decides where his mail opens
  # (2026-10-26: a plain `thunderbird` only re-activated the hidden window on
  # the agent seat, so for him it "just did not work").
  launcher = pkgs.writeShellScriptBin "thunderbird" ''
    set -u
    real=${pkgs.thunderbird}/bin/thunderbird
    # The profile manager, and anything outside Hyprland: plain Thunderbird.
    case " $* " in *" --ProfileManager "* | *" -P "* | *" --headless "*) exec "$real" "$@" ;; esac
    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || ! hyprctl -j monitors >/dev/null 2>&1; then
      exec "$real" "$@"
    fi
    export PATH=${
      lib.makeBinPath [
        pkgs.jq
        pkgs.systemd
        pkgs.coreutils
      ]
    }:$PATH
    windows() { hyprctl -j clients | jq -c '[.[] | select(.class == "thunderbird")]'; }

    systemctl --user start thunderbird.service
    for _ in $(seq 1 60); do
      windows | jq -e 'length > 0' >/dev/null && break
      sleep 0.5
    done
    before=$(windows | jq -c 'map(.address)')
    if [ $# -gt 0 ]; then
      # A remote call into the running instance; it returns at once.
      "$real" "$@"
      for _ in $(seq 1 40); do
        windows | jq -e --argjson b "$before" 'any(.[]; .address as $a | $b | index($a) | not)' >/dev/null && break
        sleep 0.25
      done
    fi

    # Erik's workspace: the focused monitor's, unless focus sits on the
    # headless AGENT-1 output, then the one under his pointer.
    target=$({ hyprctl -j monitors; hyprctl -j cursorpos; } | jq -rs '
      .[1] as $c
      | [.[0][] | select(.name != "AGENT-1" and (.disabled | not))] as $m
      | ([$m[] | select(.focused)]
         + [$m[] | select($c.x >= .x and $c.x < .x + .width and $c.y >= .y and $c.y < .y + .height)]
         + $m)[0].activeWorkspace.name')
    all=$(windows)
    for address in $(echo "$all" | jq -r '.[].address'); do
      hyprctl dispatch movetoworkspacesilent "name:$target,address:$address" >/dev/null
    done
    # Focus the window just opened (a compose window), else the main window.
    focus=$(echo "$all" | jq -r --argjson b "$before" '
      ([.[] | select(.address as $a | $b | index($a) | not)]
       + [.[] | select(.initialTitle == "Mozilla Thunderbird")] + .)[0].address // empty')
    [ -n "$focus" ] && hyprctl dispatch focuswindow "address:$focus" >/dev/null
    exit 0
  '';
in
{
  options.thunderbird.autostart = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Keep Thunderbird running for the whole Hyprland session.";
  };

  config = {
    # Install package directly — bypassing programs.thunderbird module to get full user.js control
    home.packages = [
      pkgs.thunderbird
    ]
    ++ lib.optional config.thunderbird.autostart (lib.hiPrio launcher);

    home.file.".thunderbird/profiles.ini".force = true;
    home.file.".thunderbird/profiles.ini".text = ''
      [General]
      StartWithLastProfile=1
      Version=2

      [Profile0]
      Default=1
      IsRelative=1
      Name=default
      Path=default
    '';

    home.file.".thunderbird/default/user.js".text = ''
      // Thunderbird declarative config — managed by home-manager

      // Local Folders has to be in this list. Left out, Thunderbird found no
      // local account at every start and made a fresh one (account1..account38).
      user_pref("mail.accountmanager.accounts", "account_frankling,account_gmail1,account_gmail2,account_kth,account_outlook,account_local");
      user_pref("mail.accountmanager.localfoldersserver", "server1");
      user_pref("mail.account.account_local.server", "server1");
      user_pref("mail.server.server1.type", "none");
      user_pref("mail.server.server1.hostname", "Local Folders");
      user_pref("mail.server.server1.userName", "nobody");
      user_pref("mail.server.server1.name", "Local Folders");
      user_pref("mail.accountmanager.defaultaccount", "account_frankling");
      user_pref("mail.smtpservers", "smtp_frankling,smtp_gmail1,smtp_gmail2,smtp_kth,smtp_outlook");
      user_pref("mail.smtp.defaultserver", "smtp_frankling");

      // ===== Frankling — erik.frankling@frankling.se (Office 365, OAuth2) =====
      user_pref("mail.account.account_frankling.identities", "id_frankling");
      user_pref("mail.account.account_frankling.server", "server_frankling");
      user_pref("mail.identity.id_frankling.fullName", "Erik Frankling");
      user_pref("mail.identity.id_frankling.useremail", "erik.frankling@frankling.se");
      user_pref("mail.identity.id_frankling.valid", true);
      user_pref("mail.identity.id_frankling.smtpServer", "smtp_frankling");
      user_pref("mail.identity.id_frankling.htmlSigText", "${sig}");
      user_pref("mail.identity.id_frankling.sig_bottom", false);
      user_pref("mail.server.server_frankling.type", "imap");
      user_pref("mail.server.server_frankling.hostname", "outlook.office365.com");
      user_pref("mail.server.server_frankling.port", 993);
      user_pref("mail.server.server_frankling.socketType", 3);
      user_pref("mail.server.server_frankling.userName", "erik.frankling@frankling.se");
      user_pref("mail.server.server_frankling.authMethod", 10);
      user_pref("mail.server.server_frankling.login_at_startup", true);
      user_pref("mail.smtpserver.smtp_frankling.hostname", "smtp.office365.com");
      user_pref("mail.smtpserver.smtp_frankling.port", 587);
      user_pref("mail.smtpserver.smtp_frankling.try_ssl", 2);
      user_pref("mail.smtpserver.smtp_frankling.username", "erik.frankling@frankling.se");
      user_pref("mail.smtpserver.smtp_frankling.authMethod", 10);

      // ===== Gmail 1 — ef.pro454@gmail.com (OAuth2) =====
      user_pref("mail.account.account_gmail1.identities", "id_gmail1");
      user_pref("mail.account.account_gmail1.server", "server_gmail1");
      user_pref("mail.identity.id_gmail1.fullName", "Erik Frankling");
      user_pref("mail.identity.id_gmail1.useremail", "ef.pro454@gmail.com");
      user_pref("mail.identity.id_gmail1.valid", true);
      user_pref("mail.identity.id_gmail1.smtpServer", "smtp_gmail1");
      user_pref("mail.identity.id_gmail1.htmlSigText", "${sig}");
      user_pref("mail.identity.id_gmail1.sig_bottom", false);
      user_pref("mail.server.server_gmail1.type", "imap");
      user_pref("mail.server.server_gmail1.hostname", "imap.gmail.com");
      user_pref("mail.server.server_gmail1.port", 993);
      user_pref("mail.server.server_gmail1.socketType", 3);
      user_pref("mail.server.server_gmail1.userName", "ef.pro454@gmail.com");
      user_pref("mail.server.server_gmail1.authMethod", 10);
      user_pref("mail.server.server_gmail1.is_gmail", true);
      user_pref("mail.server.server_gmail1.login_at_startup", true);
      user_pref("mail.smtpserver.smtp_gmail1.hostname", "smtp.gmail.com");
      user_pref("mail.smtpserver.smtp_gmail1.port", 587);
      user_pref("mail.smtpserver.smtp_gmail1.try_ssl", 2);
      user_pref("mail.smtpserver.smtp_gmail1.username", "ef.pro454@gmail.com");
      user_pref("mail.smtpserver.smtp_gmail1.authMethod", 10);

      // ===== Gmail 2 — erik.frankling@gmail.com (OAuth2) =====
      user_pref("mail.account.account_gmail2.identities", "id_gmail2");
      user_pref("mail.account.account_gmail2.server", "server_gmail2");
      user_pref("mail.identity.id_gmail2.fullName", "Erik Frankling");
      user_pref("mail.identity.id_gmail2.useremail", "erik.frankling@gmail.com");
      user_pref("mail.identity.id_gmail2.valid", true);
      user_pref("mail.identity.id_gmail2.smtpServer", "smtp_gmail2");
      user_pref("mail.identity.id_gmail2.htmlSigText", "${sig}");
      user_pref("mail.identity.id_gmail2.sig_bottom", false);
      user_pref("mail.server.server_gmail2.type", "imap");
      user_pref("mail.server.server_gmail2.hostname", "imap.gmail.com");
      user_pref("mail.server.server_gmail2.port", 993);
      user_pref("mail.server.server_gmail2.socketType", 3);
      user_pref("mail.server.server_gmail2.userName", "erik.frankling@gmail.com");
      user_pref("mail.server.server_gmail2.authMethod", 10);
      user_pref("mail.server.server_gmail2.is_gmail", true);
      user_pref("mail.server.server_gmail2.login_at_startup", true);
      user_pref("mail.smtpserver.smtp_gmail2.hostname", "smtp.gmail.com");
      user_pref("mail.smtpserver.smtp_gmail2.port", 587);
      user_pref("mail.smtpserver.smtp_gmail2.try_ssl", 2);
      user_pref("mail.smtpserver.smtp_gmail2.username", "erik.frankling@gmail.com");
      user_pref("mail.smtpserver.smtp_gmail2.authMethod", 10);

      // ===== KTH — erikfran@kth.se (plain password via sops) =====
      user_pref("mail.account.account_kth.identities", "id_kth");
      user_pref("mail.account.account_kth.server", "server_kth");
      user_pref("mail.identity.id_kth.fullName", "Erik Frankling");
      user_pref("mail.identity.id_kth.useremail", "erikfran@kth.se");
      user_pref("mail.identity.id_kth.valid", true);
      user_pref("mail.identity.id_kth.smtpServer", "smtp_kth");
      user_pref("mail.identity.id_kth.htmlSigText", "${sig}");
      user_pref("mail.identity.id_kth.sig_bottom", false);
      user_pref("mail.server.server_kth.type", "imap");
      user_pref("mail.server.server_kth.hostname", "webmail.kth.se");
      user_pref("mail.server.server_kth.port", 993);
      user_pref("mail.server.server_kth.socketType", 3);
      user_pref("mail.server.server_kth.userName", "ug.kth.se\\erikfran");
      user_pref("mail.server.server_kth.authMethod", 3);
      user_pref("mail.server.server_kth.login_at_startup", true);
      user_pref("mail.smtpserver.smtp_kth.hostname", "smtp.kth.se");
      user_pref("mail.smtpserver.smtp_kth.port", 587);
      user_pref("mail.smtpserver.smtp_kth.try_ssl", 2);
      // smtp.kth.se only accepts the bare KTH username. The ug.kth.se\ form that
      // IMAP wants is rejected here with "535 authentication failed".
      user_pref("mail.smtpserver.smtp_kth.username", "erikfran");
      user_pref("mail.smtpserver.smtp_kth.authMethod", 3);

      // ===== Outlook.com — erik.frankling@outlook.com (OAuth2) =====
      user_pref("mail.account.account_outlook.identities", "id_outlook");
      user_pref("mail.account.account_outlook.server", "server_outlook");
      user_pref("mail.identity.id_outlook.fullName", "Erik Frankling");
      user_pref("mail.identity.id_outlook.useremail", "erik.frankling@outlook.com");
      user_pref("mail.identity.id_outlook.valid", true);
      user_pref("mail.identity.id_outlook.smtpServer", "smtp_outlook");
      user_pref("mail.identity.id_outlook.htmlSigText", "${sig}");
      user_pref("mail.identity.id_outlook.sig_bottom", false);
      user_pref("mail.server.server_outlook.type", "imap");
      user_pref("mail.server.server_outlook.hostname", "outlook.office365.com");
      user_pref("mail.server.server_outlook.port", 993);
      user_pref("mail.server.server_outlook.socketType", 3);
      user_pref("mail.server.server_outlook.userName", "erik.frankling@outlook.com");
      user_pref("mail.server.server_outlook.authMethod", 10);
      user_pref("mail.server.server_outlook.login_at_startup", true);
      user_pref("mail.smtpserver.smtp_outlook.hostname", "smtp.office365.com");
      user_pref("mail.smtpserver.smtp_outlook.port", 587);
      user_pref("mail.smtpserver.smtp_outlook.try_ssl", 2);
      user_pref("mail.smtpserver.smtp_outlook.username", "erik.frankling@outlook.com");
      user_pref("mail.smtpserver.smtp_outlook.authMethod", 10);
    '';

    # Agents read login codes and confirmation links from Thunderbird (the
    # mbox files under ImapMail/, see the browser-use skill). It used to be
    # started by hand from the launcher, so after a reboot nothing ran it and
    # the mail on disk went three weeks stale (2026-10-01 to 10-21).
    #
    # It is Erik's Thunderbird, on his profile, so it never goes near the agent
    # seat. Until 2026-10-26 it ran as class `agent-thunderbird` on `agent-park`
    # (AGENT-1), every window it opened was parked there too, and his own
    # `thunderbird` only re-activated that hidden window: he could not open
    # his mail. Now the main window starts on `special:mail`, a hidden scratch
    # workspace on his side that nothing toggles, and the `thunderbird`
    # launcher above (launcher entry, command line, mailto:) moves it to the
    # workspace he is on. Compose and message windows he opens follow his
    # focus. Closing the main window quits Thunderbird; the service starts a
    # fresh hidden one 10 s later. The first version (71c8f14c) opened it on
    # his screen and reopened it after every close.
    #
    # Not a headless IMAP sync (mbsync etc.): four of the five accounts are
    # OAuth2, Thunderbird holds the only working tokens, and a profile can be
    # open in one process only. The Executor mail apps cover Gmail and KTH.
    systemd.user.services.thunderbird = lib.mkIf config.thunderbird.autostart {
      Unit = {
        Description = "Erik's Thunderbird kept running hidden for mail sync (`thunderbird` shows it)";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${pkgs.thunderbird}/bin/thunderbird --name thunderbird";
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    # Main windows only: their initial title is "Mozilla Thunderbird". When
    # Thunderbird is already on Erik's screen, agent-desktop's watcher
    # (computer-use/desktop.py) brings any further main window to him.
    wayland.windowManager.hyprland.settings.windowrule = lib.mkIf config.thunderbird.autostart [
      "workspace special:mail silent, match:class ^(thunderbird)$, match:initial_title ^(Mozilla Thunderbird)$"
      "no_initial_focus on, match:class ^(thunderbird)$, match:initial_title ^(Mozilla Thunderbird)$"
    ];

    # Replaces the package's own launcher entry under the same name, so
    # mimeapps.list (mailto:, message/rfc822) resolves to the launcher too.
    xdg.desktopEntries.thunderbird = lib.mkIf config.thunderbird.autostart {
      name = "Thunderbird";
      genericName = "Mail";
      exec = "${launcher}/bin/thunderbird %U";
      icon = "thunderbird";
      categories = [
        "Network"
        "Email"
      ];
      mimeType = [
        "message/rfc822"
        "x-scheme-handler/mailto"
        "x-scheme-handler/mid"
        "text/calendar"
        "text/x-vcard"
      ];
      settings.StartupWMClass = "thunderbird";
    };
  };
}
