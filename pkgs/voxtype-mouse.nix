# voxtype-mouse: bridge a mouse button to voxtype's own record commands.
#
# Why this exists: voxtype's built-in evdev hotkey only opens devices that look
# like keyboards (it requires KEY_A + KEY_Z + KEY_ENTER in the device's key
# capabilities), so a pure mouse is never watched — a button press on the
# trackball is invisible to it no matter what is bound.
#
# The alternatives were checked and do not work on this setup:
#   * KDE global shortcut: press-only. KDE hands apps no key-release event, so
#     it can only ever toggle, never hold-to-talk.
#   * KWin workspace scripts: expose keyboard shortcuts and cursor position, but
#     no mouse button events at all.
#   * KWin scripted effects: `mouseChanged` carries button state (so
#     press/release could be inferred), but it is observational — it cannot
#     consume the event — and needs an enabled effect package.
#   * keyd: has no `task` key name (only leftmouse/middlemouse/rightmouse/
#     mouse1/mouse2/mouseback/mouseforward), so BTN_TASK cannot be bound.
#
# Raw evdev does expose both edges, which is all this needs:
#
#   BTN_TASK val=1  -> voxtype record start   (press)
#   BTN_TASK val=0  -> voxtype record stop    (release)
#   BTN_TASK val=2  -> ignored                (autorepeat)
#
# So this mirrors exactly what voxtype's own listener does internally, using the
# commands voxtype documents for compositor bindings (`record start` on press,
# `record stop` on release).
#
# Requirements: read access to the device node, i.e. membership of the `input`
# group (the module adds it).
#
# Caveat: a reader cannot consume the event, so the button press still reaches
# whatever has focus. BTN_TASK is normally inert in applications, but that is
# the reason this is a "bridge" and not a true interceptor.
{
  lib,
  python3,
  writeShellScriptBin,
  writeText,
  voxtype,
  # Match on the input device's reported name and USB id. Deliberately NOT on
  # /dev/input/eventN — those numbers shift across reboots and re-plugs, which
  # is the usual way a watcher like this silently stops working.
  deviceName ? "HUGE PLUS",
  vendor ? "056e",
  product ? "01ab",
  # evdev key/button code. 279 = BTN_TASK (what this trackball's extra button
  # reports). Discover with: `evtest` or a raw read of /dev/input/eventN.
  button ? 279,
}: let
  script = writeText "voxtype-mouse.py" ''
    import argparse
    import glob
    import os
    import select
    import struct
    import subprocess
    import sys
    import time

    EV_KEY = 1
    EVENT_FMT = "llHHi"
    EVENT_SIZE = struct.calcsize(EVENT_FMT)

    BTN_NAMES = {
        272: "BTN_LEFT", 273: "BTN_RIGHT", 274: "BTN_MIDDLE",
        275: "BTN_SIDE", 276: "BTN_EXTRA", 277: "BTN_FORWARD",
        278: "BTN_BACK", 279: "BTN_TASK",
    }


    def button_label(code):
        return BTN_NAMES.get(code, "button %d" % code)


    def device_advertises(sysdir, code):
        """True if the device's key bitmap includes `code`.

        Capabilities are exposed as a big-endian array of 64-bit hex words, so
        the word holding bit N is the (len-1 - N//64)-th from the left.
        """
        try:
            with open(os.path.join(sysdir, "capabilities/key")) as fh:
                words = [int(w, 16) for w in fh.read().split()]
        except (OSError, ValueError):
            return False
        idx = code // 64
        if idx >= len(words):
            return False
        return bool((words[len(words) - 1 - idx] >> (code % 64)) & 1)


    def find_device(name_sub, vendor, product, code):
        """Locate the event node by device name + USB id, not by event number.

        One physical device commonly exposes *several* event nodes sharing the
        same name and USB ids — this trackball presents a keyboard-like
        interface plus a pointer interface, both reported as "HUGE PLUS
        HUGE PLUS" with 056e:01ab. Matching on name+ids alone therefore picks
        whichever node enumerates first, which is not necessarily the one
        carrying the button.

        So a node is only accepted if it actually advertises the requested
        button code. That makes the match both correct and self-checking: if
        the button is absent, no node is chosen and the watcher keeps waiting
        rather than silently watching the wrong device.
        """
        for path in sorted(
            glob.glob("/dev/input/event*"),
            key=lambda p: int(p.split("event")[1]) if p.split("event")[1].isdigit() else 0,
        ):
            base = os.path.basename(path)
            sysdir = "/sys/class/input/%s/device" % base
            try:
                with open(os.path.join(sysdir, "name")) as fh:
                    name = fh.read().strip()
                with open(os.path.join(sysdir, "id/vendor")) as fh:
                    vid = fh.read().strip()
                with open(os.path.join(sysdir, "id/product")) as fh:
                    pid = fh.read().strip()
            except OSError:
                continue
            if name_sub and name_sub.lower() not in name.lower():
                continue
            if vendor and vid.lower() != vendor.lower():
                continue
            if product and pid.lower() != product.lower():
                continue
            if not device_advertises(sysdir, code):
                continue
            return path, name
        return None, None


    def read_exact(fd, n):
        buf = b""
        while len(buf) < n:
            chunk = fd.read(n - len(buf))
            if not chunk:
                raise OSError("device closed")
            buf += chunk
        return buf


    def main():
        ap = argparse.ArgumentParser(description="Bridge a mouse button to voxtype record start/stop")
        ap.add_argument("--device-name", default="")
        ap.add_argument("--vendor", default="")
        ap.add_argument("--product", default="")
        ap.add_argument("--button", type=int, required=True)
        ap.add_argument("--voxtype", required=True, help="absolute path to the voxtype binary")
        args = ap.parse_args()

        env = os.environ.copy()
        # A GUI/session-launched unit may not carry XDG_RUNTIME_DIR; voxtype
        # locates the daemon via $XDG_RUNTIME_DIR/voxtype/voxtype.lock, so
        # without it `record start` silently fails with "daemon is not running".
        env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())

        label = button_label(args.button)
        print(
            "voxtype-mouse: looking for device name~%r vendor=%s product=%s with %s"
            % (args.device_name, args.vendor, args.product, label),
            flush=True,
        )

        def record(action):
            try:
                subprocess.run(
                    [args.voxtype, "record", action],
                    env=env,
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                print("voxtype-mouse: -> record %s" % action, flush=True)
            except OSError as exc:
                print("voxtype-mouse: failed to run voxtype: %s" % exc, file=sys.stderr, flush=True)

        fd = None
        pressed = False

        while True:
            if fd is None:
                path, name = find_device(args.device_name, args.vendor, args.product, args.button)
                if path is None:
                    # Device absent (unplugged, powered off). Wait and retry so
                    # the service survives a disconnect instead of dying.
                    time.sleep(2)
                    continue
                try:
                    fd = open(path, "rb", buffering=0)
                except OSError as exc:
                    print("voxtype-mouse: cannot open %s: %s" % (path, exc), file=sys.stderr, flush=True)
                    fd = None
                    time.sleep(2)
                    continue
                pressed = False
                print("voxtype-mouse: watching %s (%s)" % (path, name), flush=True)

            try:
                ready, _, _ = select.select([fd], [], [], 5)
                if not ready:
                    continue
                event = read_exact(fd, EVENT_SIZE)
                _sec, _usec, etype, code, value = struct.unpack(EVENT_FMT, event)
            except (OSError, ValueError) as exc:
                # Device vanished or reset: drop the fd and rescan. If a press
                # was in flight, stop recording rather than leave the daemon
                # capturing until its safety timeout.
                print("voxtype-mouse: device lost (%s); rescanning" % exc, file=sys.stderr, flush=True)
                if pressed:
                    record("stop")
                    pressed = False
                try:
                    fd.close()
                except Exception:
                    pass
                fd = None
                continue

            if etype != EV_KEY or code != args.button:
                continue

            if value == 1 and not pressed:
                pressed = True
                record("start")
            elif value == 0 and pressed:
                pressed = False
                record("stop")
            # value == 2 is autorepeat: ignored on purpose.


    if __name__ == "__main__":
        try:
            main()
        except KeyboardInterrupt:
            sys.exit(0)
  '';
in
  writeShellScriptBin "voxtype-mouse" ''
    exec ${python3}/bin/python3 ${script} \
      --device-name ${lib.escapeShellArg deviceName} \
      --vendor ${lib.escapeShellArg vendor} \
      --product ${lib.escapeShellArg product} \
      --button ${toString button} \
      --voxtype ${voxtype}/bin/voxtype \
      "$@"
  ''
