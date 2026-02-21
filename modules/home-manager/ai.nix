{
  pkgs,
  otherPkgs,
  lib,
  inputs,
  ...
}:

{
  imports = [
  ];

  nixpkgs.config.allowBroken = true;

  home.packages = with pkgs; [
    claude-code
    # code-cursor-fhs
    # opencode
    # codex
    # kiro-fhs
    # vscode-fhs
    # windsurf
    lmstudio
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
  ];

  programs.opencode = {
    enable = true;
    settings = {
      permission = {
        edit = "allow";
        bash = "allow";
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
