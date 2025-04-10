{ config, lib, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    v4l-utils
    ffmpeg
    gphoto2

    (pkgs.wrapOBS {
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-pipewire-audio-capture
      ];
    })
  ];

  boot.extraModulePackages = with config.boot.kernelPackages;
    [
      v4l2loopback
    ];
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=2 video_nr=1,2 card_label="OBS Cam, Virt Cam" exclusive_caps=1
  '';
}
