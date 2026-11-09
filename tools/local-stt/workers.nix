# The two speech recognisers. llama-swap runs them as models
# (modules/nixos/local-stt.nix adds them to its config); the gateway only
# reaches them through llama-swap's /upstream/<model>/ passthrough.
let
  pkgs = import ../stt-benchmark/pkgs.nix;
  preview = import ./streaming-server.nix;
  final = import ./audio-server.nix;
  previewModel = import ../stt-benchmark/default.nix { model = "nemotron-en"; };
  finalModel = import ../stt-benchmark/default.nix { model = "vibevoice-asr-q8"; };
  previewPort = 5812;
  finalPort = 5813;
  finalConfig = pkgs.writeText "vibevoice-server.json" (
    builtins.toJSON {
      host = "127.0.0.1";
      port = finalPort;
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
          # The gateway uploads WAV bytes (multipart), which has no options
          # field, so the decoding settings live here.
          default_request_options = {
            temperature = 0;
            max_tokens = 4096;
            num_beams = 1;
            audio_chunk_mode = "none";
          };
        }
      ];
    }
  );
in
{
  inherit previewPort finalPort;
  previewBinary = "${preview}/bin/nemo-speech";
  previewModel = "${previewModel}/model.gguf";
  finalBinary = "${final}/bin/audiocpp_server";
  inherit finalConfig;
  previewCommand = "${preview}/bin/nemo-speech serve --asr-model ${previewModel}/model.gguf --host 127.0.0.1 --port ${toString previewPort} --backend vulkan --threads 4 --no-ui --read-timeout 1900";
  finalCommand = "${final}/bin/audiocpp_server --config ${finalConfig}";
}
