let
  pkgs = import ../stt-benchmark/pkgs.nix;
  python = pkgs.python3.withPackages (p: [ p.aiohttp ]);
  preview = import ./streaming-server.nix;
  final = import ./audio-server.nix;
  previewModel = import ../stt-benchmark/default.nix { model = "nemotron-en"; };
  finalModel = import ../stt-benchmark/default.nix { model = "vibevoice-asr-q8"; };
  finalConfig = pkgs.writeText "vibevoice-server.json" (
    builtins.toJSON {
      host = "127.0.0.1";
      port = 8783;
      backend = "vulkan";
      device = 0;
      threads = 4;
      lazy_load = false;
      max_loaded_models = 1;
      idle_unload_ms = 0;
      log_request_body = false;
      models = [
        {
          id = "vibevoice";
          family = "vibevoice_asr";
          path = "${finalModel}/model.gguf";
          task = "asr";
          mode = "offline";
        }
      ];
    }
  );
in
pkgs.writeShellApplication {
  name = "local-stt-server";
  runtimeInputs = [ pkgs.git ];
  text = ''
    export STT_NEMO_BINARY=${preview}/bin/nemo-speech
    export STT_NEMO_MODEL=${previewModel}/model.gguf
    export STT_VIBE_BINARY=${final}/bin/audiocpp_server
    export STT_VIBE_CONFIG=${finalConfig}
    exec ${python}/bin/python3 ${./gateway.py}
  '';
}
