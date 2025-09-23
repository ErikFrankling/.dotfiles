# From: https://discourse.nixos.org/t/declare-firefox-extensions-and-settings/36265

{ config, pkgs, ... }:

let
  lock-false = {
    Value = false;
    Status = "locked";
  };
  lock-true = {
    Value = true;
    Status = "locked";
  };
  lock-value = v: {
    Value = v;
    Status = "locked";
  };
in
{
  programs = {
    firefox = {
      enable = true;
      languagePacks = [
        "en-US"
      ];

      # ---- POLICIES ----
      # Check about:policies#documentation for options.
      policies = {
        # DisableTelemetry = true;
        # DisableFirefoxStudies = true;
        # EnableTrackingProtection = {
        #   Value = true;
        #   Locked = true;
        #   Cryptomining = true;
        #   Fingerprinting = true;
        # };
        # DisablePocket = true;
        # DisableFirefoxAccounts = true;
        # DisableAccounts = true;
        # DisableFirefoxScreenshots = true;
        # OverrideFirstRunPage = "";
        # OverridePostUpdatePage = "";
        # DontCheckDefaultBrowser = true;
        # DisplayBookmarksToolbar = "never"; # alternatives: "always" or "newtab"
        # DisplayMenuBar = "default-off"; # alternatives: "always", "never" or "default-on"
        # SearchBar = "unified"; # alternative: "separate"

        # ---- EXTENSIONS ----
        # Check about:support for extension/add-on ID strings.
        # Valid strings for installation_mode are "allowed", "blocked",
        # "force_installed" and "normal_installed".
        ExtensionSettings = {
          # "*".installation_mode = "blocked"; # blocks all addons except the ones specified below
          # uBlock Origin:
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };
          # Privacy Badger:
          "jid1-MnnxcxisBPnSXQ@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi";
            installation_mode = "force_installed";
          };
          # 1Password:
          # "{d634138d-c276-4fc8-924b-40a0ea21d284}" = {
          #   install_url = "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi";
          #   installation_mode = "force_installed";
          # };
        };

        # ---- PREFERENCES ----
        # Check about:config for options.
        Preferences = {
          # "browser.contentblocking.category" = {
          #   Value = "strict";
          #   Status = "locked";
          # };
          # "extensions.pocket.enabled" = lock-false;
          # "extensions.screenshots.disabled" = lock-true;
          # "browser.topsites.contile.enabled" = lock-false;
          # "browser.formfill.enable" = lock-false;
          # "browser.search.suggest.enabled" = lock-false;
          # "browser.search.suggest.enabled.private" = lock-false;
          # "browser.urlbar.suggest.searches" = lock-false;
          # "browser.urlbar.showSearchSuggestionsFirst" = lock-false;
          # "browser.newtabpage.activity-stream.feeds.section.topstories" = lock-false;
          # "browser.newtabpage.activity-stream.feeds.snippets" = lock-false;
          # "browser.newtabpage.activity-stream.section.highlights.includePocket" = lock-false;
          # "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = lock-false;
          # "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = lock-false;
          # "browser.newtabpage.activity-stream.section.highlights.includeVisited" = lock-false;
          # "browser.newtabpage.activity-stream.showSponsored" = lock-false;
          # "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
          # "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;

          "browser.tabs.min_inactive_duration_before_unload" = lock-value 120000; # 2 min. default is 10 min

          # turn on tab unloading when the system is low on memory configured by the two settings below
          "browser.tabs.unloadOnLowMemory" = lock-true;
          # the amount of system memory (in MB) that is the threshold for Firefox to start unloading tabs
          "browser.low_commit_space_threshold_mb" = lock-value 4096; # default is 200mb
          # the procentage of memory (of total system memory) that is the threshold for Firefox to start unloading tabs. both thresholds most be exceeded
          "browser.low_commit_space_threshold_percent" = lock-value 20; # default is 5%

          # controls the number of cached page viewers in memory for each tab's session history
          "browser.sessionhistory.max_total_viewers" = lock-value 4; # default is -1 (unlimited)

          "browser.cache.memory.enable" = lock-true; # default is true
          # controls the maximum amount of RAM (in kilobytes) allocated for caching decoded images, messages, and UI elements
          # "browser.cache.memory.capacity" = lock-value 65536; # default is -1 (automatic based on system memory)
          "browser.cache.disk.enable" = lock-false; # default is true

          # "dom.ipc.processCount.webIsolated" = lock-value 4; # Lower process count if you wish

          # from: https://www.reddit.com/r/firefox/comments/17hlkhp/comment/k8db8s5/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
          "pdfjs.forcePageColors" = lock-value true;
          "pdfjs.pageColorsBackground" = lock-value "#202020";
          "pdfjs.pageColorsForeground" = lock-value "#d1d1d1";
        };
      };
    };
  };
}
