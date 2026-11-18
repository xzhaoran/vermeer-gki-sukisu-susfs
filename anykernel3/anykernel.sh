### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## adapted for Redmi K70 (vermeer): GKI 2.0, kernel-only boot image

### AnyKernel setup
# global properties
properties() { '
kernel.string=GKI 5.15.194 + SukiSU-Nova + SUSFS (vermeer)
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=vermeer
device.name2=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
# vermeer: header v4 boot image, kernel only (no ramdisk), slot device
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
split_boot;

if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
  # image carries a ramdisk: keep it, repack normally
  unpack_ramdisk;
  write_boot;
else
  # GKI 2.0 device: kernel lives in boot, generic ramdisk in init_boot.
  # Replace the kernel only and leave every other partition alone.
  flash_boot;
fi;
## end boot install
