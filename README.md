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
| `linux-omarchy` | 7.3-1.14 | [omarchy-pkgs#1417](https://github.com/omacom/omarchy-pkgs/pull/1417) (Linux 7.3) plus one patch | Suspend no longer hard-locks when it follows a resume closely (2217, keeps the Surface EC's UART link alive) |
| `surface-pro-11-support` | 1-4.1 | [omarchy-pkgs#1528](https://github.com/omacom/omarchy-pkgs/pull/1528), then pen pairing and speakers | Touchpad mode after resume, Bluetooth palm rejection, Slim Pen pairing, Windows speaker tuning |
| `omarchy-surface-pro-11` | 1-4 | [omarchy#14390](https://github.com/omacom/omarchy/pull/14390) | The board setup a #14390 install does: OLED device tree pin, panel and keyboard before disk unlock, light sensor |
| `surface-pro-11-plugins` | 1-4 | | Omarchy shell plugins, switched on once per user: lock screen with face unlock, battery charge-limit toggle in the Power panel, ambient-light auto-brightness in the Display panel, rounded screen corners, and windows rounded to match the display in every theme |
| `surface-pro-11-face` | 1-5 | | Face unlock with the IR camera: camera wiring, facelock quirk, `surface-pro-11-face-setup` |
| `facelock` | 0.2.1.r153-2 | [tyvsmith/facelock](https://github.com/tyvsmith/facelock) `main` (no release has IR cameras behind CAMSS yet) | Face authentication for PAM |
| `onnxruntime-bin` | 1.29.0 | Arch Linux ARM has no onnxruntime | Microsoft's aarch64 build, for facelock |
| `surface-pro-11-windows` | 1-2 | | Windows in the Limine boot menu (below Omarchy) and System > Boot to Windows |
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
`7.3-1.13` is the 13th build on top of Omarchy's `7.3-1`. When Omarchy
publishes `7.3-1` or later, `bin/check-upstream` reports the package as
caught up. Once Omarchy's build has every fix ours carries, the package's
directory is deleted here and pacman moves to Omarchy's next release.

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
caught up with a carried package.

What comes next is in [docs/ROADMAP.md](docs/ROADMAP.md).
