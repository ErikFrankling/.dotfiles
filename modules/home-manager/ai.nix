{
  pkgs,
  ...
}:

{
  imports = [
  ];

  home.packages = with pkgs; [
    claude-code
    code-cursor-fhs
    opencode
    codex
    kiro-fhs
    vscode-fhs
    windsurf
  ];
}
