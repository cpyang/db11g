# Installer media staging

Everything in this directory is gitignored **except this README** — the
Oracle binaries are licensed and must be downloaded by you.

## What goes here

Oracle Database 11.2.0.4 for Linux x86-64 — My Oracle Support
**Patch 13390677** (search "11.2.0.4 for Linux x86-64"), all seven parts:

```
p13390677_112040_Linux-x86-64_1of7.zip
p13390677_112040_Linux-x86-64_2of7.zip
...
p13390677_112040_Linux-x86-64_7of7.zip
```

(`1of7` carries Grid Infrastructure, `2of7` the RDBMS install image;
the playbooks unzip what they need from this directory.)

## How to place them

Either copy the zips in, or — to avoid duplicating ~7 GB — symlink each
file from wherever your media library lives:

```bash
ln -s /path/to/media/p13390677_112040_Linux-x86-64_*of7.zip staging/
```

Keep `staging/` itself a real directory; only the files inside may be
symlinks. (The VMs mount it via vboxsf, which resolves per-file host
symlinks — verified working; a top-level `staging` symlink instead of a
directory is NOT portable and was removed from the repo history.)

## Sanity checks

- `for z in staging/p13390677_*.zip; do unzip -t "$z" >/dev/null && echo OK "$z"; done`
  — CRC failures mean a truncated download; the installer WILL die on it.
- After `vagrant up`, the guest sees them read-only at `/u01/staging/`
  (Vagrantfile shared-folder definition; playbooks 03/04 unpack from
  there into `/u01/media`).

## Git behavior

`.gitignore` excludes any content placed here, tracks only this README,
and also stays quiet if `staging` is (mistakenly) a symlink.
