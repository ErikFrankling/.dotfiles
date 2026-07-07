{ pkgs, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = [ inputs.llm-agents.packages.${system}.omp ];

  home.file.".omp/agent/config.yml" = {
    force = true;
    source = ./config.yml;
  };
}
