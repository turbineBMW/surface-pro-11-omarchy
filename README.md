# Surface Pro 11 for Omarchy

A pacman repository that adds Surface Pro 11 support to a stock
[Omarchy](https://omarchy.org) install while that support is still in review
upstream. It is a community add-on by a member of Omarchy's Snapdragon team,
not an official Omarchy project.

Tested on the Surface Pro 11 with Snapdragon X Elite and OLED display
(`microsoft,denali-oled`). The LCD and X Plus models use other device trees
and are not supported yet.

## Install

On a Surface Pro 11 that already runs Omarchy:

```sh
curl -fsSL https://raw.githubusercontent.com/turbineBMW/surface-pro-11-omarchy/main/install.sh | bash
```

This trusts the repository's signing key, adds `[surface-pro-11]` above
`[omarchy]` in `/etc/pacman.conf`, and installs `omarchy-surface-pro-11`.
From then on `omarchy-update` keeps everything current. To stop using the
repository:

```sh
curl -fsSL https://raw.githubusercontent.com/turbineBMW/surface-pro-11-omarchy/main/install.sh | bash -s -- --remove
```

The packages stay installed until Omarchy publishes newer versions.

## Face unlock

Open Setup > Security > Face Unlock in the Omarchy menu (or the Face Unlock
app, or run `surface-pro-11-face-setup`) and look at the camera. It sets up
facelock for the IR camera and adds face unlock to the lock screen only;
Remove > Security > Face Unlock takes it off again. The lock starts a scan when
it locks, when you touch the keyboard or mouse, and after a resume, at most
three times each, and an empty Enter scans once more. The password always
works. The lock screen's face flow follows
[omarchy#11612](https://github.com/omacom/omarchy/pull/11612) and its review.

## Windows

If Windows is still installed, installing the repository adds it to the
Limine boot menu below Omarchy, and System > Boot to Windows (also a
launcher entry) restarts into it once. That sets the firmware's one-time
BootNext to Windows Boot Manager, so Windows starts exactly as it does on
its own and BitLocker sees the boot path it expects; the next restart comes
back to Omarchy. It asks for your password once per few minutes.

## Plugins

The Lock Screen, Power and Display panels are Omarchy's own, rebuilt with one
Surface addition each (face unlock, charge limit, auto-brightness) whenever Omarchy updates them (a pacman hook applies a small
patch to the installed built-in). If an update breaks a patch, the previous
build stays in use and pacman prints a warning. The rebuilt panels load
when the shell restarts, which `omarchy-update` does after every update. The
corner plugin is standalone.

At login, each plugin is linked into `~/.config/omarchy/plugins` and switched
on once with `omarchy plugin enable`; a plugin you switch off or remove stays
off. If you already run your own copy of the Power or Display panel, the
Surface one is left off. Windows get 12 px circular corners from
`~/.local/state/omarchy/toggles/hypr/surface-pro-11-rounding.lua`; delete it
to go back to the theme's corners.

## What it carries

Only packages that differ from Omarchy's. Each one leaves this repository
once Omarchy ships the same fixes.

| Package | Version | Upstream | Adds |
|---|---|---|---|
| `linux-omarchy` | 7.3-25.3 | [omarchy-pkgs#1698](https://github.com/omacom/omarchy-pkgs/pull/1698), which Omarchy will publish as `7.3-25` (its `7.3-24` plus 2217), plus 2221 and the `quiet-efivarfs` initramfs hook, which no Omarchy PR has yet, plus the hardware camera ISP (3300–3370) | Suspend no longer hard-locks when it follows a resume closely (2217, keeps the Surface EC's UART link alive), audio over DisplayPort to a monitor or dock (2221), no efivarfs mount error flashing during boot, and the camera's hardware ISP (the runtime is `qualcomm-isp-runtime`) |
| `surface-pro-11-support` | 1-5.3 | [omarchy-pkgs#1528](https://github.com/omacom/omarchy-pkgs/pull/1528) and master's 1-4 (UCM in its own folder, compressed firmware), then pen pairing, speakers, DisplayPort audio, monitor brightness and panel self-refresh | Touchpad mode after resume, Bluetooth palm rejection, Slim Pen pairing, Windows speaker tuning, audio over DisplayPort, external monitor brightness following the screen's, panel self-refresh (PSR1) on the internal display |
| `omarchy-surface-pro-11` | 1-6 | [omarchy#14390](https://github.com/omacom/omarchy/pull/14390) | The board setup a #14390 install does: OLED device tree pin, panel and keyboard before disk unlock, light sensor |
| `surface-pro-11-plugins` | 1-11 | | Omarchy shell plugins, switched on once per user: lock screen with face unlock, battery charge-limit toggle in the Power panel, ambient-light auto-brightness in the Display panel, rounded screen corners, and windows rounded to match the display in every theme |
| `surface-pro-11-face` | 1-6 | | Face unlock with the IR camera: camera wiring, facelock quirk, `surface-pro-11-face-setup` |
| `facelock` | 0.2.1.r153-3 | [tyvsmith/facelock](https://github.com/tyvsmith/facelock) `main` (no release has IR cameras behind CAMSS yet) | Face authentication for PAM |
| `onnxruntime-bin` | 1.29.0 | Arch Linux ARM has no onnxruntime | Microsoft's aarch64 build, for facelock |
| `qualcomm-isp-runtime` | 0.1-26 | [turbineBMW/qualcomm-isp](https://github.com/turbineBMW/qualcomm-isp) `v0.1-26` | The front camera, and the rear camera once its board data is prepared, through the hardware ISP (ICP/IPE), published to PipeWire at 4K down to 640x360 with the rear's ten-bit denoising, motion-safe temporal filtering, exposure and colour tuned from the Surface's own Windows camera data, and a `publisher.d` hook for filters such as automatic framing; needs `linux-omarchy` 7.3-25.3 or later and that camera data |
| `qualcomm-isp-autoframe` | 0.1-1 | [turbineBMW/qualcomm-isp](https://github.com/turbineBMW/qualcomm-isp) `v0.1-20` | Automatic framing for the front camera, as Windows Studio Effects does it: a face detector follows you and the picture is cropped around you from the ISP's 4K output to 1080p; `isp-autoframe off` for the full view, `isp-autoframe plugin install` for the bar widget; installed on request, not by `omarchy-surface-pro-11` |
| `qualcomm-isp-libcamera` | 0.7.2-8 | [turbineBMW/qualcomm-isp](https://github.com/turbineBMW/qualcomm-isp) `v0.1-19` | A private libcamera (`/usr/lib/qualcomm-isp/libcamera`) for the runtime's capture, with the rear OV13858 sensor, paired RAW statistics and its gain range bounded to what the sensor delivers; the system libcamera stays |
| `surface-pro-11-windows` | 1-4 | | Windows in the Limine boot menu (below Omarchy) and System > Boot to Windows |
| `surface-pro-11-keyring` | 1-1 | | This repository's signing key |

No firmware is in this repository. The Surface's DSP, GPU and Wi-Fi firmware
belong to Microsoft and Qualcomm and come from your own Windows install
through Omarchy's `qcom-firmware-extract`.

## Installer

`bin/build-iso` builds Omarchy's aarch64 installer with these packages in
it, and `sudo bin/make-usb ISO DEVICE --firmware FILEREPOSITORY` writes it to
a stick with an OMARCHY_FW partition holding the Surface's firmware from a
Windows driver store, so the installer never reads the (possibly
BitLocker-encrypted) Windows partition. The image itself carries no firmware.

## Versions

A carried package uses the pkgrel Omarchy will give the change, plus `.N`:
`7.3-25.1` is our first build of the kernel Omarchy will publish as `7.3-25`
(its `7.3-24` plus 2217, omarchy-pkgs#1698), not a build on top of Omarchy's
`7.3-24`.

Omarchy's version alone doesn't say whether it has our fixes: it publishes
new kernel pkgrels several times a day, with or without them. So
`bin/check-upstream` looks up each local source file of a carried package
(patches, config, hooks) in omarchy-pkgs' recipe and its history, and lists
those Omarchy has never had. While there are any, the package is "carried",
or "carried, behind" once Omarchy publishes a newer version than our base,
which is a cue to rebase, not to retire. When Omarchy has published every
one of them, the package is "caught up": check Omarchy's build (fixes we
make by leaving one of Omarchy's patches out are not seen by the check), then delete the package's directory here, and pacman
moves to Omarchy's next release.

## Maintaining

```sh
bin/build [PKGBASE...]    # build into out/aarch64, skipping versions already there
bin/check-upstream        # compare with Omarchy edge
bin/publish fetch|upload  # sync out/aarch64 with the GitHub release
bin/export-key FPR        # put the signing key into the keyring package and install.sh
```

CI builds in Omarchy's own builder image on GitHub's arm64 runners, only
rebuilding packages whose version changed, and publishes the release
`aarch64`, which is the repository pacman downloads from. It needs the
`SIGNING_KEY` secret (armored private signing key, no passphrase) and the
`SIGN_KEY` variable (its fingerprint). A daily job fails when Omarchy has
published every fix a carried package carries, and warns when a carried
package is behind Omarchy's version.

What comes next is in [docs/ROADMAP.md](docs/ROADMAP.md).
