let
  flake = builtins.getFlake (toString ../..);
  pkgs = flake.nixosConfigurations.pc.pkgs;
in
pkgs.mkShell {
  packages = with pkgs; [
    python3
    curl
    ffmpeg
    llama-cpp-vulkan
  ];
}
