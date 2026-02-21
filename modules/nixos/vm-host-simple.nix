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

  nixvirtLib = inputs.nixvirt.lib;

  # Path where you'll put the unattend.iso from schneegans
  unattendIso = "${vmStorage}/unattend.iso";

  # Base Windows template
  windowsBase = nixvirtLib.domain.templates.windows {
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
    install_vol = "${vmStorage}/Win11_25H2_EnglishInternational_x64.iso";
    virtio_net = true;
    virtio_drive = false;
    virtio_video = false;
    install_virtio = true;
  };

  # Add unattend ISO as extra CD-ROM
  windowsWithUnattend = windowsBase // {
    devices = windowsBase.devices // {
      disk = windowsBase.devices.disk ++ [
        {
          type = "file";
          device = "cdrom";
          driver = {
            name = "qemu";
            type = "raw";
          };
          source = {
            file = unattendIso;
          };
          target = {
            dev = "sde";
            bus = "sata";
          };
          readonly = true;
        }
      ];
    };
  };

in
{
  imports = [ inputs.nixvirt.nixosModules.default ];

  virtualisation.libvirt = {
    enable = true;
    swtpm.enable = true;

    connections."qemu:///system" = {
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
          active = true;
        }
      ];

      pools = [
        {
          definition = nixvirtLib.pool.writeXML {
            name = "default";
            uuid = "650c5bbb-eebd-4cea-8a2f-36e1a75a8683";
            type = "dir";
            target.path = vmStorage;
          };
          active = true;
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

      domains = [
        {
          definition = nixvirtLib.domain.writeXML windowsWithUnattend;
          active = null;
        }
      ];
    };
  };
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

  environment.variables = {
    LIBVIRT_DEFAULT_URI = "qemu:///system";
  };

  # Create storage directory
  systemd.tmpfiles.rules = [ "d ${vmStorage} 0755 root root -" ];

  # Auto-connect virt-manager
  programs.dconf.enable = true;
}
