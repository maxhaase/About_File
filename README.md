# About_File
Bash script that prints a comprehensive, forensics-style report for any file you pass as an argument. It includes dependency checks, robust DOCX metadata extraction (via xmlstarlet if present, otherwise a Perl fallback), and safe fallbacks for optional tools.
What the script does (high level)

Resolves the absolute path and shows which block device, filesystem, and mount options back it.

Prints all file timestamps in UTC: atime, mtime, ctime, and btime (creation) if available.

Tries to read low-level inode times with debugfs (ext4) or xfs_io (XFS).

Dumps ACLs (getfacl), extended attributes (getfattr), and immutable flags (lsattr).

Computes SHA-256 and SHA-512 hashes for chain-of-custody.

Identifies file type with file -k.

If exiftool is available, prints general metadata (helpful for DOCX/PDF/etc.).

If the file is a DOCX/ZIP container, extracts docProps/core.xml and docProps/app.xml via xmlstarlet (preferred) or a Perl fallback to pull created, modified, creator, title, application, total_edit_minutes, and pages.

Locates any hardlinks to the same inode (same filesystem).

Shows mount options, which matter for atime behavior (e.g., relatime).

Queries Linux audit logs for recent events referencing the file if auditd/ausearch are enabled.

This script is designed to be copy-paste safe and robust on typical Linux workstations and servers.
