{
  config,
  lib,
  pkgs,
  username,
  inputs,
  ...
}:

let
  cfg = config.windows-vm;
  nixvirtLib = inputs.nixvirt.lib;

  # Simple conversion of GPU devices to hostdev format
  # Each device needs: type, managed, source.address with domain/bus/slot/function
  gpuHostdevs = map (dev: 
    let
      isVga = dev.function == 0;
    in
    {
      type = "pci";
      managed = true;
      source.address = {
        domain = 0;
        bus = dev.bus;
        slot = dev.slot;
        function = dev.function;
      };
      # Enable ROM BAR and VBIOS for GPU - required for AMD GPU passthrough to avoid error 43
      # Only enable on the VGA function
      rom = lib.optionalAttrs isVga {
        bar = true;
        # Use extracted VBIOS for Ryzen 7000 iGPU to fix Error 43
        file = "${cfg.storagePath}/vbios_7800x3d.bin";
      };
    } // lib.optionalAttrs isVga {
      # Add x-vga attribute for primary GPU passthrough
      # This tells QEMU this is the primary VGA device
      "x-vga" = "on";
    }
  ) cfg.gpuDevices;

  # Base Windows VM from NixVirt template
  windowsBase = nixvirtLib.domain.templates.windows {
    name = cfg.vmName;
    uuid = cfg.vmUuid;
    memory = {
      count = cfg.memoryGB;
      unit = "GiB";
    };
    storage_vol = {
      pool = "default";
      volume = "${cfg.vmName}.qcow2";
    };
    nvram_path = "${cfg.storagePath}/${cfg.vmName}.nvram";
    install_vol = cfg.windowsISO;
    virtio_net = true;
    # virtio_drive = true;
    virtio_drive = false;
    virtio_video = false;
    install_virtio = true;
    kvm.hidden.state = true;
    ioapic.driver = "kvm";
    cpu = {
      mode = "host-passthrough";
      check = "none";
      migratable = "on";
      feature = [
        {
          policy = "disable";
          name = "hypervisor";
        }
        {
          policy = "disable";
          name = "hv-time";
        }
      ];
      # Add CPU topology to help Windows properly detect CPU structure
      # This can improve stability and prevent driver issues
      topology = {
        sockets = cfg.cpuSockets;
        cores = cfg.cpuCores;
        threads = cfg.cpuThreads;
      };
    };
  };

  # Extended VM with GPU passthrough and Looking Glass
  windowsFull = windowsBase // {
    devices = windowsBase.devices // {
      # Add unattend ISO if specified
      disk =
        windowsBase.devices.disk
        ++ lib.optional (cfg.unattendISO != null) {
          type = "file";
          device = "cdrom";
          driver = {
            name = "qemu";
            type = "raw";
          };
          source.file = cfg.unattendISO;
          target = {
            dev = "sde";
            bus = "sata";
          };
          readonly = true;
        };

      # Add GPU passthrough devices
      hostdev = gpuHostdevs;

      # Remove video device from base template - use AMD GPU passthrough only
      # The // operator merges, so we need to explicitly override
      video = {
        model = {
          type = "none";
        };
      };

    # QEMU command line to disable default video
    qemu = {
      commandline = {
        arg = [
          {
            value = "-vga";
          }
          {
            value = "none";
          }
        ];
      };
    };

      # Looking Glass shared memory
      shmem = {
        name = "looking-glass";
        model.type = "ivshmem-plain";
        size = {
          unit = "M";
          count = cfg.lookingGlass.memoryMB;
        };
        source = {
          path = cfg.lookingGlass.hostPath;
        };
      };
    };

    # Performance optimizations and AMD GPU hiding
    # Use minimal features to avoid Hyper-V detection in AMD drivers
    features = {
      acpi = { };
      apic = { };
      kvm = {
        hidden = {
          state = true;
        };
      };
      # Hyper-V settings with vendor ID spoofing (kept for later testing)
      # hyperv = windowsBase.features.hyperv // {
      #   vendor_id = {
      #     state = true;
      #     value = "randomid";
      #   };
      #   relaxed = { state = true; };
      #   vapic = { state = true; };
      #   spinlocks = { state = true; retries = 8191; };
      #   stimer = { state = false; };
      # };
    };

    # Disable Hyper-V clock to prevent hv-time exposure
    clock = {
      offset = "localtime";
      timer = [
        {
          name = "rtc";
          tickpolicy = "catchup";
        }
        {
          name = "pit";
          tickpolicy = "delay";
        }
        {
          name = "hpet";
          present = false;
        }
        {
          name = "hypervclock";
          present = false;
        }
      ];
    };

    # Remove memballoon for VFIO performance
    memballoon = {
      model = "none";
    };

    # QEMU command line arguments for GPU passthrough
    # Add x-vga flag to mark GPU as primary VGA device
    qemu = {
      commandline = {
        arg = [
          {
            value = "-set";
          }
          {
            value = "device.hostdev0.x-vga=on";
          }
        ];
      };
    };
  };

in
{
  imports = [
    ./options.nix
    inputs.nixvirt.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    # VFIO/IOMMU kernel configuration
    boot.kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "initcall_blacklist=sysfb_init"
      "vfio-pci.ids=${lib.concatStringsSep "," cfg.gpuVendorIds}"
      # "video=efifb:off" # Disable EFI framebuffer to prevent GPU conflicts - BROKEN: breaks primary GPU for Wayland
      "pcie_aspm=off" # Disable PCIe ASPM for better GPU passthrough stability
      "amdgpu.exp_hw_support=1" # Enable experimental hardware support
      "kvm.ignore_msrs=1" # Ignore unhandled MSRs
      "kvm.report_ignored_msrs=0" # Don't spam logs with ignored MSRs
      # "pci=realloc" # Reallocate PCI resources to fix BAR allocation issues - BROKEN: causes Wayland crash
    ];

    # Kernel modules for VFIO, Looking Glass, and AMD GPU reset bug fix
    boot.extraModulePackages = [ config.boot.kernelPackages.vendor-reset ];
    boot.kernelModules = [ "vendor-reset" ];

    boot.initrd.kernelModules = [
      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"
    ];

    boot.initrd.preDeviceCommands = ''
      DEVS="${cfg.gpuPciAddresses}"
      for DEV in $DEVS; do
        echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
      done
      modprobe -i vfio-pci
    '';

    boot.extraModprobeConfig = ''
      softdep amdgpu pre: vfio-pci
      # options kvmfr static_size_mb=${toString cfg.lookingGlass.memoryMB}
    '';

    # Permissions for kvmfr device
    # services.udev.extraRules = ''
    #   KERNEL=="kvmfr0", GROUP="libvirtd", MODE="0660"
    # '';

    # Libvirt configuration
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
              target.path = cfg.storagePath;
            };
            active = true;
            volumes = [
              {
                definition = nixvirtLib.volume.writeXML {
                  name = "${cfg.vmName}.qcow2";
                  capacity = {
                    count = cfg.diskSizeGB;
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
            definition = nixvirtLib.domain.writeXML windowsFull;
            active = false;
          }
        ];
      };
    };

    # System packages
    environment.systemPackages = with pkgs; [
      virt-manager
      virt-viewer
      looking-glass-client
    ];

    # User groups
    users.users.${username}.extraGroups = [
      "libvirtd"
      "kvm"
    ];

    # Looking Glass permissions and storage directory
    systemd.tmpfiles.rules = [
      "f /dev/shm/looking-glass 0660 ${username} libvirtd -"
      "d ${cfg.storagePath} 0755 ${username} users -"
    ];

    # Firewall
    networking.firewall.trustedInterfaces = [ "virbr0" ];

    # Programs
    programs.dconf.enable = true;
    programs.virt-manager.enable = true;

    environment.variables = {
      LIBVIRT_DEFAULT_URI = "qemu:///system";
    };
  };
}
