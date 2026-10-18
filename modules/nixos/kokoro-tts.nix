{ ... }:
{
  # Kokoro TTS (Kokoro-FastAPI, CPU): read-aloud's small voice for T3 Code,
  # used while dictation holds the GPU. OpenAI-style POST /v1/audio/speech on
  # http://127.0.0.1:8880 with "speed" and "voice" in the request.
  #
  # Runs on the PC's CPU (about 9x faster than real time, no GPU memory). The
  # homelab copy (192.168.50.100:8880, homelab repo apps/kokoro-tts.yaml) was
  # slower than real time on that CPU; it moves to the GTX 1060 once the
  # node's NVIDIA kernel module matches its driver again, and then this
  # container can go. Comparison: research/read-aloud/2026-10-18.
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.kokoro-tts = {
    image = "ghcr.io/remsky/kokoro-fastapi-cpu:v0.9.0@sha256:ee3111d6a2c903ed62f3b4fa19543c6901205ed39fce3c177e895b34a8386b9c";
    ports = [ "127.0.0.1:8880:8880" ];
    # Bursty per sentence; keep it from taking the whole CPU while Erik works.
    extraOptions = [
      "--cpus=6"
      "--memory=3g"
    ];
  };
}
