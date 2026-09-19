# Isolated ROCm runtime for quality experiments; not a persistent system service.
let
  pkgs = import ./pkgs.nix;
in
pkgs.python313.withPackages (ps: [
  ps.torchWithRocm
  ((ps.torchao.override { torch = ps.torchWithRocm; }).overridePythonAttrs {
    # Validate the quantized GPU operation in the benchmark runtime instead of
    # pulling unrelated CUDA test dependencies into this ROCm-only environment.
    doCheck = false;
    nativeCheckInputs = [ ];
  })
  (ps.buildPythonPackage {
    pname = "transformers";
    version = "5.5.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/e7/28/35f7411ff80a3640c1f4fc907dcbb6a65061ebb82f66950e38bfc9f7f740/transformers-5.5.0-py3-none-any.whl";
      sha256 = "821a9ff0961abbb29eb1eb686d78df1c85929fdf213a3fe49dc6bd94f9efa944";
    };
    dependencies = with ps; [
      huggingface-hub
      numpy
      packaging
      pyyaml
      regex
      tokenizers
      typer
      safetensors
      tqdm
    ];
    postInstall = ''
      ${pkgs.patch}/bin/patch -d "$out/${pkgs.python313.sitePackages}" -p1 < ${./rocm-tensor-loading.patch}
    '';
    pythonImportsCheck = [ "transformers" ];
  })
  (ps.accelerate.override { torch = ps.torchWithRocm; })
  ps.librosa
  ps.soundfile
  ps.safetensors
  ps.sentencepiece
])
