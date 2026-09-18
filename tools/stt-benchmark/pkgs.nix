let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  pinned = lock.nodes.nixpkgs.locked;
in
import (builtins.fetchTarball {
  url = "https://github.com/NixOS/nixpkgs/archive/${pinned.rev}.tar.gz";
  sha256 = pinned.narHash;
}) { system = "x86_64-linux"; }
