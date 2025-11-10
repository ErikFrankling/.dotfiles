{
  pkgs,
  otherPkgs,
  ...
}:

{
  imports = [
  ];

  nixpkgs.config.allowBroken = true;

  home.packages = with pkgs; [
    claude-code
    code-cursor-fhs
    # opencode
    codex
    kiro-fhs
    vscode-fhs
    windsurf
    lmstudio
    otherPkgs.pkgsStable.local-ai
  ];

  programs.opencode = {
    enable = true;
    settings = {
      model = "ollama/gpt-oss:20b";
      provider = {
        ollama = {
          npm = "@ai-sdk/openai-compatible";
          name = "Ollama";
          options = {
            baseURL = "http://localhost:11434/v1";
          };
          models = {
            "gpt-oss:20b" = {
              name = "OpenAI GPT OSS 20B";
            };
          };
        };
      };
    };
  };
}
