{
  config,
  pkgs,
  lib,
  username,
  ...
}:

{
  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      # TPM emulation (required for Windows 11)
      swtpm.enable = true;
    };
  };

  # Virt-manager GUI
  programs.virt-manager.enable = true;

  # USB passthrough support
  virtualisation.spiceUSBRedirection.enable = true;

  users.users.${username}.extraGroups = [
    "libvirtd"
    "kvm"
  ];

  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    qemu
    OVMF
    spice-gtk # For USB redirection in virt-viewer
    virtio-win # This provides the ISO at a known path
  ];

  # Enable the default NAT network
  networking.firewall.trustedInterfaces = [ "virbr0" ];
}
