# Roadmap

Decided 2026-10-24: stock Omarchy plus this add-on repository, never a fork.
Everything below is a package here or a tool that installs one.

## 1. Package repository (this commit)

Kernel, support package, board setup, keyring, CI, `install.sh`.

Before it goes public:

- [ ] Create a signing key; `bin/export-key`; add `SIGNING_KEY`/`SIGN_KEY` to the GitHub repository.
- [ ] Tell the Dragon team in Basecamp before announcing anything.
- [ ] First CI run: confirm the kernel finishes inside the 340-minute limit on
      the 4-core arm64 runner (otherwise build it here and upload by hand).
- [ ] Install it on the SP11 through `install.sh` from the published release.

## 2. Plugins on by default

Omarchy loads third-party plugins only from `~/.config/omarchy/plugins` and
only once they are listed in `shell.json`. New package
`surface-pro-11-plugins`:

- pen: Slim Pen battery OSD, silent while docked (reads
  `/run/surface-pro-11-support/pen-docked`)
- monitor: brightness slider and ambient-light auto-brightness
- battery and power: low-battery warning, charge limit, power profile
- lock: lock screen with IR face unlock; needs `facelock` (upstream
  tyvsmith/facelock#396 merged) and the IR camera package
- corners: rounded fills at the screen corners, matching the panel's radius

Plugins install to `/usr/share/surface-pro-11-plugins/<id>`. A user service
links each into `~/.config/omarchy/plugins` and adds it to `shell.json` once.
A state file records that, so a plugin the user switches off stays off. An
existing directory with the same id (a hand-installed copy) is left alone.

Upstream proposal: a system plugin directory scanned next to the user one,
which would remove the linking step.

Themes: one Hyprland drop-in rounds windows to match the display's corners
for every theme, so no theme needs editing. Everything else stays stock.

## 3. Windows next to Omarchy

- Limine entry for Windows. Its boot manager is on its own EFI partition
  (p1), not Omarchy's, so `FIND_BOOTLOADERS` does not find it today. Point
  the entry at that partition by GUID.
- "Reboot to Windows" in the Omarchy menu and as a desktop entry: set the
  firmware's `BootNext` to Windows Boot Manager and reboot. Windows then
  starts exactly as it does on its own, which keeps BitLocker's measurements
  unchanged. A chainload through Limine would change them.
  One `efibootmgr` write; never bulk EFI variable writes while Hyprland runs.

## 4. Installer ISO

Omarchy's Dragon ISO with this repository added, firmware-free. The
installer reads firmware and sensor configuration from the stick's `SP11FW`
partition the Windows creator fills, falling back to the Windows partition.
Both install modes stay: whole disk, or free space next to Windows.

## 5. Windows USB creator

Avalonia (C#), a single win-arm64 executable, styled like Omarchy. It is
the GUI for `sp11/public/scripts/sp11-usb-creator.ps1`, which already does
the work:

1. Download the ISO and verify its checksum.
2. Collect the firmware and the light-sensor configuration from the running
   Windows. Windows has the BitLocker volume unlocked, so BitLocker never
   has to be turned off.
3. Write the ISO to the stick and the collected files to `SP11FW`.
4. If Omarchy will sit next to Windows: shrink C: (works with BitLocker on).
5. Prepare for Secure Boot off: show and save the BitLocker recovery key,
   then `Suspend-BitLocker -RebootCount 3`. Turning Secure Boot off changes
   what BitLocker measures, and without this Windows asks for the recovery
   key on its next start.
6. Explain the firmware steps (Secure Boot off, boot from USB).

Developed and screenshot on Linux; published for win-arm64.
