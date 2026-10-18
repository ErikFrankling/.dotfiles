# Extra TTS engines on top of the Breeze ROCm image, never replacing its ROCm torch.
FROM breeze-tts:42aa40215419
RUN pip freeze | grep -E '^(torch|torchaudio|torchvision)==' > /constraints.txt
ARG PACKAGES
ARG APT=""
RUN if [ -n "$APT" ]; then apt-get update && apt-get install -y --no-install-recommends $APT && rm -rf /var/lib/apt/lists/*; fi
RUN pip install -c /constraints.txt $PACKAGES
RUN python -c "import torch; assert torch.version.hip, torch.__version__"
