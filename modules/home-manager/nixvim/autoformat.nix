{ ... }:

{
  programs.nixvim = {
    plugins.parinfer-rust.enable = true;
    extraFiles = {
      "autoformat.lua" = "./autoformat.lua";
    };
  };
}
