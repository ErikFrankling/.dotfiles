{
  lib,
  hyprland,
  pkg-config,
  systemd,
  coreutils,
}:
hyprland.stdenv.mkDerivation {
  pname = "hyprland-agent-windows";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ hyprland ] ++ hyprland.buildInputs;
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    $CXX -shared -fPIC -std=c++26 -O2 -Wall -Wextra -Wno-unused-parameter \
      -DSYSTEMD_RUN='"${systemd}/bin/systemd-run"' -DENV_BIN='"${coreutils}/bin/env"' \
      plugin.cpp $(pkg-config --cflags hyprland pixman-1 libdrm wayland-server) \
      -o agent-windows.so
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    $CXX -std=c++26 -Wall -Wextra -Wno-unused-parameter origin_test.cpp -o origin-test
    ./origin-test
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 agent-windows.so $out/lib/agent-windows.so
    runHook postInstall
  '';
  passthru = { inherit hyprland; };
  meta.platforms = lib.platforms.linux;
}
