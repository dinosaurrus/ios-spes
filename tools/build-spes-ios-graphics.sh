#!/bin/bash
# Host-only full iOS boot image builder. Requires an installed iOS userdata root.
set -euo pipefail
[[ $# == 2 ]] || { echo 'usage: build-spes-ios-graphics.sh KERNEL LIVE_FDT' >&2; exit 2; }
kernel=$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1")
fdt=$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$2")
cd "$(dirname "$0")/.."
[[ -f "$kernel" && -f "$fdt" ]] || { echo 'Kernel or live FDT missing' >&2; exit 1; }
# UI defaults match the tested six-core boot and the published 60 Hz mode.
# Override SWEET_CPUS/SWEET_FB_HZ explicitly for low-rate diagnostic boots.
cpus=${SWEET_CPUS:-6}
fb_hz=${SWEET_FB_HZ:-60}
gpu_mhz=${SPES_GPU_MHZ:-300}
# Keep the GPU (RedwoodGPU) and its fences on by default; the UI needs them.
gpu=${SWEET_GPU:-1}
glsync=${SWEET_GL_SYNC:-1}
# 1 = stop the kernel console at the first iOS frame (normal UI boot);
# 0 = keep drawing it over the UI (diagnostic: shows the last lines/panics).
noconsole=${SWEET_FB_NOCONSOLE:-1}
# Unset = kernel default (direct MDP scanout when VIG0 scans the boot fb).
direct=${SWEET_FB_DIRECT:-}
# Extra boot-args for diagnostic images, e.g. SWEET_EXTRA_ARGS='modem=1 wifi=1'.
extra=${SWEET_EXTRA_ARGS:-}
# A stable per-phone Wi-Fi MAC (from the live FDT's serial number; the serial is not printed).
wlan_mac=$(python3 tools/spes_wlan_mac.py "$fdt" 2>/dev/null || true)
[[ -n "$wlan_mac" ]] && extra="${extra:+$extra }wlan_mac=$wlan_mac"
mkdir -p shim/out
python3 tools/mkadt.py shim/out/spes-ios-graphics.adt --device spes --memory-dtb "$fdt"
# The development kernel uses OSX platform policy; allow iOS executables.
# ignition_level=1 uses the cache merged into our single HFS root.
python3 tools/mkpayload.py "$kernel" shim/out/spes-ios-graphics.adt shim/out/spes-ios-graphics-fixed.payload \
    --cmdline "debug=0xc serial=3 cpus=$cpus keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 ufsroot=userdata unentitled_ios_sim_launch=1 ignition_level=1 launchd_unsecure_cache=1 wdt_test=no_user_checkin wdt=-1 ufsrw=1 rootrw=1 sweetlog=1 ufslogsecs=10 sweettouch=1 sweettouchdelay=5 sweettouchdiag=3 sweetkeys=1 sweethw=0 sweetfb_noconsole=$noconsole sweetfb_hz=$fb_hz spesgpu=$gpu spesgpuprobe=1 spesgpu_mhz=$gpu_mhz glsync=$glsync${direct:+ sweetfb_direct=$direct}${extra:+ $extra}"
BOOT_HEADER_VERSION=3 shim/build.sh out/spes-ios-graphics-fixed.payload
cp shim/out/shim-boot.img shim/out/spes-ios-graphics.img
shasum -a 256 shim/out/spes-ios-graphics.img > shim/out/spes-ios-graphics.img.sha256
echo 'Built shim/out/spes-ios-graphics.img; nothing sent to phone. Boot only after iOS root installation.'
