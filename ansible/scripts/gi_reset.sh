#!/bin/bash
# gi_reset.sh — wipe the GI layer on a node for a clean-slate reinstall.
# Used after the interleaved-ohasd experiment left a half-configured
# stack (di 2026-10-21). Safe here: no databases exist, DATA/FRA never
# mounted. Self-elevating. ASM headers themselves are re-zeroed by
# playbook 02 with asm_force=true, not here.
set -x
SUDO=""; [ "$(id -u)" != "0" ] && SUDO="sudo"
GI=/u01/app/11.2.0/grid

$SUDO systemctl disable --now ohasd 2>/dev/null || true
$SUDO rm -f /etc/systemd/system/ohasd.service
$SUDO systemctl daemon-reload 2>/dev/null || true

[ -x $GI/bin/crsctl ] && $SUDO timeout 120 $GI/bin/crsctl stop crs -f >/dev/null 2>&1 || true
sleep 5
for p in ohasd.bin crsd.bin ocssd.bin evmd.bin has.bin parmon oraagent.bin; do
  $SUDO pkill -9 -f "bin/$p" 2>/dev/null || true
done
sleep 2

$SUDO sed -i '/ohasd/d' /etc/inittab
# Clear the FULL stranded-state set: root.sh also leaves scls_scr/lastgasp/
# oprocd behind, and CRS-4046 "Invalid Oracle Clusterware configuration"
# aborts the next root.sh at ~2 min if they survive (di 2026-10-21 15:24).
$SUDO rm -f /etc/oracle/olr.loc /etc/oracle/ocr.loc /etc/oracle/olr.loc.orig /etc/oracle/ocr.loc.orig
$SUDO rm -rf /etc/oracle/scls_scr /etc/oracle/lastgasp /etc/oracle/oprocd
$SUDO rm -rf /var/run/oracle

$SUDO rm -rf $GI
$SUDO rm -rf /u01/app/grid/* /u01/app/11.2.0/grid/install/chainedInstall   # gpnp profile/wallets + chained jobs = CRS-4046 on retry
$SUDO rm -rf /u01/app/oraInventory
$SUDO rm -rf /u01/media
$SUDO rm -f /u01/tmp/*.rsp
$SUDO rm -rf /u01/app/oracle/cfgtoollogs

echo "RESET_DONE $(hostname)"
$SUDO ls -la /u01/app/ 2>/dev/null | head -8

echo "NOTE: disk HEADERS are not wiped here - the next build must run"
echo "      playbook 02 with -e asm_force=true (stack DOWN only!), else the"
echo "      GI installer aborts with INS-30516 on the stale +CRS dg."
