{
  ...
}:

{
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    # ibus.engines = with pkgs.ibus-engines; [ ];
    # ibus.panel
  };

  environment.sessionVariables = {
    GTK_IM_MODULE = "ibus";
    QT_IM_MODULE = "ibus";
    XMODIFIERS = "@im=ibus";
  };
}
