let
  pkgs = import ../stt-benchmark/pkgs.nix;
  python = pkgs.python3.withPackages (p: [ p.aiohttp ]);
  workers = import ./workers.nix;
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
in
pkgs.writeShellApplication {
  name = "local-stt-server";
  runtimeInputs = [ pkgs.git ];
  # The STT_* worker paths are not run here (llama-swap runs the workers);
  # they are recorded in each recording's state.json as provenance.
  text = ''
    export STT_NEMO_BINARY=${workers.previewBinary}
    export STT_NEMO_MODEL=${workers.previewModel}
    export STT_VIBE_BINARY=${workers.finalBinary}
    export STT_VIBE_CONFIG=${workers.finalConfig}
    export STT_PROBE_PCM=${probeClip}
    exec ${python}/bin/python3 ${./gateway.py}
  '';
}
