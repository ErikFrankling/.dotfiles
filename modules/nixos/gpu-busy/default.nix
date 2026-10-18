# How busy the GPU really is, for the shell's gpu ring.
#
# The udev rule in hosts/pc/configuration.nix pins the 7900 XT at profile_peak,
# and in that mode amdgpu's utilisation counter reads 100 all the time:
# `gpu_busy_percent`, the firmware's `average_gfx_activity` in gpu_metrics, and
# nvtop's device total (which reads the same thing) all say 100 on an idle
# desktop. The per-process numbers nvtop shows are right, because they come from
# DRM fdinfo — engine time the kernel has billed to each client — and this
# service adds those up per card. See gpu-busy.py.
#
# It writes /run/gpu-busy/<pci address>, e.g. /run/gpu-busy/0000:03:00.0, once a
# second. erikshell reads that file when it exists and falls back to
# gpu_busy_percent when it does not.
{ pkgs, ... }:

let
  gpuBusy = pkgs.writers.writePython3 "gpu-busy" {
    # The file's docstrings and comments are longer than flake8's 79 columns.
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./gpu-busy.py);
in
{
  systemd.services.gpu-busy = {
    description = "GPU utilisation from DRM fdinfo, for the shell";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${gpuBusy} /run/gpu-busy";
      Restart = "always";
      RestartSec = "5s";

      # Listing another user's /proc/<pid>/fd is a plain permission check
      # (DAC_READ_SEARCH) and reading the links and fdinfo in it is a
      # ptrace-read check (SYS_PTRACE); those two are all it holds. Hyprland
      # is not dumpable, so even running as erikf would not be enough to see
      # the compositor's own GPU time.
      DynamicUser = true;
      AmbientCapabilities = [
        "CAP_SYS_PTRACE"
        "CAP_DAC_READ_SEARCH"
      ];
      CapabilityBoundingSet = [
        "CAP_SYS_PTRACE"
        "CAP_DAC_READ_SEARCH"
      ];
      RuntimeDirectory = "gpu-busy";
      RuntimeDirectoryMode = "0755";
      UMask = "0022";

      # It reads /proc and writes one directory, nothing else.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      SystemCallArchitectures = "native";
      MemoryMax = "64M";
      Nice = 10;
    };
  };
}
