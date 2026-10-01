{ ... }:

let
  # The system firefox.desktop, whose Exec ends in %U. The old default was
  # firefox-2.desktop, a stub Firefox wrote into ~/.local/share/applications
  # with a bare `Exec=firefox`: no field code, so every link opened from another
  # app (Thunderbird's OAuth sign-in included) dropped its URL and showed an
  # empty Firefox window.
  browser = "firefox.desktop";
  mail = "thunderbird.desktop";

  associations = {
    "x-scheme-handler/http" = browser;
    "x-scheme-handler/https" = browser;
    "x-scheme-handler/chrome" = browser;
    "text/html" = browser;
    "application/xhtml+xml" = browser;
    "application/x-extension-htm" = browser;
    "application/x-extension-html" = browser;
    "application/x-extension-shtml" = browser;
    "application/x-extension-xht" = browser;
    "application/x-extension-xhtml" = browser;
    "image/jpeg" = browser;

    "x-scheme-handler/mailto" = mail;
    "x-scheme-handler/mid" = mail;
    "message/rfc822" = mail;

    # Deep-link handlers the apps used to register themselves. mimeapps.list is
    # read-only now, so they have to be listed here. The t3code and claude-cli
    # desktop files are the ones those apps write to ~/.local/share/applications.
    "x-scheme-handler/claude" = "com.anthropic.Claude.desktop";
    "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    "x-scheme-handler/codex" = "codex-desktop.desktop";
    "x-scheme-handler/grokbot" = "grok-bot.desktop";
    "x-scheme-handler/sand" = "grok-bot.desktop";
    "x-scheme-handler/t3code" = "com.t3tools.T3Code.desktop";

    # MATLAB registered these in the legacy ~/.local/share/applications list,
    # which Home Manager now writes as well.
    "x-scheme-handler/mw-matlab" = "mw-matlab.desktop";
    "x-scheme-handler/mw-matlabconnector" = "mw-matlabconnector.desktop";
    "x-scheme-handler/mw-simulink" = "mw-simulink.desktop";
  };
in
{
  xdg.mimeApps = {
    enable = true;
    associations.added = associations;
    defaultApplications = associations;
  };

  # Replaces the hand-grown mimeapps.list files that apps had been appending to.
  xdg.configFile."mimeapps.list".force = true;
  xdg.dataFile."applications/mimeapps.list".force = true;
}
