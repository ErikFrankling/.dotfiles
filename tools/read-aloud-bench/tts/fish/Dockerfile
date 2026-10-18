FROM rab-fish:rocm
# Ubuntu ships its own sitecustomize, so hook in through a .pth file.
COPY fish_torchaudio_patch.py /opt/venv/lib/python3.12/site-packages/
RUN echo "import fish_torchaudio_patch" > /opt/venv/lib/python3.12/site-packages/zz_fish_torchaudio_patch.pth
