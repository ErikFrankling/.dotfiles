{ pkgs, config, ... }:
let
  prompt = pkgs.writeScriptBin "prompt" (builtins.readFile ./prompt.sh);
in
{
  home.packages = with pkgs; [ prompt ];
}
