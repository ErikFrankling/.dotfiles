{ lib, ... }:

{
  options.hyprland =
    let
      inherit (lib) mkOption types;
    in
    {
      monitors = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "DP-1";
            };
            width = mkOption {
              type = types.int;
              example = 1920;
            };
            height = mkOption {
              type = types.int;
              example = 1080;
            };
            refreshRate = mkOption {
              type = types.int;
              default = 60;
            };
            x = mkOption {
              type = types.int;
              default = 0;
            };
            y = mkOption {
              type = types.int;
              default = 0;
            };
            scale = mkOption {
              type = types.str;
              default = "1";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
            };
          };
        });
        default = [ ];
      };

      mouse = {
        scroll_factor = mkOption {
          type = types.str;
          default = "0.2";
        };
        sensitivity = mkOption {
          type = types.str;
          default = "-0.1";
        };
      };

      keyboards = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "DP-1";
            };
            width = mkOption {
              type = types.int;
              example = 1920;
            };
            height = mkOption {
              type = types.int;
              example = 1080;
            };
            refreshRate = mkOption {
              type = types.int;
              default = 60;
            };
            x = mkOption {
              type = types.int;
              default = 0;
            };
            y = mkOption {
              type = types.int;
              default = 0;
            };
            scale = mkOption {
              type = types.str;
              default = "1";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
            };
          };
        });
        default = [ ];
      };

      initWindows = mkOption {
        type = types.listOf (types.submodule {
          options = {
            exec = mkOption {
              type = types.str;
              example = "kitty tmux";
            };
            workspace = mkOption {
              type = types.int;
              example = 1;
            };
            monitor = mkOption {
              type = types.str;
              example = "DP-1";
            };
          };
        });
        default = [ ];
      };

      workspaces = mkOption {
        type = types.listOf (types.submodule {
          options = {
            ID = mkOption {
              type = types.int;
              example = 1;
            };
            monitor = mkOption {
              type = types.str;
              example = "DP-1";
            };
            default = mkOption {
              type = types.bool;
              default = false;
            };
          };
        });
        default = [ ];
      };
    };
}
