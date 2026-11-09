# Whole-disk layout for the ablo laptop, applied by nixos-anywhere at install
# time (README.md). Everything but the EFI partition is LUKS2: the SOC 2
# disk-encryption control. The passphrase is asked for at every boot.
#
# The install reads the passphrase from /tmp/disk.key on the installer
# (nixos-anywhere --disk-encryption-keys); it is not stored on the laptop.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            passwordFile = "/tmp/disk.key";
            settings.allowDiscards = true;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
