# vm-host.nix - Declarative Windows VM with NixVirt
#
# Prerequisites:
# 1. Add NixVirt to flake inputs (see flake-example.nix)
# 2. Pass 'nixvirt' via specialArgs
# 3. Include NixVirt.nixosModules.default in your modules list
#
{
  pkgs,
  lib,
  config,
  username,
  inputs,
  ...
}:

let
  # Storage location for VM disks
  vmStorage = "/home/${username}/vm/";

  # Helper to access NixVirt lib
  nixvirtLib = inputs.nixvirt.lib;

in
{
  # ==========================================
  # NIXVIRT CONFIGURATION
  # ==========================================
  imports = [ inputs.nixvirt.nixosModules.default ];

  virtualisation.libvirt = {
    enable = true;
    swtpm.enable = true; # Required for Windows 11 TPM

    connections."qemu:///system" = {

      # -------------------------------------
      # NETWORK (replaces manual virsh commands)
      # -------------------------------------
      networks = [
        {
          definition = nixvirtLib.network.writeXML {
            name = "default";
            uuid = "c4acfd00-4597-41c7-a48e-e2302234fa89";
            forward.mode = "nat";
            bridge.name = "virbr0";
            ip = {
              address = "192.168.122.1";
              netmask = "255.255.255.0";
              dhcp.range = {
                start = "192.168.122.2";
                end = "192.168.122.254";
              };
            };
          };
          active = true; # Auto-start network
        }
      ];

      # -------------------------------------
      # STORAGE POOL
      # -------------------------------------
      pools = [
        {
          definition = nixvirtLib.pool.writeXML {
            name = "default";
            uuid = "650c5bbb-eebd-4cea-8a2f-36e1a75a8683";
            type = "dir";
            target.path = vmStorage;
          };
          active = true;

          # Pre-create the Windows disk
          volumes = [
            {
              definition = nixvirtLib.volume.writeXML {
                name = "windows.qcow2";
                capacity = {
                  count = 100;
                  unit = "GiB";
                };
                target.format.type = "qcow2";
              };
            }
          ];
        }
      ];

      # -------------------------------------
      # WINDOWS VM
      # -------------------------------------
      domains = [
        {
          definition = nixvirtLib.domain.writeXML (
            nixvirtLib.domain.templates.windows {
              name = "windows";
              uuid = "f4a3c5e7-2b8d-4f1a-9c6e-0d7b3a2e1f5c";
              memory = {
                count = 20;
                unit = "GiB";
              };

              storage_vol = {
                pool = "default";
                volume = "windows.qcow2";
              };
              nvram_path = "${vmStorage}/windows.nvram";

              # Set this to your Windows ISO path after downloading
              install_vol = "${vmStorage}/Win11_25H2_EnglishInternational_x64.iso";
              # install_vol = null;

              # VirtIO for better performance
              virtio_net = true;
              virtio_drive = true;
              virtio_video = false;
              install_virtio = true; # Adds VirtIO driver ISO automatically
            }
          );
          active = null; # Don't auto-start
        }
      ];
    };
  };

  # ==========================================
  # SUPPORTING CONFIG
  # ==========================================

  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  networking.firewall.trustedInterfaces = [ "virbr0" ];

  users.users.${username}.extraGroups = [
    "libvirtd"
    "kvm"
  ];

  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice-gtk
  ];

  # Create storage directory
  systemd.tmpfiles.rules = [ "d ${vmStorage} 0755 root root -" ];

  # Auto-connect virt-manager
  programs.dconf.enable = true;
}
