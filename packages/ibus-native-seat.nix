# Hyprland has one native input-method relay. IBus 1.5.34 otherwise switches
# priv->seat to every newly advertised seat, even when its IME is unavailable.
# Keep the original native seat when the agent plugin advertises a second one.
{
  ibus,
  runCommand,
  python3,
  stdenv,
  patch,
}:

ibus.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./ibus-native-seat.patch ];
  passthru = (old.passthru or { }) // {
    tests = ((old.passthru or { }).tests or { }) // {
      nativeSeat =
        runCommand "ibus-native-seat-regression"
          {
            nativeBuildInputs = [
              python3
              stdenv.cc
              patch
            ];
          }
          ''
            python ${./ibus-native-seat-test.py} \
              ${ibus.src}/client/wayland/ibuswaylandim.c ${./ibus-native-seat.patch}
            touch "$out"
          '';
    };
  };
})
