let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  # Follow the flake's own nixpkgs, not whichever node happens to be called
  # "nixpkgs" (that was batmon's old pin). The speech workers load the system
  # Vulkan driver from /run/opengl-driver, so their glibc must match the system.
  pinned = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
in
import (builtins.fetchTarball {
  url = "https://github.com/NixOS/nixpkgs/archive/${pinned.rev}.tar.gz";
  sha256 = pinned.narHash;
}) { system = "x86_64-linux"; }
