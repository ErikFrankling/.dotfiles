{ pkgs, ... }:

{
  fonts = {
    packages = with pkgs; [
      jetbrains-mono
      nerdfonts
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
      noto-fonts-color-emoji
    ];

    fontconfig = {
      enable = true;

      defaultFonts = {
        serif = [ "JetBrains Mono" ];
        sansSerif = [ "JetBrains Mono" ];
        monospace = [ "JetBrains Mono" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
