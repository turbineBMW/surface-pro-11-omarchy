#!/bin/bash

set -euo pipefail

package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
extractor="$package_dir/extract-ath12k-board.py"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() {
  echo "not ok - $1" >&2
  exit 1
}

# Build a board-2.bin container with two named records, in the ath12k layout.
python - "$scratch/board-2.bin" <<'EOF'
import struct, sys

def ie(kind, payload):
    return struct.pack("<II", kind, len(payload)) + payload + b"\0" * (-len(payload) % 4)

def board(name, data):
    return ie(0, ie(0, name.encode()) + ie(1, data))

content = b"QCA-ATH12K-BOARD\0mmm" + board("bus=pci,other", b"other-board-data") + board("bus=pci,wanted", b"wanted-board-data!")
open(sys.argv[1], "wb").write(content)
EOF

wanted_sha=$(printf 'wanted-board-data!' | sha256sum | cut -d' ' -f1)
python "$extractor" --expected-bytes 18 --expected-sha256 "$wanted_sha" \
  "$scratch/board-2.bin" "bus=pci,wanted" "$scratch/board.bin" ||
  fail "the named board record is extracted"
[[ $(<"$scratch/board.bin") == "wanted-board-data!" ]] ||
  fail "the extracted board record is unmodified"

if python "$extractor" --expected-bytes 18 --expected-sha256 "$(printf x | sha256sum | cut -d' ' -f1)" \
  "$scratch/board-2.bin" "bus=pci,wanted" "$scratch/wrong.bin" 2>/dev/null; then
  fail "a record with an unexpected checksum is rejected"
fi
[[ ! -e $scratch/wrong.bin ]] || fail "a rejected record leaves no output"

if python "$extractor" --expected-bytes 16 --expected-sha256 "$wanted_sha" \
  "$scratch/board-2.bin" "bus=pci,missing" "$scratch/missing.bin" 2>/dev/null; then
  fail "a missing record is rejected"
fi

source "$package_dir/PKGBUILD"
[[ $_board_record == *"subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255" ]] ||
  fail "the package selects the validated Surface Pro 11 board record"
[[ " ${options[*]} " == *" !strip "* ]] ||
  fail "the ELF board data is packaged without stripping"
[[ " ${arch[*]} " == " aarch64 " && " ${groups[*]} " == *" omarchy-platform-qualcomm "* ]] ||
  fail "the package is tagged Qualcomm-only for aarch64"
grep -q "^_audioreach_commit=d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677$" "$package_dir/PKGBUILD" ||
  fail "the topology builds from pinned AudioReach source"
grep -q 'File "/Qualcomm/x1e80100/Surface11-HiFi.conf"' "$package_dir/MICROSOFT-Surface-Pro-11.conf" ||
  fail "the card profile points at the shipped HiFi verb"

grep -Fq 'api.libcamera.path = "/base/soc@0/cci@ac15000/i2c-bus@0/camera@60"' "$package_dir/50-surface-pro-11-cameras.conf" ||
  fail "the infrared sensor is hidden from camera pickers"
! grep -q 'monitor.v4l2.rules' "$package_dir/50-surface-pro-11-cameras.conf" ||
  fail "V4L2 devices are not disabled; in WirePlumber 0.5 that stalls camera discovery"
grep -A1 -- '- BlackLevel:' "$package_dir/imx681.yaml" | grep -q 'blackLevel: 4096$' ||
  fail "the front camera tuning carries the measured IMX681 black level"

bin="$scratch/bin"
mkdir -p "$bin"

# Every hook acts only on the Surface Pro 11 OLED.
printf 'microsoft,denali-oled\0microsoft,denali\0qcom,x1e80100\0' >"$scratch/denali"
printf 'lenovo,yoga-slim7x\0qcom,x1e80100\0' >"$scratch/other"

# Battery: after resume the thresholds already set are written back unchanged.
battery="$scratch/qcom-battmgr-bat"
mkdir -p "$battery"
charge_sleep() {
  SP11_CHARGE_LIMIT_SYSFS="$battery" SP11_CHARGE_LIMIT_COMPATIBLE="$scratch/$1" \
    bash "$package_dir/surface-pro-11-charge-limit-sleep" "${@:2}"
}
thresholds() {
  printf '%s\n' "$1" >"$battery/charge_control_start_threshold"
  printf '%s\n' "$2" >"$battery/charge_control_end_threshold"
}
thresholds 60 90
[[ $(charge_sleep denali post suspend) == *"restored start=60 end=90" ]] ||
  fail "a user-chosen charge window is written back as set after resume"
[[ $(<"$battery/charge_control_start_threshold") == 60 && $(<"$battery/charge_control_end_threshold") == 90 ]] ||
  fail "the charge window is never replaced"
thresholds 0 100
[[ -z $(charge_sleep denali post suspend) ]] || fail "with no charge limit set, nothing is written"
thresholds 60 90
[[ -z $(charge_sleep other post suspend) ]] || fail "the charge hook does nothing on other hardware"
[[ -z $(charge_sleep denali pre suspend) ]] || fail "the charge hook acts only after resume"
! grep -l 'charge' "$package_dir"/*.service >/dev/null 2>&1 ||
  fail "no boot-time service imposes a charge window"

# Pen: iptsd is stopped before sleep and a fresh process started after resume.
cat >"$bin/systemctl" <<'STUB'
#!/bin/bash
case $1 in
  list-units) printf 'iptsd@dev-hidraw5.service loaded active running Intel Precise Touch & Stylus Daemon\n' ;;
  *) printf '%s\n' "$*" >>"$SYSTEMCTL_LOG" ;;
esac
STUB
chmod +x "$bin/systemctl"
iptsd_sleep() {
  PATH="$bin:$PATH" SYSTEMCTL_LOG="$scratch/systemctl.log" SP11_IPTSD_STATE="$scratch/iptsd.units" \
    SP11_IPTSD_COMPATIBLE="$scratch/$1" SP11_IPTSD_SETTLE=0 bash "$package_dir/surface-pro-11-iptsd-sleep" "${@:2}"
}
iptsd_sleep other pre suspend
[[ ! -e $scratch/systemctl.log ]] || fail "iptsd is left alone on other hardware"
iptsd_sleep denali pre suspend
iptsd_sleep denali post suspend
[[ $(<"$scratch/systemctl.log") == $'stop iptsd@dev-hidraw5.service\nstart iptsd@dev-hidraw5.service' ]] ||
  fail "iptsd restarts across suspend, since the touch controller resets on resume"
iptsd_sleep denali post suspend
[[ $(wc -l <"$scratch/systemctl.log") == 2 ]] ||
  fail "a resume without a matching stop starts nothing"

# Lid: wake on the lid only when suspending with it closed; an open lid's
# false edge in CX collapse would wake the machine at once.
cat >"$bin/busctl" <<'STUB'
#!/bin/bash
[[ -n ${LID_CLOSED:-} ]] || exit 1
echo "b $LID_CLOSED"
STUB
chmod +x "$bin/busctl"
lid_wakeup="$scratch/lid-wakeup"
lid_sleep() {
  PATH="$bin:$PATH" SP11_LID_WAKE_SYSFS="$lid_wakeup" SP11_LID_WAKE_COMPATIBLE="$scratch/$1" \
    bash "$package_dir/surface-pro-11-lid-wake-sleep" "${@:2}"
}
echo enabled >"$lid_wakeup"
LID_CLOSED=false lid_sleep denali pre suspend >/dev/null
[[ $(<"$lid_wakeup") == disabled ]] || fail "suspending with the lid open turns lid wake off"
LID_CLOSED=true lid_sleep denali pre suspend >/dev/null
[[ $(<"$lid_wakeup") == enabled ]] || fail "suspending with the lid closed arms lid wake"
LID_CLOSED= lid_sleep denali pre suspend >/dev/null
[[ $(<"$lid_wakeup") == disabled ]] || fail "an unknown lid state counts as open"
echo enabled >"$lid_wakeup"
LID_CLOSED=false lid_sleep other pre suspend
LID_CLOSED=false lid_sleep denali post suspend
[[ $(<"$lid_wakeup") == enabled ]] || fail "the lid hook acts only before suspend on the Surface Pro 11"

# Flex Keyboard: pair on attach when there is no working bond, reconnect on
# detach. bluetoothctl, btmgmt and the pairing tool are stubs that record what
# they were asked to do.
cat >"$bin/bluetoothctl" <<'STUB'
#!/bin/bash
case $1 in
  show) printf '\tPowered: yes\n' ;;
  info)
    [[ -e $BT_STATE/paired ]] || exit 1
    printf '\tPaired: yes\n\tBonded: yes\n'
    if [[ -e $BT_STATE/connected ]]; then printf '\tConnected: yes\n'; else printf '\tConnected: no\n'; fi
    ;;
  connect) echo "connect $2" >>"$BT_STATE/log"; [[ ! -e $BT_STATE/connectable ]] || : >"$BT_STATE/connected" ;;
  remove) echo "remove $2" >>"$BT_STATE/log"; rm -f "$BT_STATE/paired" "$BT_STATE/connected" ;;
  *) echo "$*" >>"$BT_STATE/log" ;;
esac
STUB
cat >"$bin/btmgmt" <<'STUB'
#!/bin/bash
echo "btmgmt $*" >>"$BT_STATE/log"
STUB
cat >"$bin/logger" <<'STUB'
#!/bin/bash
STUB
cat >"$bin/fake-flex-pair" <<'STUB'
#!/bin/bash
echo "pair $*" >>"$BT_STATE/log"
[[ ${PAIR_FAILS:-} ]] && exit 1
: >"$BT_STATE/paired"; : >"$BT_STATE/connected"
STUB
chmod +x "$bin/bluetoothctl" "$bin/btmgmt" "$bin/logger" "$bin/fake-flex-pair"

keyboard=C5:45:77:5A:A0:E8
flex_reset() {
  rm -rf "$scratch/bt" "$scratch/run" "$scratch/hid"
  mkdir -p "$scratch/bt" "$scratch/run" "$scratch/hid"
  : >"$scratch/bt/log"
}
flex_attach() { mkdir -p "$scratch/hid/0019:045E:0C8B.0002" "$scratch/hid/0019:045E:0C8F.0001"; }
flex_bond() { echo "$keyboard" >"$scratch/bt/address"; : >"$scratch/bt/paired"; }
flex() {
  PATH="$bin:$PATH" BT_STATE="$scratch/bt" SP11_FLEX_COMPATIBLE="$scratch/$1" \
    SP11_FLEX_HID_DEVICES="$scratch/hid" SP11_FLEX_ADDRESS_FILE="$scratch/bt/address" \
    SP11_FLEX_RUN_DIR="$scratch/run" SP11_FLEX_PAIR_TOOL="$bin/fake-flex-pair" SP11_FLEX_NO_SLEEP=1 \
    bash "$package_dir/surface-pro-11-flex-$2" >/dev/null 2>&1 || true
}
flex_did() { grep -qx "$1" "$scratch/bt/log"; }

flex_reset; flex_attach
flex other autopair
! flex_did "pair --no-detach" || fail "the Flex Keyboard is left alone on other hardware"

flex_reset; flex_attach
flex denali autopair
flex_did "pair --no-detach" || fail "an attached keyboard with no bond is paired over the wire"

flex_reset; flex_attach; flex_bond; : >"$scratch/bt/connected"
flex denali autopair
[[ ! -s $scratch/bt/log ]] || fail "a working bond is left alone"

# The bond would even connect on request: only the marker says it is stale.
flex_reset; flex_attach; flex_bond; : >"$scratch/bt/connectable"; : >"$scratch/run/flex-needs-repair"
flex denali autopair
flex_did "remove $keyboard" && flex_did "pair --no-detach" ||
  fail "a bond that failed to reconnect on detach is replaced on the next attach"
[[ ! -e $scratch/run/flex-needs-repair ]] || fail "a successful pair clears the repair marker"

flex_reset; flex_attach; flex_bond
flex denali autopair
flex_did "btmgmt power off" && flex_did "remove $keyboard" && flex_did "pair --no-detach" ||
  fail "a bond that will not connect even after a controller reset is replaced"

flex_reset; flex_attach; flex_bond; : >"$scratch/bt/connectable"
flex denali autopair
! flex_did "pair --no-detach" || fail "a bond that connects on request is kept"

flex_reset; mkdir -p "$scratch/hid/0019:045E:0C8B.0002"
flex denali autopair
! flex_did "pair --no-detach" || fail "without the kernel's pairing channel nothing is paired"

flex_reset
flex denali autopair
! flex_did "pair --no-detach" || fail "a detached keyboard is not paired"

flex_reset; flex_bond; : >"$scratch/bt/connectable"
flex denali reconnect
flex_did "connect $keyboard" && [[ ! -e $scratch/run/flex-needs-repair ]] ||
  fail "a detached keyboard is connected over Bluetooth"

flex_reset; flex_bond
flex denali reconnect
[[ -e $scratch/run/flex-needs-repair ]] || fail "a detached keyboard that never connects is marked for re-pairing"

flex_reset; flex_attach; flex_bond
flex denali reconnect
! flex_did "connect $keyboard" || fail "an attached keyboard is not connected over Bluetooth"

python -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$package_dir/surface-pro-11-flex-pair" ||
  fail "the pairing tool is valid Python"
for unit in surface-pro-11-flex-autopair surface-pro-11-flex-reconnect; do
  grep -qx 'ConditionFirmware=device-tree-compatible(microsoft,denali-oled)' "$package_dir/$unit.service" ||
    fail "$unit runs only on the Surface Pro 11 OLED"
  grep -q "start $unit.service" "$package_dir/70-surface-pro-11-flex-keyboard.rules" ||
    fail "attaching or detaching the keyboard starts $unit"
done

# Touchpad: after resume a job of its own puts the attached keyboard's touchpad
# back in touchpad mode. systemd-run is a stub that records what it was asked to
# run.
cat >"$bin/systemd-run" <<'STUB'
#!/bin/bash
echo "systemd-run $*" >>"$TOUCHPAD_LOG"
STUB
chmod +x "$bin/systemd-run"
touchpad_sleep() {
  : >"$scratch/touchpad.log"
  PATH="$bin:$PATH" TOUCHPAD_LOG="$scratch/touchpad.log" SP11_TOUCHPAD_COMPATIBLE="$scratch/$1" \
    python "$package_dir/surface-pro-11-touchpad-mode-sleep" "${@:2}"
}
touchpad_sleep denali post suspend
grep -q -- "--no-block .*surface-pro-11-touchpad-mode-sleep check$" "$scratch/touchpad.log" ||
  fail "after resume the touchpad is checked in a job that does not hold up the resume"
touchpad_sleep denali pre suspend
[[ ! -s $scratch/touchpad.log ]] || fail "the touchpad hook acts only after resume"
touchpad_sleep other post suspend
[[ ! -s $scratch/touchpad.log ]] || fail "the touchpad hook does nothing on other hardware"

# The touchpad's mode and switches, read and written through a fake hidraw node.
touchpad="$scratch/touchpad/0019:045E:0C8D.0005"
mkdir -p "$touchpad/hidraw/hidraw4" "$scratch/drivers/hid-multitouch" "$scratch/dev"
ln -s "$scratch/drivers/hid-multitouch" "$touchpad/driver"
: >"$scratch/dev/hidraw4"
# The touchpad's Device Configuration collection, as the keyboard reports it.
printf '\x05\x0d\x09\x0e\xa1\x01\x85\x84\x09\x22\xa1\x02\x09\x52\x15\x00\x25\x0a\x75\x08\x95\x01\xb1\x02\xc0\x09\x22\xa1\x00\x85\x85\x09\x57\x09\x58\x75\x01\x95\x02\x25\x01\xb1\x02\x95\x06\xb1\x03\xc0\xc0' \
  >"$scratch/config.rdesc"
cp "$scratch/config.rdesc" "$touchpad/report_descriptor"
touchpad_check() { # $1 = Input Mode, $2 = switch report byte, $3 = reply length
  python - "$package_dir/surface-pro-11-touchpad-mode-sleep" "$scratch" "$@" <<'EOF'
import sys
hook = {'__name__': 'hook'}
exec(open(sys.argv[1]).read(), hook)
scratch, mode, switches, length = sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4], 0), int(sys.argv[5])
hook['HID'], hook['DEV'] = scratch + '/touchpad', scratch + '/dev'
report = {0x84: mode, 0x85: switches}

class Fcntl:
    def ioctl(self, fd, request, buf):
        nr = request & 0xff
        if nr == 0x07:
            buf[1] = report[buf[0]]
            return length
        print(f'set {buf.hex()}')
        return len(buf)

hook['fcntl'] = Fcntl()
try:
    print(hook['check']('0019:045E:0C8D.0005') or 'left alone')
except OSError as e:
    print(f'error {e}')
EOF
}
[[ $(touchpad_check 3 0x17 2) == "left alone" ]] ||
  fail "a touchpad in touchpad mode with both switches on is left alone"
[[ $(touchpad_check 0 0x17 2) == $'set 8403\nset 8517\nresumed in input mode 0 with switches 0x17, restored touchpad mode' ]] ||
  fail "a touchpad in mouse mode is put back in touchpad mode, keeping the rest of the switch report"
[[ $(touchpad_check 3 0x14 2) == $'set 8403\nset 8517\n'* ]] ||
  fail "a touchpad left with its surface and button switches off gets them back"
[[ $(touchpad_check 0 0x17 1) == "error short reply to feature report 0x84" ]] ||
  fail "a short reply to the mode read changes nothing"
printf '\x05\x0d\x09\x0e\xa1\x01\x85\x84\x09\x22\xa1\x02\x09\x52\x15\x00\x25\x0a\x75\x10' >"$touchpad/report_descriptor"
[[ $(touchpad_check 0 0x17 2) == "left alone" ]] ||
  fail "a touchpad whose configuration reports are laid out differently is left alone"

cp "$scratch/config.rdesc" "$touchpad/report_descriptor"
rm -rf "$touchpad/hidraw/hidraw4"
[[ $(SP11_TOUCHPAD_COMPATIBLE="$scratch/denali" SP11_TOUCHPAD_HID="$scratch/touchpad" SP11_TOUCHPAD_SETTLE=0 \
  SP11_TOUCHPAD_TRIES=1 python "$package_dir/surface-pro-11-touchpad-mode-sleep" check 2>&1) == \
  "surface-pro-11-touchpad-mode: 0019:045E:0C8D.0005 gave up: IndexError"* ]] ||
  fail "a touchpad that goes away during the check is reported, not a crash"

grep -q '^MatchBus=bluetooth$' "$package_dir/50-surface-pro-11-flex-keyboard.quirks" &&
  grep -q '^MatchProduct=0x0C7A$' "$package_dir/50-surface-pro-11-flex-keyboard.quirks" &&
  grep -q '^AttrTPKComboLayout=below$' "$package_dir/50-surface-pro-11-flex-keyboard.quirks" ||
  fail "the detached keyboard's touchpad gets palm rejection"
grep -q '^AttrEventCode=-BTN_RIGHT$' "$package_dir/50-surface-pro-11-flex-keyboard.quirks" ||
  fail "the detached keyboard's clickpad hides its right button, like the attached one"
grep -q 'usr/share/libinput/50-surface-pro-11-flex-keyboard.quirks' "$package_dir/PKGBUILD" ||
  fail "the touchpad quirk is installed where libinput reads quirks"

# Pen: docking the Slim Pen pairs it the way Windows does. Bluetooth commands
# are recorded instead of run; the dock is a pipe that collects the key report.
pen_dock() { # $1 = paired before (yes/no), $2 = pen flags, $3 = bonded after pairing (yes/no)
  python - "$package_dir/surface-pro-11-pen-dock" "$scratch" "$@" <<'EOF'
import os, sys
dock = {'__name__': 'dock'}
exec(open(sys.argv[1]).read(), dock)
scratch, paired, flags, bonded = sys.argv[2], sys.argv[3] == 'yes', int(sys.argv[4], 0), sys.argv[5] == 'yes'
dock['LOCK'] = scratch + '/run/flex-autopair.lock'
calls = []

def run(*cmd, timeout=10):
    calls.append(' '.join(cmd))
    if cmd[:2] == ('bluetoothctl', 'info'):
        state = paired if not any(c.startswith('btmgmt pair') for c in calls) else bonded
        return f'\tPaired: {"yes" if state else "no"}\n\tBonded: {"yes" if state else "no"}\n'
    return '\tPairable: no\n' if cmd[:2] == ('bluetoothctl', 'show') else ''

dock['run'] = run
dock['add_remote_oob_tk'] = lambda addr, addr_type, tk: calls.append(f'oob {addr} {addr_type} {len(tk)}') or True
host_le = bytes.fromhex('C4CB76A1AB84')[::-1]
# The pen's 0x6E report as captured: Pen ID, address D0:CE:7D:D7:54:A7 (LSB first), flags.
report = bytes([0x6E, 0x27, 0x8F, 0x61, 0x96]) + bytes.fromhex('D0CE7DD754A7')[::-1] + bytes([flags])
r, w = os.pipe()
dock['pen_docked'](w, report, host_le)
os.close(w)
sent = os.read(r, 64)
for c in calls:
    print(c)
if sent:
    print(f'key report {sent[:12].hex()} +{len(sent) - 12}')
EOF
}
out=$(pen_dock no 0x07 yes)
[[ $out == *"oob D4:05:0B:76:FF:23 2 16"* && $out == *"btmgmt pair -c 3 -t 2 D4:05:0B:76:FF:23"* ]] ||
  fail "a docked pen with no bond is paired at its auto-bond address (reported address XOR host, static random)"
[[ $out == *"key report 6f278f6196a754d77dced001 +16"* ]] ||
  fail "the pen gets its ID, address, address type and a 16-byte key through the dock"
[[ $out == *"bluetoothctl trust D4:05:0B:76:FF:23"* && $out == *"pairable on"* && $out == *"pairable off"* ]] ||
  fail "a paired pen is trusted and the adapter goes back to not pairable"
[[ $out == *"paired the pen D4:05:0B:76:FF:23"* ]] || fail "a successful pairing is logged"
out=$(pen_dock yes 0x07 yes)
[[ $out != *"btmgmt pair"* && $out != *"remove"* && $out != *"key report"* ]] ||
  fail "a pen that is paired and knows this host is left alone"
out=$(pen_dock yes 0x03 yes)
[[ $out == *"bluetoothctl remove D4:05:0B:76:FF:23"* && $out == *"btmgmt pair"* ]] ||
  fail "a pen that no longer knows this host (paired elsewhere since) is paired again"
out=$(pen_dock no 0x07 no)
[[ $out == *"dock it again to retry"* && $out != *"trust"* ]] ||
  fail "a failed pairing is reported and retried on the next dock, not trusted"
out=$(pen_dock no 0x05 yes)
[[ $out == *"btmgmt pair -c 3 -t 2 D0:CE:7D:D7:54:A7"* ]] ||
  fail "a pen without the auto-bond flag pairs at the address it reports"
# The dock's reports, as captured, drive the docked-state file the desktop reads.
out=$(python - "$package_dir/surface-pro-11-pen-dock" "$scratch" <<'EOF'
import os, stat, sys
dock = {'__name__': 'dock'}
exec(open(sys.argv[1]).read(), dock)
dock['DOCKED'] = sys.argv[2] + '/run/pen-docked'
dock['pen_docked'] = lambda fd, report, host_le: print('pair', end=' ')
dock['set_docked'](False)
# In range when the service starts, removed, idle, inserted, idle.
for report in ('6e278f6196a754d77dced007', '5c0902', '5c0000', '5c0904', '5c0000'):
    dock['dock_report'](None, bytes.fromhex(report), bytes(6))
    print(open(dock['DOCKED']).read().strip(), end=' ')
print(oct(stat.S_IMODE(os.stat(dock['DOCKED']).st_mode)))
EOF
)
[[ $out == "pair 1 0 0 1 1 0o644" ]] ||
  fail "the pen counts as docked when the dock reports it in range or inserted, and undocked when removed"
# Starting up: the dock is a FIFO that reports a docked pen, or nothing.
pen_dock_start() { # $1 = state before, $2 = report the dock sends at set-up (or "none")
  python - "$package_dir/surface-pro-11-pen-dock" "$scratch" "$@" <<'EOF'
import os, sys, threading, time
dock = {'__name__': 'dock'}
exec(open(sys.argv[1]).read(), dock)
scratch, before, report = sys.argv[2:5]
dock['DOCKED'] = scratch + '/run/pen-docked'
fifo = scratch + '/dock-' + report
os.mkfifo(fifo)
writer = os.open(fifo, os.O_RDWR)
dock['set_docked'](before == '1')
dock['pen_docked'] = lambda fd, report, host_le: None
written = []
set_docked = dock['set_docked']
dock['set_docked'] = lambda docked: written.append(int(docked)) or set_docked(docked)
dock['set_feature'] = lambda fd, rid, payload: report != 'none' and os.write(writer, bytes.fromhex(report))
threading.Thread(target=dock['watch'], args=(fifo, bytes(6)), daemon=True).start()
time.sleep(2.5)
print(' '.join(map(str, written)) or '-', open(dock['DOCKED']).read().strip())
EOF
}
[[ $(pen_dock_start 1 none) == "0 0" ]] ||
  fail "a dock that reports no pen once set up is empty"
[[ $(pen_dock_start 1 6e278f6196a754d77dced007) == "1 1" ]] ||
  fail "restarting with the pen docked never marks it undocked in between"
[[ -z $(SP11_PEN_COMPATIBLE="$scratch/other" python "$package_dir/surface-pro-11-pen-dock" 2>&1) ]] ||
  fail "the pen dock helper does nothing on other hardware"
grep -qx 'ConditionFirmware=device-tree-compatible(microsoft,denali-oled)' "$package_dir/surface-pro-11-pen-dock.service" ||
  fail "the pen dock service runs only on the Surface Pro 11 OLED"
grep -q 'ENV{HID_NAME}=="\*045E:0C8E\*".*start surface-pro-11-pen-dock.service' <(tr -d '\\\n' <"$package_dir/70-surface-pro-11-flex-keyboard.rules") ||
  fail "the pen dock appearing starts the pen dock service"

echo "ok - surface-pro-11-support verifies its hardware setup"
