{ username, ... }:
{
  windows-vm = {
    enable = true;
    vmName = "windows";

    # Vendor:Device IDs for VFIO kernel driver binding (from lspci -nn)
    gpuVendorIds = [
      "1002:164e" # Raphael iGPU VGA
      "1002:1640" # Raphael iGPU Audio
      "1022:1649" # Raphael PSP/CCP (Platform Security Processor)
    ];

    # PCI addresses for VFIO binding in initrd (from lspci -D)
    gpuPciAddresses = "0000:0d:00.0 0000:0d:00.1 0000:0d:00.2";

    # PCI devices for VM passthrough (from lspci -nn, convert hex to decimal)
    # 0d:00.0 = bus=13, slot=0, function=0
    # 0d:00.1 = bus=13, slot=0, function=1
    # 0d:00.2 = bus=13, slot=0, function=2
    gpuDevices = [
      {
        bus = 13;
        slot = 0;
        function = 0;
      }
      {
        bus = 13;
        slot = 0;
        function = 1;
      }
      {
        bus = 13;
        slot = 0;
        function = 2; # PSP/CCP - may be required for iGPU
      }
    ];

    memoryGB = 16;
    diskSizeGB = 100;
    storagePath = "/home/${username}/vm";
    windowsISO = "/home/${username}/vm/Win11.iso";
    unattendISO = "/home/${username}/vm/unattend.iso";
    lookingGlass = {
      memoryMB = 64;
      hostPath = "/dev/shm/looking-glass";
      # hostPath = "/dev/kvmfr0"; # For kvmfr method, keep for later
    };

    cpuCores = 4;
    cpuThreads = 2;
  };
}
