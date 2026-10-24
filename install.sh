#!/bin/bash
# Add the surface-pro-11 package repository to an Omarchy install on a
# Surface Pro 11 and install everything it carries.
#
#   curl -fsSL https://raw.githubusercontent.com/turbineBMW/surface-pro-11-omarchy/main/install.sh | bash
#
# The repository sits above [omarchy] in /etc/pacman.conf, so the packages it
# carries replace Omarchy's until Omarchy ships the same fixes. Run with
# --remove to take it out again; the packages stay until Omarchy updates them.
set -euo pipefail

REPO_NAME=surface-pro-11
GITHUB=turbineBMW/surface-pro-11-omarchy
SERVER="https://github.com/$GITHUB/releases/download/\$arch"
KEY_URL="https://raw.githubusercontent.com/$GITHUB/main/keys/surface-pro-11.asc"
KEY_FINGERPRINT=6CAC3F8AE94AC7BDCFB7A9017C8D01DD008051AB
PACMAN_CONF=${PACMAN_CONF:-/etc/pacman.conf}
BEGIN="# BEGIN SURFACE PRO 11 REPOSITORY"
END="# END SURFACE PRO 11 REPOSITORY"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'surface-pro-11: %s\n' "$*" >&2; exit 1; }

remove_section() {
  awk -v begin="$BEGIN" -v end="$END" '
    $0 == begin { skip = 1; next }
    skip && $0 == end { skip = 0; next }
    !skip { print }
  ' "$PACMAN_CONF"
}

if [[ ${1:-} == --remove ]]; then
  tmp=$(mktemp)
  remove_section >"$tmp"
  sudo install -m644 "$tmp" "$PACMAN_CONF"
  rm -f "$tmp"
  say "Removed the $REPO_NAME repository from $PACMAN_CONF."
  exit 0
fi

[[ $(uname -m) == aarch64 ]] || die "this is for the Surface Pro 11 (aarch64) only"
compatible=$(tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null || true)
if ! grep -qx 'microsoft,denali-oled' <<<"$compatible" && [[ ${1:-} != --force ]]; then
  die "only the Surface Pro 11 X Elite OLED is tested (this is: ${compatible%%$'\n'*}); --force to continue anyway"
fi
[[ -d /usr/share/omarchy ]] || die "install Omarchy first"
grep -q '^\[omarchy\]' "$PACMAN_CONF" || die "no [omarchy] repository in $PACMAN_CONF"
[[ -n $KEY_FINGERPRINT ]] || die "this copy of install.sh has no signing key yet"

say "Trusting the repository's signing key $KEY_FINGERPRINT"
key=$(mktemp)
trap 'rm -f "$key"' EXIT
curl -fsSL "$KEY_URL" -o "$key"
got=$(gpg --show-keys --with-colons "$key" | awk -F: '/^fpr:/ { print $10; exit }')
[[ $got == "$KEY_FINGERPRINT" ]] || die "downloaded key is $got, expected $KEY_FINGERPRINT"
sudo pacman-key --add "$key"
sudo pacman-key --lsign-key "$KEY_FINGERPRINT"

say "Adding [$REPO_NAME] above [omarchy] in $PACMAN_CONF"
tmp=$(mktemp)
remove_section | awk -v begin="$BEGIN" -v end="$END" -v name="$REPO_NAME" -v server="$SERVER" '
  !done && $0 == "[omarchy]" {
    print begin
    print "[" name "]"
    print "Server = " server
    print end
    print ""
    done = 1
  }
  { print }
' >"$tmp"
sudo install -m644 "$tmp" "$PACMAN_CONF"
rm -f "$tmp"

say "Installing the Surface Pro 11 packages"
# A full upgrade, as Omarchy does: never a partial one. The repository's
# packages replace Omarchy's builds of the same name.
sudo pacman -Syu --needed omarchy-surface-pro-11

say "Done. Reboot to start the new kernel."
