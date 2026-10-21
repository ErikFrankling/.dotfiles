let
  pkgs = import ../stt-benchmark/pkgs.nix;
  python = pkgs.python3.withPackages (p: [ p.aiohttp ]);
  preview = import ./streaming-server.nix;
  final = import ./audio-server.nix;
  previewModel = import ../stt-benchmark/default.nix { model = "nemotron-en"; };
  finalModel = import ../stt-benchmark/default.nix { model = "vibevoice-asr-q8"; };
  # Spoken words for the gateway's live-draft self-test (16 kHz mono PCM).
  probeClip =
    pkgs.runCommand "local-stt-probe.pcm"
      {
        nativeBuildInputs = [
          pkgs.espeak-ng
          pkgs.sox
        ];
      }
      ''
        espeak-ng -s 150 -w say.wav "testing the dictation server, one two three"
        sox say.wav -r 16000 -c 1 -b 16 -e signed-integer -t raw $out pad 0.3 0.8
      '';
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
    export STT_PROBE_PCM=${probeClip}
    exec ${python}/bin/python3 ${./gateway.py}
  '';
}
