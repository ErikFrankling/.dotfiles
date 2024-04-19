{ pkgs, ... }: {
  config.programs.nixvim.plugins = {
    treesitter = {
      enable = true;
      ensureInstalled = [
        "bash"
        "c"
        "c_sharp"
        "cmake"
        "cpp"
        "css"
        "dart"
        "dockerfile"
        "fish"
        "git_config"
        "gitcommit"
        "gitignroe"
        "glsl"
        "go"
        "haskell"
        "html"
        "ini"
        "java"
        "javascript"
        "jsdoc"
        "json"
        "json5"
        "jsonc"
        "jsonnet"
        "kotlin"
        "llvm"
        "lua"
        "luadoc"
        "make"
        "markdown"
        "markdown_inline"
        "meson"
        "ninja"
        "nix"
        "ocaml"
        "org"
        "passwd"
        "proto"
        "python"
        "regex"
        "rust"
        "scss"
        "sql"
        "toml"
        "typescript"
        "vim"
        "yaml"
        "zig"
      ];
      indent = true;
      folding = true;
    };

    treesitter-context = { enable = true; };
  };
}
