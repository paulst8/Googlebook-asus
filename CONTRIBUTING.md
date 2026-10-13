# Contributing

Thanks for helping. The most useful contribution is a **[hardware report](https://github.com/paulst8/Googlebook-asus/issues/new?template=hardware_report.yml)**: tell us which laptop you tried, which step failed or worked, and what `bm-configure.sh` detected.

## Reporting problems

- Use the [bug report](https://github.com/paulst8/Googlebook-asus/issues/new?template=bug_report.yml) form. Say which script failed and paste its last lines.
- Questions and ideas that aren't bugs: use [issues](https://github.com/paulst8/Googlebook-asus/issues).
- Do **not** post your signing key (`avb.pem`), or any Google image, in an issue.

## Changing the scripts

1. Fork the repo and make a branch.
2. Keep scripts in `scripts/` and helper code in `scripts/lib/`. Scripts find the helper code relative to themselves and the working files relative to the folder you run them from.
3. A script that writes to a disk must: find the drive by **serial number** from `bm.conf`, refuse to continue if it isn't found, show what it will do, and ask for a typed confirmation. Support `DRYRUN=1` where practical.
4. Don't hard-code a drive, a serial number, a PCI ID, a firmware name or a user name. Put hardware-specific values in `bm-configure.sh` / `bm.conf`.
5. Run the checks locally before you open a pull request:
   ```bash
   for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done
   shellcheck --severity=error scripts/*.sh scripts/lib/*.sh   # if you have shellcheck installed
   python3 -m py_compile scripts/lib/*.py
   python3 -m unittest discover -s tests -v
   ```
6. In the pull request, say what you tested and on which hardware. Disk-writing changes need meaningful disk-free safety tests; state clearly which hardware paths remain untested.

## Please don't commit

Images, keys, `bm.conf`, partition-table backups, or logs that contain serial numbers or account names. `.gitignore` covers the usual ones; the CI also scans for personal data.
