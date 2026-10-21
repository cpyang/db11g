# Oracle Database 11.2.0.4 RAC Lab Environment (Vagrant + VirtualBox + Ansible)

> Two-node Oracle 11.2.0.4 RAC on one workstation: Vagrant manages the VMs,
> host-side Ansible drives every Oracle installation step.

## Overview

- **Vagrant + VirtualBox** — VM lifecycle, host-only networking, shared VDIs
- **Ansible (host-driven)** — OS prep, ASM disks, silent GI/DB installs, dbca
- **staging/** read-only shared folder as the sole installation source

**Nothing installs during `vagrant up`.** Vagrant only boots the two nodes
and runs the tiny bootstrap/swap scripts; every Oracle phase is an explicit
`ansible-playbook` run from the host. That keeps long installer sessions
re-attachable and re-runnable per phase.

## Architecture

```
 db11g-rac1.db11g.lab                     db11g-rac2.db11g.lab
 192.168.86.11 / 10.90.90.11              192.168.86.12 / 10.90.90.12
 vip 192.168.86.101                       vip 192.168.86.102
        \                                        /
     ASM_SCSI shared VDIs (Fixed + shareable)   /
   db11g_crs.vdi 12G | db11g_data.vdi 20G | db11g_fra.vdi 10G
                SCAN: db11g-scan = 192.168.86.100
```

### Node addressing

| Component | Node 1 | Node 2 |
|-----------|--------|--------|
| Hostname (FQDN) | db11g-rac1.db11g.lab | db11g-rac2.db11g.lab |
| Public IP | 192.168.86.11 | 192.168.86.12 |
| Private IP (interconnect) | 10.90.90.11 | 10.90.90.12 |
| Virtual IP | 192.168.86.101 | 192.168.86.102 |
| SCAN | 192.168.86.100 (`db11g-scan`, single) | shared |
| RAM / vCPU | 6 GB / 2 | 6 GB / 2 |

> **Why not 192.168.56.x / 10.10.10.x?** Those ranges belong to the 19c RAC
> lab (`oracle_dr_on_aws/tests`) that runs on the same hosts. Reusing them
> produces two VMs with identical IPs — the ARP layer will not warn you.
> Keep the ranges apart.

The interconnect is a VirtualBox **internal network** (`db11g-priv-net`):
the fastest private path, no host vboxnet needed. eth0 in-guest is
Vagrant's NAT (internet for yum/NTP); the two `private_network` lines
become eth1/eth2 in first-boot order. NIC roles are resolved **by
address** at runtime — never trust an `ethX` in a config here.

### Storage layout

| VDI | Size | ASM label → disk group | Contents |
|-----|------|------------------------|----------|
| `db11g_crs.vdi` | **12 GB** | `/dev/oracleasm/disks/CRS` → **CRS** | OCR + voting files (installer-placed) |
| `db11g_data.vdi` | **20 GB** | `/dev/oracleasm/disks/DATA` → **DATA** | database files |
| `db11g_fra.vdi` | **10 GB** | `/dev/oracleasm/disks/FRA` → **FRA** | recovery area (8 GB cap) |
| `db11g-racN-swap.vdi` | 6 GB | (not ASM) | swap — CVU wants swap ≈ RAM |

The three shared sizes are **deliberately distinct**: guests identify disks
by exact sector count (VBox disks expose no serial; letters drift). VDIs
live in `.vagrant/shared_disks/` and are created **Fixed + shareable** —
VirtualBox 7 refuses `--mtype shareable` on dynamic media, so legacy
dynamic `disks/*.vdi` files from the old Vagrantfile are unusable (the
Vagrantfile now aborts with instructions if it meets one). All redundancy
is EXTERNAL (lab: no mirroring).

## Installation media — `staging/`

The Vagrantfile maps host `staging/` into both guests **read-only** at
`/u01/staging` (VirtualBox shared folder; nothing is rsync'd — the default
`/vagrant` sync is disabled so the 5 GB of zips never copy into guests).

This lab installs from the **11.2.0.4 patch-set media** (downloadable with
a free OTN account — search MyOracleSupport for patch **13390677**):

| File | Role | Needed here |
|------|------|-------------|
| `p13390677_112040_Linux-x86-64_1of7.zip` | RDBMS part 1 | ✅ |
| `p13390677_112040_Linux-x86-64_2of7.zip` | RDBMS part 2 | ✅ |
| `p13390677_112040_Linux-x86-64_3of7.zip` | **Grid Infrastructure** | ✅ |
| `…_4of7…7of7.zip` | client / gateways / examples / docs | ❌ (harmless) |

> ⚠️ Media mapping verified against the archives themselves: the GI
> installer is in **3of7**, NOT 1of7 (`1of7`+`2of7` = `database/` only).
> `ansible/reference/*.rsp.orig` were extracted from these zips and are the
> ground truth for response-file keys.

Software lands on node1 at `/u01/media/` (unzipped from the mount, ~13 GB —
the 50 GB root disk absorbs it), and 11.2 installers **propagate** homes to
node2 themselves.

## Prerequisites

| Software | Version | Notes |
|----------|---------|-------|
| VirtualBox | ≥ 7.0 | fixed+shareable VDIs, internal net |
| Vagrant | ≥ 2.3 | box `oraclelinux/7` (virtualbox provider) |
| Ansible | **ansible-core 2.16.x pinned venv** | see below |

**Ansible version is load-bearing.** System ansible-core ≥ 2.17 dropped
Python 3.6 target support — EL7 only ships 3.6, so 2.17+ connects and then
dies on module execution. Create the venv once:

```bash
python3.12 -m venv .venv-ansible          # 2.16 needs controller ≤ 3.12
source .venv-ansible/bin/activate
pip install 'ansible-core==2.16.*'
```

(11g also links with `make 3.82`; EL7's base-repo make is exactly that —
another reason this lab stays on OL7, not OL8.)

## Quick start

```bash
cd ~/src/db11g
vagrant up db11g-rac1          # node1 FIRST (it owns cluster formation)
vagrant up db11g-rac2

cd ansible && source ../.venv-ansible/bin/activate
ansible-playbook playbooks/01-configure-os.yml        # OS/users/DNS/trust
ansible-playbook playbooks/02-configure-cluster.yml   # ASM disks, probes
ansible-playbook playbooks/03-install-grid.yml        # GI + root.sh + DGs  (~45 min)
ansible-playbook playbooks/04-install-db.yml          # RDBMS software      (~40 min)
ansible-playbook playbooks/05-create-db.yml           # dbca RAC database   (~45 min)
```

Playbook phases are idempotent and stage-guarded: re-running a phase skips
completed work (`crsctl` present, `bin/oracle` size, DG visible in
`crsctl stat res -t`). root.sh phases always run node1 before node2 — do
not remove the play ordering.

Before the **first** real run of 05, sanity-check the dbca flags on the VM:
`vagrant ssh db11g-rac1 -c "sudo -u oracle /u01/app/oracle/product/11.2.0/dbhome_1/bin/dbca -createDatabase -help"`.

### Verify

```bash
vagrant ssh db11g-rac1
sudo -u grid /u01/app/11.2.0/grid/bin/crsctl check cluster -all
sudo -u grid /u01/app/11.2.0/grid/bin/olsnodes -n -s
sudo -u grid /u01/app/11.2.0/grid/bin/crsctl query css votedisk
sudo -u grid /u01/app/11.2.0/grid/bin/ocrcheck
sudo -u grid asmcmd lsdg                      # CRS, DATA, FRA mounted
srvctl status database -d rac                  # rac1 + rac2 running
```

## Project structure

```
db11g/
├── Vagrantfile                  # VMs, shared VDIs (Fixed+shareable), staging mount
├── staging/                     # 11.2.0.4 zips (gitignored) — the install source
├── ansible/
│   ├── ansible.cfg              # inventory + roles_path (run from ansible/)
│   ├── inventory/
│   │   ├── hosts                # FQDN hosts, per-node IPs, machine keys
│   │   └── group_vars/          # all.yml (OS/media), rac.yml (cluster/db)
│   ├── playbooks/               # 01 os → 02 cluster → 03 grid → 04 db → 05 dbca
│   ├── roles/
│   │   ├── common/              # users, limits, sysctl, hosts, dnsmasq, ssh trust
│   │   ├── storage/             # ASM disk discovery + udev symlinks
│   │   ├── grid/                # GI install (stages: check|software|root|dgs)
│   │   └── database/            # RDBMS install (stages: check|software|root|verify)
│   ├── scripts/asm_setup.sh     # size-keyed partitioning + udev rules (idempotent)
│   └── reference/               # media response templates (ground truth)
└── vagrant/scripts/
    ├── bootstrap.sh             # EL7-minimal: SELinux off, firewalld off, python3
    └── swap_setup.sh            # 6 GB swap VDI → GPT partition + fstab (run:always)
```

Retired by this revision: root `ansible.cfg` (wrong roles_path),
`vagrant/scripts/ansible-provision.sh` (host commands run in-guest),
`packages/` and `disks/` (superseded by `staging/` and
`.vagrant/shared_disks/`).

## What gets configured

### OS (`common`)
- `grid` (GI owner; **not** in dba) + `oracle` users, fixed-GID groups, NOPASSWD sudo
- limits via drop-in (`/etc/security/limits.d`), sysctl (incl.
  `vm.overcommit_memory=1`, required for AMM on small VMs), THP off via systemd unit
- `/etc/hosts` (public/vip/priv/scan) + **dnsmasq** serving the zone — 11.2's
  SCAN prereq wants real DNS; hosts-only trips CVU PRVF-11826. `PEERDNS=no`
  protects `/etc/resolv.conf` from the NAT interface's DHCP.
- SSH trust for **oracle and grid**, every node incl. self, as **classic PEM
  keys** (`ssh-keygen -m PEM`) — the 11.2 installer's built-in Java ssh
  cannot read OpenSSH-format keys and fails with "invalid privatekey"
  while everything looks fine from a shell.

### Cluster (`02`)
- Shared VDIs: wipe + GPT-partition (node1 only) + udev symlinks
  `/dev/oracleasm/disks/{CRS,DATA,FRA}` keyed by **partition sector size**
- Per-hop BatchMode ssh probes + SCAN resolution probe (fail early, not in CVU)

### Grid (`03`)
- `runInstaller -silent` from `/u01/media/grid` with the media-format rsp
- OCR/voting into the CRS disk group (EXTERNAL); DATA+FRA created after
  root.sh via `asmca -silent`
- root.sh node1 → node2; verified with `crsctl check cluster -all` + `olsnodes`

### Database (`04`/`05`)
- software-only EE install with `CLUSTER_NODES` = both nodes (a blank list
  does **not** auto-propagate — the remote home keeps a 0-byte `bin/oracle`)
- `$OH/root.sh` on both nodes; verify = bin/oracle size + setuid mode
- dbca create (node1) → `-addInstance` (node2) → FRA + 2×OPEN check

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Vagrantfile aborts: "DYNAMIC media" | legacy `disks/*.vdi` — confirm unattached/empty (`showmediuminfo`, `Machine:` blank), delete, re-up |
| all modules fail right after connect | system ansible ≥ 2.17 on EL7 targets — activate the pinned venv |
| ASM disk not visible to installer | rerun `02`; check `blockdev --rereadpt` + `udevadm test`; never hand-map `/dev/sdX` |
| root.sh node2 `PRKC-1168 "AUTO"` | VIPs must be static: keep `autoConfigureClusterNodeVIP=false` + hosts entries |
| installer log "Failed to add identity file … invalid privatekey" | keys not classic PEM — rerun `01` |
| scan ORA-00141 / listeners "support no services" | dnsmasq down or bound to wrong NIC — `systemctl status dnsmasq`, `nslookup db11g-scan 127.0.0.1` |
| CVU PRVF-11826 (empty DNS set) | `/etc/resolv.conf` rewritten by DHCP — `PEERDNS=no` + rerun `01` |
| CRS broken after host reboot | bring up node1, wait for CRS online, then node2 (shared VDI lock order) |

Guest log locations: installer `/u01/app/oraInventory/logs/`, GI
`/u01/app/grid/cfgtoollogs/`, dbca `/u01/app/oracle/cfgtoollogs/dbca/`.

## Cleanup

```bash
vagrant destroy -f                     # VMs; shared VDIs KEPT (deliberate)
rm -f .vagrant/shared_disks/*.vdi      # only for a true cold start
```

VDIs survive `destroy` so a rebuild can reuse ASM content. Note that
`destroy && up` regenerates ssh state → re-run `01` **before** `02` so the
trust probes find rebuilt keys/known_hosts.

## Security notes

Lab only: shared `oracle` passwords everywhere, no firewalld, no TLS. Never
expose these ports beyond the host.

## References
- Oracle 11.2.0.4 Installation Guide (Linux x86-64), RAC chapter
- Media pack: patch 13390677 (1of7…7of7) — see `staging/` table above
- ansible-core "Managed Node Requirements" (why 2.16 for EL7 targets)
