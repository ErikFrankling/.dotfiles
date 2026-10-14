"""Exercise the actual patched IBus registry branch without a live display.

Usage: python ibus-native-seat-test.py SOURCE_FILE PATCH_FILE
CC can select the compiler. Temporary files stay under the working directory.
"""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


def main():
    source, patch = (Path(arg).resolve() for arg in sys.argv[1:])
    with tempfile.TemporaryDirectory(prefix=".ibus-seat-check-", dir=Path.cwd()) as temporary:
        directory = Path(temporary)
        copied = directory / "client/wayland/ibuswaylandim.c"
        copied.parent.mkdir(parents=True)
        shutil.copy(source, copied)
        copied.chmod(0o600)
        with patch.open() as changes:
            subprocess.run(["patch", "-p1"], cwd=directory, stdin=changes, check=True)

        code = copied.read_text()
        marker = "} else if (!g_strcmp0 (interface, wl_seat_interface.name)) {"
        body = code.split(marker, 1)[1].split("} else if (!g_strcmp0 (interface,", 1)[0]
        # Compile the real branch with instrumentation at its protocol boundary.
        # The regression is a second global replacing a live native seat and
        # requesting another IME, not merely the presence of a source string.
        prefix = r"""
#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
typedef struct {void *seat; unsigned wl_name; void *input_method_v2;} IBusWaylandSeat;
typedef struct {IBusWaylandSeat *seat; void *seats; void *input_method_manager_v2;} State;
static int binds, imes;
static int wl_seat_interface, seat_listener, input_method_listener_v2;
#define g_slice_new0(T) ((T *)calloc(1, sizeof(T)))
static void *wl_registry_bind(void *r, unsigned n, void *i, unsigned v) {
    ++binds; return (void *)(uintptr_t)n;
}
static void wl_seat_add_listener(void *s, void *l, void *d) {}
static void g_ptr_array_add(void *a, void *v) {}
static void *zwp_input_method_manager_v2_get_input_method(void *m, void *s) {
    ++imes; return s;
}
static void zwp_input_method_v2_add_listener(void *i, void *l, void *d) {}
static void add_seat(State *priv, unsigned name, unsigned version) {
    void *registry = 0; void *wlim = 0;
"""
        suffix = r"""
}
int main(void) {
    State state = {0};
    add_seat(&state, 1, 7);
    IBusWaylandSeat *native = state.seat;
    assert(native && native->wl_name == 1 && binds == 1 && imes == 0);
    add_seat(&state, 2, 7);
    assert(state.seat == native && binds == 1 && imes == 0);
    add_seat(&state, 3, 7);
    assert(state.seat == native && binds == 1 && imes == 0);
    free(native);
    return 0;
}
"""
        fixture = directory / "test.c"
        fixture.write_text(prefix + body + suffix)
        binary = directory / "test"
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) +
                       ["-std=c11", str(fixture), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
    print("PASS: later seats cannot bind, create another IME, or replace the native seat")


if __name__ == "__main__":
    main()
