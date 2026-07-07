{
  pkgs,
  otherPkgs,
  lib,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  codexCli = inputs.llm-agents.packages.${system}.codex;
  codexDesktop = inputs.codex-desktop-linux.packages.${system}.codex-desktop;
  codexFirefoxShim = pkgs.writeShellScriptBin "firefox" ''
    unset LD_LIBRARY_PATH
    exec /run/current-system/sw/bin/firefox "$@"
  '';
  codexDesktopCleanExternalOpen = pkgs.symlinkJoin {
    name = "${codexDesktop.name}-clean-external-open";
    paths = [ codexDesktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f "$out/bin/codex-desktop"
      makeWrapper "${codexDesktop}/opt/codex-desktop/start.sh" "$out/bin/codex-desktop" \
        --prefix PATH : "${
          pkgs.lib.makeBinPath (
            with pkgs;
            [
              bash
              coreutils
              curl
              findutils
              gawk
              gnugrep
              gnused
              nodejs
              procps
              python3
              systemd
              xdg-utils
            ]
          )
        }" \
        --prefix PATH : "/run/current-system/sw/bin" \
        --prefix PATH : "/etc/profiles/per-user/\$(whoami)/bin" \
        --prefix PATH : "${codexFirefoxShim}/bin"

      desktopFile="$out/share/applications/codex-desktop.desktop"
      if [ -e "$desktopFile" ]; then
        target="$(readlink -f "$desktopFile")"
        rm -f "$desktopFile"
        substitute "$target" "$desktopFile" \
          --replace-fail "${codexDesktop}/bin/codex-desktop" "$out/bin/codex-desktop"
      fi
    '';
    meta = codexDesktop.meta or { };
  };
in
{
  imports = [
    inputs.codex-desktop-linux.homeManagerModules.default
    ./omp
  ];

  nixpkgs.config.allowBroken = true;

  # home.file.".codex/config.toml" = {
  #   force = true;
  #   text = ''
  #     approval_policy = "never"
  #     approvals_reviewer = "user"
  #     hide_agent_reasoning = false
  #     model_reasoning_summary = "detailed"
  #     sandbox_mode = "danger-full-access"
  #     show_raw_agent_reasoning = true
  #
  #     [notice]
  #     hide_full_access_warning = true
  #
  #     [projects."/home/erikf/.dotfiles"]
  #     trust_level = "trusted"
  #
  #     [marketplaces.neptune-dxp-marketplace]
  #     source_type = "local"
  #     source = "/home/erikf/projects/work/claude-code-plugin"
  #
  #     [plugins."neptune-dxp@neptune-dxp-marketplace"]
  #     enabled = true
  #
  #     [mcp_servers.neptune-dxp]
  #     url = "http://localhost:8080/mcp"
  #   '';
  # };

  home.packages = with pkgs; [
    # claude-code
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    # code-cursor-fhs
    # opencode
    # codex
    # otherPkgs.pkgsMaster.codex
    codexCli
    inputs.t3code-nix.packages.${system}.t3code
    inputs.llm-agents.packages.${system}.grok
    # kiro-fhs
    # vscode-fhs
    # windsurf
    inputs.opencode-desktop-nix.packages.${system}.default
    lmstudio
    # inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi # Disabled - npm registry 500 blocking rebuild
  ];

  home.file.".config/codex-desktop/electron-flags.conf" = {
    force = true;
    text = ''
      # Codex Desktop Linux launch flags.
      # Link opening is handled by the clean external opener wrapper below.
    '';
  };

  programs.codexDesktopLinux = {
    enable = true;
    package = codexDesktopCleanExternalOpen;
    cliPackage = codexCli;

    remoteControl = {
      enable = true;
      package = codexCli;
    };
  };

  programs.opencode = {
    enable = true;

    web = {
      enable = true;
      extraArgs = [
        "--hostname"
        "0.0.0.0"
        "--port"
        "4096"
        "--mdns"
      ];
    };

    settings = {
      permission = "allow";

      mcp = {
        neptune-dxp = {
          type = "remote";
          url = "https://p9eval.erikfrankling.duckdns.org/mcp";
          enabled = true;
          timeout = 30000;
        };
      };

      skills = {
        paths = [
          "/home/erikf/projects/work/claude-code-plugin/skills"
        ];
      };

      provider = {
        llama-swap = {
          npm = "@ai-sdk/openai-compatible";
          name = "Llama Swap (local)";
          options = {
            baseURL = "http://192.168.50.232:8000/v1";
          };
          models = {
            "qwen3.5-27b" = {
              name = "Qwen3.5-27B IQ4_NL (local)";
            };
            "qwen3.5-opus" = {
              name = "Qwen3.5-27B Opus (local)";
            };
            "qwen3.5-a3b" = {
              name = "Qwen3.5-35B-A3B MoE (local)";
            };
          };
        };
      };

      # model = "ollama/gpt-oss:20b";
      # model = "localai/qwen3-30b-a3b-thinking-2507"; # default model shown in UI
      # provider = {
      #   ollama = {
      #     npm = "@ai-sdk/openai-compatible";
      #     name = "Ollama";
      #     options = {
      #       baseURL = "http://localhost:11434/v1";
      #     };
      #     models = {
      #       "gpt-oss:20b" = {
      #         name = "OpenAI GPT OSS 20B";
      #       };
      #     };
      #   };
      # };
      # provider = {
      #   localai = {
      #     npm = "@ai-sdk/openai-compatible";
      #     name = "LocalAI (self-hosted)";
      #     options = {
      #       baseURL = "http://localhost:8000/v1"; # LocalAI OpenAI-compatible API
      #     };
      #     models = {
      #       "starcoder2-15b-fast" = {
      #         name = "StarCoder2-15B Fast (local)";
      #       };
      #       "qwen3-30b-a3b" = {
      #         name = "Qwen3-30B-A3B (local)";
      #       };
      #       "qwen3-30b-a3b-thinking-2507" = {
      #         name = "Qwen3-30B-A3B-Thinking-2507";
      #       };
      #       "qwen3-coder-30B-a3b" = {
      #         name = "Qwen3-Coder-30B-A3B";
      #       };
      #     };
      #   };
      # };

    };
  };
}
