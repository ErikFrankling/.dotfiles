# Chatterbox pins torch 2.6 (CUDA); install it without deps and add the rest by hand.
FROM breeze-tts:42aa40215419
RUN pip freeze | grep -E '^(torch|torchaudio|torchvision)==' > /constraints.txt
RUN pip install --no-deps chatterbox-tts==0.1.7 \
 && pip install -c /constraints.txt librosa==0.11.0 s3tokenizer transformers==5.2.0 diffusers==0.29.0 resemble-perth conformer==0.3.2 safetensors==0.5.3 pyloudnorm omegaconf spacy-pkuseg pykakasi==2.3.0
RUN python -c "import torch; assert torch.version.hip, torch.__version__"
