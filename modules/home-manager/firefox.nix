{ ... }:

{
  programs.firefox.enable = true;

  # Force-installed through enterprise policy rather than left to a click, so a
  # reinstall or a new machine comes back with it already there. Same mechanism
  # zen.nix uses for its extension list.
  programs.firefox.policies.ExtensionSettings = {
    # Reports the focused tab to the time agent on this machine. It is the only
    # way to get a domain at all: no window title carries one, and the
    # screenshot cannot be relied on either -- Zen hides its toolbar, and a
    # downscaled screenshot is marginal even where the URL bar is visible.
    #
    # The extension posts to 127.0.0.1:5600 and nowhere else. The agent keeps
    # the host and discards the rest of the URL, so a path never leaves the
    # machine.
    "{ef87d84c-2127-493f-b952-5b4e744245bc}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/aw-watcher-web/latest.xpi";
      installation_mode = "force_installed";
    };
  };
}
