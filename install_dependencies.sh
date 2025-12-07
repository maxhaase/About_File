#!/usr/bin/env bash
# Project: About_File
# Script : install_deps.sh
# Desc   : Install dependencies for fileinfo.sh on common Linux distributions.
# This installer covers: Ubuntu/Debian (and derivatives), Fedora, RHEL/CentOS/Rocky/Alma/Amazon Linux, openSUSE/SLE, Arch/Manjaro, Alpine, Void, and Gentoo (best-effort categories).

#######################
# Author: Max Haase
# maxhaase@gmail.com
#######################

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./install_deps.sh

Description:
  Detects your Linux distribution and installs the dependencies required by fileinfo.sh:
    - coreutils, util-linux, file
    - e2fsprogs (debugfs), xfsprogs (xfs_io)
    - acl (getfacl), attr (getfattr), lsattr (via e2fsprogs)
    - unzip
    - exiftool
    - xmlstarlet
    - perl
    - audit/ausearch (auditd on Debian/Ubuntu; audit on RPM distros)

Run as root, or with sudo privileges. No arguments are required.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi

require_root() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo --preserve-env=HOME,BASHOPTS,PATH "$0" "$@"
    else
      echo "ERROR: Please run as root or install 'sudo' first." >&2
      exit 1
    fi
  fi
}

require_root "$@"

# Detect OS
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "ERROR: /etc/os-release not found; unsupported system." >&2
  exit 1
fi

# Default lists (generic names)
BASE_PKGS=(coreutils util-linux file unzip perl)
FS_PKGS=(e2fsprogs xfsprogs)
META_PKGS=(xmlstarlet)
ACL_ATTR_PKGS=(acl attr)
AUDIT_DEB=(auditd)
AUDIT_RPM=(audit)
# exiftool varies by distro
EXIF_DEB=(libimage-exiftool-perl)
EXIF_RPM=(perl-Image-ExifTool)
EXIF_ZYPP=(exiftool perl-Image-ExifTool)
EXIF_APK=(perl-image-exiftool)
EXIF_PAC=(exiftool)
EXIF_XBPS=(exiftool)
EXIF_EMERGE=(dev-perl/Image-ExifTool)

install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    "${BASE_PKGS[@]}" "${FS_PKGS[@]}" "${ACL_ATTR_PKGS[@]}" \
    "${EXIF_DEB[@]}" "${META_PKGS[@]}" "${AUDIT_DEB[@]}"
}

install_dnf_or_yum() {
  local mgr=dnf
  command -v dnf >/dev/null 2>&1 || mgr=yum

  # Enable EPEL & CRB/PowerTools where appropriate (for xmlstarlet/exiftool on RHEL/EL).
  if [[ "${ID_LIKE:-}" =~ rhel|centos|fedora || "$ID" =~ (rhel|centos|rocky|almalinux|ol|amzn) ]]; then
    if command -v dnf >/dev/null 2>&1; then
      if [[ "$ID" =~ (rhel|almalinux|rocky|centos|ol) ]]; then
        # EL9 uses crb; EL8 uses powertools
        if grep -qE '^VERSION_ID="?9' /etc/os-release; then
          dnf config-manager --set-enabled crb || true
        else
          dnf config-manager --set-enabled powertools || true
        fi
      fi
      $mgr -y install epel-release || true
    else
      $mgr -y install epel-release || true
    fi
  fi

  $mgr -y install \
    "${BASE_PKGS[@]}" "${FS_PKGS[@]}" "${ACL_ATTR_PKGS[@]}" \
    "${EXIF_RPM[@]}" "${META_PKGS[@]}" "${AUDIT_RPM[@]}"
}

install_zypper() {
  zypper -n refresh
  # try both names for exiftool; zypper ignores missing ones gracefully if present later
  zypper -n install \
    "${BASE_PKGS[@]}" "${FS_PKGS[@]}" "${ACL_ATTR_PKGS[@]}" \
    "${EXIF_ZYPP[@]}" "${META_PKGS[@]}" audit
}

install_pacman() {
  pacman -Sy --noconfirm
  pacman -S --needed --noconfirm \
    "${BASE_PKGS[@]}" "${FS_PKGS[@]}" "${ACL_ATTR_PKGS[@]}" \
    "${EXIF_PAC[@]}" "${META_PKGS[@]}" audit
}

install_apk() {
  apk update
  apk add --no-cache \
    "${BASE_PKGS[@]}" "${FS_PKGS[@]}" "${ACL_ATTR_PKGS[@]}" \
    "${EXIF_APK[@]}" "${META_PKGS[@]}" audit
}

install_xbps() {
  xbps-install -Syu || true
  xbps-install -Sy \
    "${BASE_PKGS[@]}" "${FS_PKGS[@]}" "${ACL_ATTR_PKGS[@]}" \
    "${EXIF_XBPS[@]}" "${META_PKGS[@]}" audit
}

install_emerge() {
  # Gentoo (best-effort names)
  emerge --sync || true
  emerge --ask=n --quiet \
    sys-apps/coreutils sys-apps/util-linux sys-apps/file \
    app-arch/unzip sys-fs/e2fsprogs sys-fs/xfsprogs \
    sys-apps/acl sys-apps/attr dev-lang/perl \
    app-text/xmlstarlet app-admin/audit dev-perl/Image-ExifTool
}

echo "Detected system: ID=${ID:-?} ID_LIKE=${ID_LIKE:-?} VERSION_ID=${VERSION_ID:-?}"

case "$ID" in
  ubuntu|debian|raspbian|linuxmint|pop|neon|zorin)
    install_apt
    ;;
  fedora)
    install_dnf_or_yum
    ;;
  rhel|centos|rocky|almalinux|ol|amzn)
    install_dnf_or_yum
    ;;
  opensuse*|sles|sled|suse)
    install_zypper
    ;;
  arch|manjaro|endeavouros|garuda)
    install_pacman
    ;;
  alpine)
    install_apk
    ;;
  void)
    install_xbps
    ;;
  gentoo)
    install_emerge
    ;;
  *)
    # Try ID_LIKE fallbacks
    if [[ "${ID_LIKE:-}" =~ debian ]]; then
      install_apt
    elif [[ "${ID_LIKE:-}" =~ rhel|centos|fedora ]]; then
      install_dnf_or_yum
    elif [[ "${ID_LIKE:-}" =~ suse ]]; then
      install_zypper
    elif [[ "${ID_LIKE:-}" =~ arch ]]; then
      install_pacman
    else
      echo "ERROR: Unsupported or unrecognized distribution ($ID). Edit this script to add support." >&2
      exit 2
    fi
    ;;
esac

echo
echo "All done. Verifying key tools:"
for bin in stat findmnt df debugfs xfs_io getfacl getfattr lsattr sha256sum sha512sum file exiftool xmlstarlet unzip ausearch; do
  if command -v "$bin" >/dev/null 2>&1; then
    printf "  %-12s  OK (%s)\n" "$bin" "$(command -v "$bin")"
  else
    printf "  %-12s  MISSING (optional)\n" "$bin"
  fi
done

echo
echo "Tip: If 'exiftool' or 'xmlstarlet' is missing on RHEL/EL, ensure EPEL is enabled and try again."













