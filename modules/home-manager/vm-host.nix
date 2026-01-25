# home-virt.nix - Home Manager config for virt-manager
#
# Add to your home-manager imports for auto-connect to qemu:///system
#
{ pkgs, ... }:

{
  # Auto-connect virt-manager to the system QEMU
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
}
