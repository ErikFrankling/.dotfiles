let
  httplib = builtins.fetchTarball {
    url = "https://github.com/yhirose/cpp-httplib/archive/62d899feac3cf9215a55f2b43da250fdd98d2156.tar.gz";
    sha256 = "1j927q3x13aq65smljwyp0g7ynwq4n2hjv5b7dq21g0bir5c33g1";
  };
in
(import ../stt-benchmark/nemo.nix).overrideAttrs (old: {
  pname = "nemotron-streaming-server-vulkan";
  postUnpack = old.postUnpack + ''
    cp -r ${httplib}/. "$sourceRoot/third_party/cpp-httplib/"
    chmod -R u+w "$sourceRoot/third_party/cpp-httplib"
  '';
  cmakeFlags = builtins.filter (flag: flag != "-DNEMO_SPEECH_BUILD_HTTP=OFF") old.cmakeFlags ++ [
    "-DNEMO_SPEECH_BUILD_HTTP=ON"
  ];
})
