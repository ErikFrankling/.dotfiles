{ pkgs, ... }:

{
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;
    
    ".config/fish/" = {
      source = ../../.config/fish;
      recursive = true;
    };

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  programs.fish = {
    enable = true;

    plugins = with pkgs; [
      # https://github.com/jethrokuan/z
      {
        name = "z";
        src = fetchFromGitHub {
          owner = "jethrokuan";
          repo = "z";
          rev = "ddeb28a7b6a1f0ec6dae40c636e5ca4908ad160a";
          sha256 = "0c5i7sdrsp0q3vbziqzdyqn4fmp235ax4mn4zslrswvn8g3fvdyh";
        };
      }

      # https://github.com/oh-my-fish/theme-bobthefish
      # {
      #   name = "bobthefish";
      #   src = fetchFromGitHub {
      #     owner = "oh-my-fish";
      #     repo = "theme-bobthefish";
      #     rev= "a2ad38aa051aaed25ae3bd6129986e7f27d42d7b";
      #     sha256 = "1fssb5bqd2d7856gsylf93d28n3rw4rlqkhbg120j5ng27c7v7lq";
      #   };
      # }
      {
        name = "bobthefish";
        src = fishPlugins.bobthefish;
      }
    ];
  };

  # xdg.configFile."fish/conf.d/plugin-bobthefish.fish".text = mkAfter ''
  # for f in $plugin_dir/*.fish
  #   source $f
  # end
  # '';
}
