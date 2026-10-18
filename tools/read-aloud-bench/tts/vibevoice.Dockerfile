FROM breeze-tts:42aa40215419
RUN pip freeze | grep -E '^(torch|torchaudio|torchvision)==' > /constraints.txt
RUN git clone https://github.com/microsoft/VibeVoice /opt/vibevoice && cd /opt/vibevoice \
 && pip install -c /constraints.txt -e ".[streamingtts]"
RUN python -c "import torch; assert torch.version.hip, torch.__version__"
