# Security

## Keep these private

- **Your signing key** (`~/gbos-avb-key/avb.pem`). Anyone with it can sign system images that your Googlebook OS will accept as verified. Never upload it, commit it or share it. If it leaks, delete it, make a new one and run `bm-sign.sh` again.
- **`bm.conf`** and the partition-table backups contain your drive serial numbers. They are not secret, but there is no reason to publish them.

## What this project does not protect

Locked boot verifies Android's own partitions only. Nothing checks GRUB, the kernel or the ramdisk, so the "locked" state is not a full chain of trust. See [Locked boot](docs/LOCKED-BOOT.md). Don't use Googlebook OS from this project for banking or other sensitive accounts.

## Reporting a vulnerability

If you find a problem in the scripts that could harm a user (for example, a script that can write to the wrong disk), please report it privately through the repository's **Security → Report a vulnerability** page rather than a public issue. For everything else, use a normal issue.
