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
        # the url should match the url when searching for the addon on like this https://addons.mozilla.org/en-US/firefox/addon/<addon-name>/

        # extracted from about:support:
        # AI Grammar Checker & Paraphraser – LanguageTool	extension	9.0.1	true	app-profile	languagetool-webextension@languagetool.org
        # DeArrow	extension	2.1.10	true	app-profile	deArrow@ajay.app
        # React Developer Tools	extension	6.1.1	true	app-profile	@react-devtools
        # Read Aloud: A Text to Speech Voice Reader	extension	1.80.0	true	app-profile	{ddc62400-f22d-4dd3-8b4a-05837de53c2e}
        # Return YouTube Dislike	extension	3.0.0.18	true	app-profile	{762f9885-5a13-4abd-9c77-433dcd38b8fd}
        # SponsorBlock for YouTube - Skip Sponsorships	extension	6.0	true	app-profile	sponsorBlocker@ajay.app
        # To Google Translate	extension	4.2.0	true	app-profile	jid1-93WyvpgvxzGATw@jetpack
        # Unhook - Remove YouTube Recommended & Shorts	extension	1.6.7	true	app-profile	myallychou@gmail.com
        # User-Agent Switcher and Manager	extension	0.6.5.1	true	app-profile	{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}
        # Youtube-shorts block	extension	1.5.3	true	app-profile	{34daeb50-c2d2-4f14-886a-7160b24d66a4}
        # Block Site	extension	0.5.6	false	app-profile	{54e2eb33-18eb-46ad-a4e4-1329c29f6e17}
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
          # LastPass:
          "support@lastpass.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/lastpass-password-manager/latest.xpi";
            installation_mode = "force_installed";
          };
          # LanguageTool:
          "languagetool-webextension@languagetool.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/languagetool/latest.xpi";
            installation_mode = "force_installed";
          };
          # DeArrow:
          "deArrow@ajay.app" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/dearrow/latest.xpi";
            installation_mode = "force_installed";
          };
          # React Developer Tools:
          "@react-devtools" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/react-devtools/latest.xpi";
            installation_mode = "force_installed";
          };
          # Read Aloud:
          "{ddc62400-f22d-4dd3-8b4a-05837de53c2e}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/read-aloud/latest.xpi";
            installation_mode = "force_installed";
          };
          # Return YouTube Dislike:
          "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/return-youtube-dislikes/latest.xpi";
            installation_mode = "force_installed";
          };
          # SponsorBlock:
          "sponsorBlocker@ajay.app" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
            installation_mode = "force_installed";
          };
          # To Google Translate:
          "jid1-93WyvpgvxzGATw@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/to-google-translate/latest.xpi";
            installation_mode = "force_installed";
          };
          # Unhook:
          "myallychou@gmail.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-recommended-videos/latest.xpi";
            installation_mode = "force_installed";
          };
          # User-Agent Switcher:
          "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/user-agent-string-switcher/latest.xpi";
            installation_mode = "force_installed";
          };
          # Youtube-shorts block:
          "{34daeb50-c2d2-4f14-886a-7160b24d66a4}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-shorts-block/latest.xpi";
            installation_mode = "force_installed";
          };
          # Block Site:
          "{54e2eb33-18eb-46ad-a4e4-1329c29f6e17}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/block-website/latest.xpi";
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
          # "pdfjs.forcePageColors" = lock-value true;
          # "pdfjs.pageColorsBackground" = lock-value "#202020";
          # "pdfjs.pageColorsForeground" = lock-value "#d1d1d1";
        };
      };
    };
  };
}
