{
  lib,
  buildGoModule,
  fetchFromGitHub,
  hyprland,
  pkg-config,
  nlohmann_json,
  libei,
  wayland,
  libxkbcommon,
  makeWrapper,
  quickshell,
  grim,
  ffmpeg,
}:
let
  version = "0.1.3-unstable-2026-09-11";
  revision = "afcd3dc39d859f18c0ac13c90625becb4a45ef66";
  src = fetchFromGitHub {
    owner = "SamSaffron";
    repo = "hyprland-computer-use";
    rev = revision;
    hash = "sha256-fge+kRqjjYH/FUHuAbGIXAYzmmD3TWATClJGfTo9XTw=";
  };
  patches = [ ./seat-only.patch ];
  postPatch = ''
    cp ${./seat_only_policy.hpp} native/seat_only_policy.hpp
    cp ${./seat_only_policy_test.cpp} native/seat_only_policy_test.cpp
  '';
  plugin = hyprland.stdenv.mkDerivation {
    pname = "hyprland-computer-use-seat-only";
    inherit
      version
      src
      patches
      postPatch
      ;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [
      hyprland
      nlohmann_json
      libei
      wayland
      libxkbcommon
    ]
    ++ hyprland.buildInputs;
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      make independent-seat build/header-version
      runHook postBuild
    '';
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      make native-test native-text-wire-test
      $CXX -std=c++23 -Wall -Wextra -Werror native/seat_only_policy_test.cpp -o build/seat-only-policy-test
      build/seat-only-policy-test
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 build/guard-seat.so $out/lib/guard-seat.so
      install -Dm755 build/header-version $out/bin/computer-use-header-version
      runHook postInstall
    '';
    passthru = { inherit hyprland; };
    meta = {
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };
in
buildGoModule {
  pname = "hyprland-computer-use";
  inherit
    version
    src
    patches
    postPatch
    ;
  vendorHash = "sha256-wWRjJdXZ5qtIx3N297ndHug4B/aEUwGfDiNbiR7+XGs=";
  subPackages = [ "cmd/hyprland-computer-use" ];
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/samsaffron/hyprland-computer-use/internal/app.Version=${version}-seat-only"
    "-X=github.com/samsaffron/hyprland-computer-use/internal/app.Commit=${revision}"
  ];
  nativeBuildInputs = [ makeWrapper ];
  # Desktop integration tests are opt-in upstream. Default tests use fixtures
  # and private sockets, never the live compositor/session bus.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # Upstream creates shell-script fixtures containing FHS utility paths.
    substituteInPlace internal/app/setup_test.go \
      --replace-fail /bin/mkdir "$(command -v mkdir)" \
      --replace-fail /bin/chmod "$(command -v chmod)"
    # The release-script unit test locates its fixture using runtime.Caller.
    GOFLAGS=-mod=vendor go test -timeout 120s ./...
    runHook postCheck
  '';
  postInstall = ''
    wrapProgram $out/bin/hyprland-computer-use --prefix PATH : ${
      lib.makeBinPath [
        hyprland
        quickshell
        grim
        ffmpeg
      ]
    }
  '';
  passthru = { inherit plugin revision; };
  meta = {
    description = "Window-scoped Hyprland MCP with mandatory independent-seat input";
    homepage = "https://github.com/SamSaffron/hyprland-computer-use";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hyprland-computer-use";
  };
}
