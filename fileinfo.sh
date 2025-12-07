#!/usr/bin/env bash
# Project: About_File
# Script : fileinfo.sh
# Desc   : Forensics-style file inventory: path/FS, stat (UTC), low-level inode times,
#          ACLs/xattrs/attrs, hashes, type, DOCX metadata (EXIF + core.xml/app.xml),
#          hardlinks, mount options, and audit logs (if available).

#######################
# Author: Max Haase
# maxhaase@gmail.com
#######################

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  fileinfo.sh <path-to-file>

Description:
  Prints a comprehensive, forensics-style report for the given file:
  - Resolved path, filesystem, mount options
  - Full stat in UTC (including birth time if supported)
  - Low-level inode times (ext4 via debugfs, xfs via xfs_io)
  - ACLs, extended attributes, immutable flags
  - SHA-256 and SHA-512 hashes
  - File type (via 'file -k')
  - DOCX metadata (exiftool; and core.xml/app.xml via xmlstarlet or Perl fallback)
  - Hardlinks (same inode)
  - Mount options (atime policy)
  - Audit log lookups (if auditd/ausearch available)

Example:
  ./fileinfo.sh /home/max/somefile.docx
USAGE
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---- argument & existence checks ----
if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

F="$1"
if [[ ! -e "$F" ]]; then
  echo "ERROR: File not found: $F" >&2
  exit 2
fi

# Resolve absolute path (follows symlinks)
R="$(readlink -f -- "$F" 2>/dev/null || true)"
[[ -n "${R:-}" ]] || R="$F"

echo "== RESOLVE & FS =="
echo "path:$R"

# Filesystem device, type, and mount options
if have findmnt; then
  findmnt -no SOURCE,FSTYPE,OPTIONS --target "$R" || true
fi
df -T "$R" || true

# ---- STAT (UTC) including birth time if available ----
echo
echo "== STAT (UTC) =="
TZ=UTC stat -c $'path:%n\ninode:%i\ntype:%F\nsize:%s bytes\nblocks:%b\nlinks:%h\nperms:%A (%a)\nuid:%u (%U)\ngid:%g (%G)\natime:%x (%X)\nmtime:%y (%Y)\nctime:%z (%Z)\nbtime:%w (%W)' "$R" || true

# ---- LOW-LEVEL INODE TIMES by FS (ext4/xfs) ----
echo
echo "== LOW-LEVEL INODE TIMES =="
FS="$(findmnt -no FSTYPE --target "$R" 2>/dev/null || echo "")"
DEV="$(findmnt -no SOURCE --target "$R" 2>/dev/null || echo "")"
INO="$(ls -li -- "$R" 2>/dev/null | awk '{print $1}')"

case "$FS" in
  ext4)
    if have debugfs; then
      # crtime=creation; ctime=metadata change; mtime=content write; atime=last access
      sudo debugfs -R "stat <$INO>" "$DEV" | egrep -i 'crtime|ctime|mtime|atime' || true
    else
      echo "debugfs not installed; skip ext4 low-level times."
    fi
    ;;
  xfs)
    if have xfs_io; then
      xfs_io -c "stat" "$R" | egrep -i 'btime|crtime|mtime|atime|ctime|ino|size' || true
    else
      echo "xfs_io not installed; skip xfs low-level times."
    fi
    ;;
  *)
    echo "No specialized low-level time tool for $FS; rely on STAT above."
    ;;
esac

# ---- ACLs, Extended Attributes, Immutable Flags ----
echo
echo "== ACLS / XATTRS / ATTRS =="
if have getfacl; then
  getfacl -p -- "$R" || true
else
  echo "getfacl not installed."
fi

if have getfattr; then
  # Dump all xattrs in hex to preserve raw values
  getfattr -d -m- -e hex -- "$R" 2>/dev/null || echo "(no xattrs)"
else
  echo "getfattr not installed."
fi

if have lsattr; then
  lsattr -a -- "$R" 2>/dev/null || true
else
  echo "lsattr not installed."
fi

# ---- Cryptographic Hashes ----
echo
echo "== HASHES =="
sha256sum -- "$R" || true
sha512sum -- "$R" || true

# ---- File Type ----
echo
echo "== FILE TYPE =="
file -k -- "$R" || true

# ---- EXIFTOOL (DOCX and general container metadata) ----
echo
echo "== EXIFTOOL (DOCX META) =="
if have exiftool; then
  exiftool -- "$R" 2>/dev/null | egrep -i 'Create|Modify|Author|Application|Company|Title|Revision|Producer|Creator|Pages' || echo "(no EXIF metadata or exiftool did not return fields)"
else
  echo "exiftool not installed."
fi

# ---- DOCX core.xml/app.xml extraction ----
# Prefer xmlstarlet (namespaces), else Perl regex fallback on unzipped XML.
echo
echo "== DOCX core.xml/app.xml =="
is_zip=0
if unzip -l -- "$R" >/dev/null 2>&1; then
  is_zip=1
fi

if [[ $is_zip -eq 1 ]]; then
  if have xmlstarlet; then
    # Namespace-aware extraction from core.xml and app.xml
    if unzip -p -- "$R" docProps/core.xml >/dev/null 2>&1; then
      echo "-- core.xml --"
      unzip -p -- "$R" docProps/core.xml 2>/dev/null \
      | xmlstarlet sel \
          -N cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
          -N dc="http://purl.org/dc/elements/1.1/" \
          -N dcterms="http://purl.org/dc/terms/" \
          -t \
          -v 'concat("created:", normalize-space(/cp:coreProperties/dcterms:created))' -n \
          -v 'concat("modified:", normalize-space(/cp:coreProperties/dcterms:modified))' -n \
          -v 'concat("creator:", normalize-space(/cp:coreProperties/dc:creator))' -n \
          -v 'concat("title:", normalize-space(/cp:coreProperties/dc:title))' -n || true
    fi
    if unzip -p -- "$R" docProps/app.xml >/dev/null 2>&1; then
      echo "-- app.xml --"
      unzip -p -- "$R" docProps/app.xml 2>/dev/null \
      | xmlstarlet sel \
          -t \
          -v 'concat("application:", normalize-space(//Application))' -n \
          -v 'concat("total_edit_minutes:", normalize-space(//TotalTime))' -n \
          -v 'concat("pages:", normalize-space(//Pages))' -n || true
    fi
  else
    # Perl fallback (tolerant to namespaces and newlines)
    if unzip -p -- "$R" docProps/core.xml >/dev/null 2>&1; then
      echo "-- core.xml (Perl fallback) --"
      unzip -p -- "$R" docProps/core.xml 2>/dev/null \
      | perl -0777 -ne '
          ($c) = /<dcterms:created[^>]*>(.*?)<\/dcterms:created>/s; $c//=q{};
          ($m) = /<dcterms:modified[^>]*>(.*?)<\/dcterms:modified>/s; $m//=q{};
          ($a) = /<dc:creator>(.*?)<\/dc:creator>/s;                 $a//=q{};
          ($t) = /<dc:title>(.*?)<\/dc:title>/s;                     $t//=q{};
          $c=~s/\s+/ /g; $m=~s/\s+/ /g; $a=~s/\s+/ /g; $t=~s/\s+/ /g;
          print "created:$c\n" if length $c;
          print "modified:$m\n" if length $m;
          print "creator:$a\n" if length $a;
          print "title:$t\n" if length $t;
        ' || true
    fi
    if unzip -p -- "$R" docProps/app.xml >/dev/null 2>&1; then
      echo "-- app.xml (Perl fallback) --"
      unzip -p -- "$R" docProps/app.xml 2>/dev/null \
      | perl -0777 -ne '
          ($app) = /<Application>(.*?)<\/Application>/s;     $app//=q{};
          ($mins)= /<TotalTime>(.*?)<\/TotalTime>/s;         $mins//=q{};
          ($pgs) = /<Pages>(.*?)<\/Pages>/s;                 $pgs//=q{};
          $app=~s/\s+/ /g; $mins=~s/\s+/ /g; $pgs=~s/\s+/ /g;
          print "application:$app\n" if length $app;
          print "total_edit_minutes:$mins\n" if length $mins;
          print "pages:$pgs\n" if length $pgs;
        ' || true
    fi
  fi
else
  echo "(Not a ZIP container; skipping DOCX internals)"
fi

# ---- Hardlinks (same inode on the same filesystem) ----
echo
echo "== HARDLINKS (same inode) =="
MNT="$(df --output=target "$R" | tail -1)"
# -xdev confines search to the same filesystem (inode uniqueness)
find "$MNT" -xdev -samefile "$R" 2>/dev/null || true

# ---- Mount options affecting atime policy ----
echo
echo "== MOUNT OPTIONS (atime policy) =="
findmnt -no OPTIONS --target "$R" 2>/dev/null || true

# ---- Audit logs (if auditd enabled) ----
echo
echo "== AUDITD (today, if available) =="
if have ausearch; then
  sudo ausearch -f "$R" -ts today 2>/dev/null || echo "no audit events for today"
else
  echo "ausearch not installed / auditd likely not enabled"
fi
