{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.windows-vm = {
    enable = mkEnableOption "Windows VM with GPU passthrough and full guest integration";

    # Basic VM settings
    vmName = mkOption {
      type = types.str;
      default = "windows";
      description = "Name of the VM";
    };

    vmUuid = mkOption {
      type = types.str;
      default = "f4a3c5e7-2b8d-4f1a-9c6e-0d7b3a2e1f5c";
      description = "UUID of the VM (generate a new one with uuidgen)";
    };

    # Hardware resources
    memoryGB = mkOption {
      type = types.int;
      default = 16;
      description = "VM memory in GB";
    };

    cpuCores = mkOption {
      type = types.int;
      default = 4;
      description = "Number of CPU cores per socket";
    };

    cpuThreads = mkOption {
      type = types.int;
      default = 1;
      description = "Number of threads per core (SMT). Set to 1 to disable SMT, 2 to enable";
    };

    cpuSockets = mkOption {
      type = types.int;
      default = 1;
      description = "Number of CPU sockets";
    };

    diskSizeGB = mkOption {
      type = types.int;
      default = 100;
      description = "VM disk size in GB";
    };

    # Storage paths
    storagePath = mkOption {
      type = types.path;
      description = "Path for VM storage (will be created if it doesn't exist)";
    };

    windowsISO = mkOption {
      type = types.path;
      description = "Path to Windows ISO file";
    };

    unattendISO = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to unattend ISO file for automated installation";
    };

    virtioDriversISO = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to virtio-win drivers ISO (auto-downloaded if null)";
    };

    # GPU Passthrough settings
    gpuVendorIds = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "1002:164e" "1002:1640" ];
      description = "GPU vendor:device IDs for VFIO driver binding (from lspci -nn)";
    };

    gpuPciAddresses = mkOption {
      type = types.str;
      default = "";
      example = "0000:0d:00.0 0000:0d:00.1";
      description = "Space-separated PCI addresses for VFIO binding (from lspci -D)";
    };

    gpuDevices = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            bus = mkOption { type = types.int; description = "PCI bus (decimal)"; };
            slot = mkOption { type = types.int; description = "PCI slot (decimal)"; };
            function = mkOption { type = types.int; description = "PCI function (decimal)"; };
          };
        }
      );
      default = [ ];
      description = "GPU PCI devices for passthrough (bus/slot/function as decimal integers from lspci)";
    };

    # Looking Glass settings
    lookingGlass = {
      enable = mkEnableOption "Looking Glass shared memory for GPU framebuffer capture";
      
      memoryMB = mkOption {
        type = types.int;
        default = 64;
        description = "Looking Glass shared memory in MB (use calculator at https://looking-glass.io/docs/stable/install/#calculating-memory)";
      };

      hostPath = mkOption {
        type = types.str;
        default = "/dev/shm/looking-glass";
        description = "Path to Looking Glass shared memory device";
      };
    };

    # Guest tools and integration
    guestTools = {
      spice = mkEnableOption "SPICE guest tools for clipboard and improved graphics";
      
      virtiofs = mkEnableOption "Virtio-9p file sharing between host and guest";
      
      sharedDirectories = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              hostPath = mkOption { type = types.path; description = "Path on host to share"; };
              mountTag = mkOption { type = types.str; description = "Mount tag in VM"; };
              readOnly = mkOption { type = types.bool; default = false; description = "Read-only access"; };
            };
          }
        );
        default = [ ];
        description = "Directories to share with VM via virtio-9p";
      };
    };

    # Network settings
    networkBridge = mkOption {
      type = types.str;
      default = "virbr0";
      description = "Network bridge to attach VM to";
    };

    # Installation settings
    install = {
      useVirtioDisk = mkOption {
        type = types.bool;
        default = true;
        description = "Use virtio for disk (faster, requires drivers during install). Set to false for SATA during installation.";
      };

      injectVirtioDrivers = mkOption {
        type = types.bool;
        default = true;
        description = "Inject virtio drivers into Windows PE for unattended install (fixes 'disk not found' errors)";
      };
    };

    # Advanced settings
    iommuType = mkOption {
      type = types.enum [ "amd" "intel" ];
      default = "amd";
      description = "IOMMU type for your CPU";
    };

    ovmfCodePath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to OVMF_CODE.fd (auto-detected if null)";
    };

    ovmfVarsPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to OVMF_VARS.fd (auto-detected if null)";
    };
  };
}
