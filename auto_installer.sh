#!/bin/sh
#
# Copyright (C) 2025-26 https://github.com/ArKT-7/Auto-Installer-Forge
#
# Made For Processing ROMs containing payload.bin, converts them into a ready-to-flash super.img, and generates a fully automated installation package for Fastboot or Recovery, which can later be flashed using my custom flasher scripts.

# Define URLs and target paths for binaries
BASE_URL="https://raw.githubusercontent.com/arkt-7/Auto-Installer-Forge/main"
URL_BUSYBOX="$BASE_URL/bin/linux_amd64/busybox"
URL_PAYLOAD_DUMPER="$BASE_URL/bin/linux_amd64/otaripper"
URL_LPMAKE="$BASE_URL/bin/linux_amd64/lpmake"
URL_LPUNPACK="$BASE_URL/bin/linux_amd64/lpunpack"
URL_FIGLET="$BASE_URL/bin/linux_amd64/figlet"
URL_FONT1="$BASE_URL/bin/figlet_fonts/standard.flf"
URL_FONT2="$BASE_URL/bin/figlet_fonts/nancyj.flf"
URL_FONT3="$BASE_URL/bin/figlet_fonts/sblood.flf"
URL_7ZZS="$BASE_URL/bin/linux_amd64/7zzs"
URL_SIMG2IMG="$BASE_URL/bin/linux_amd64/simg2img"

ORIGINAL_DIR="$PWD"
current_dir=$(basename "$PWD")
if [ "$current_dir" = "Auto-Installer-Forge" ]; then
  BIN_DIR="$PWD/bin"
  WORK_DIR="$PWD/out"
  MAGISK_DIR="$BIN_DIR/magisk_patch"
else
  BIN_DIR="$PWD/Auto-Installer-Forge/bin"
  WORK_DIR="$PWD/Auto-Installer-Forge/out"
  MAGISK_DIR="$BIN_DIR/magisk_patch"
fi
mkdir -p "$WORK_DIR" "$MAGISK_DIR"
# echo -e "BIN_DIR=$BIN_DIR"
# echo -e "WORK_DIR=$WORK_DIR"
# echo -e "MAGISK_DIR=$MAGISK_DIR"

log() {
    echo -e -e "\n[$(date +"%H:%M:%S")] $1"
}

# Function to download and set permissions
download_and_set_permissions() {
    local url=$1 dest_file=$2
    log "[INFO] Downloading $(basename "$dest_file")..."
    curl -L -# -o "$dest_file" "$url" || { log "[ERROR] Failed to download $(basename "$dest_file")"; exit 1; }
    chmod +x "$dest_file"
    echo -e "[SUCCESS] $(basename "$dest_file") ready."
}

# Function to download files without setting permissions
download_file() {
    local url=$1 dest_file=$2
    #echo -e "[INFO] Downloading $(basename "$dest_file")..."
    curl -L -# -o "$dest_file" "$url" || { log "[ERROR] Failed to download $(basename "$dest_file")"; }
    echo -e "[SUCCESS] $(basename "$dest_file") downloaded."
}

# Function to extract checksum from file
get_checksum() {
    local filename="$1"
    if [ "$CHECKSUM_AVAILABLE" -eq 0 ]; then
        echo " "
        return
    fi
    grep "^$filename=" "$CHECKSUM_FILE" | cut -d'=' -f2
}


# Function to verify checksum
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"

    if [ "$CHECKSUM_AVAILABLE" -eq 0 ]; then
        #echo -e "[WARNING] Checksum verification skipped for $(basename "$file")."
        return 0
    fi

    if [ -z "$expected_checksum" ]; then
        echo -e "[WARNING] No checksum found for $(basename "$file"), skipping verification."
        return 0  # Skip verification if no checksum is available
    fi

    local actual_checksum
    actual_checksum=$($BIN_DIR/busybox sha256sum "$file" | awk '{print $1}')

    if [ "$actual_checksum" = "$expected_checksum" ]; then
        #echo -e "[SUCCESS] Checksum verified for $(basename "$file")."
        return 0
    else
        echo -e "\n[ERROR] Checksum mismatch for $(basename "$file")! Expected: $expected_checksum, Got: $actual_checksum"
        return 1
    fi
}

# Function to attempt download with checksum validation
download_with_fallback() {
    PRIMARY_URL="$1"
    FALLBACK_URL="$2"
    DEST_FILE="$3"
    FILE_KEY="$4"  # Key name in checksum file

    #echo -e "[INFO] Downloading: $(basename "$DEST_FILE")"

    EXPECTED_CHECKSUM=$(get_checksum "$FILE_KEY")

    if download_file "$PRIMARY_URL" "$DEST_FILE"; then
        if verify_checksum "$DEST_FILE" "$EXPECTED_CHECKSUM"; then
            return 0  # Download successful with valid checksum
        else
            echo -e "[WARNING] Checksum mismatch, trying fallback...\n"
            rm -f "$DEST_FILE"
        fi
    else
        echo -e "[WARNING] Primary download failed, trying fallback...\n"
    fi

    # Try downloading from fallback source
    if download_file "$FALLBACK_URL" "$DEST_FILE"; then
        if verify_checksum "$DEST_FILE" "$EXPECTED_CHECKSUM"; then
            return 0  # Fallback successful with valid checksum
        else
            echo -e "[ERROR] Fallback checksum mismatch! Continuing with warning...\n"
            return 1
        fi
    else
        echo -e "[ERROR] Failed to download $(basename "$DEST_FILE") from both sources! Continuing..."
        return 1
    fi
}

# Function to extract magiskboot and libs
extract_magisk_tools() {
    log "[INFO] Extracting Magisk tools..."

    # Unzip only assets and lib folders; if unzip fails, exit
    if ! $BIN_DIR/7zzs x "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/$1" "assets/*" "lib/*" -o"$MAGISK_DIR" -y > /dev/null; then
        log "[ERROR] Failed to unzip Magisk APK"
        return 1
    fi

    ARCH_DIR="arm64-v8a"
    LIB_PATH="$MAGISK_DIR/lib/$ARCH_DIR"
    if [ -d "$LIB_PATH" ]; then
        for file in "$LIB_PATH"/*.so; do
            [ -f "$file" ] || continue
            new_name=$(basename "$file" | $BIN_DIR/busybox sed -E 's/^lib(.*)\.so$/\1/')
            mv "$file" "$MAGISK_DIR/assets/$new_name"
        done
    else
        log "[ERROR] Library folder not found for $ARCH_DIR"
        return 1
    fi
    ARCH_DIR="x86_64"
    LIB_PATH="$MAGISK_DIR/lib/$ARCH_DIR"
    if [ -d "$LIB_PATH" ]; then
        for file in "$LIB_PATH"/lib{magiskboot,busybox}.so; do
            [ -f "$file" ] || continue
            new_name=$(basename "$file" | $BIN_DIR/busybox sed -E 's/^lib(.*)\.so$/\1/')
            mv "$file" "$MAGISK_DIR/assets/$new_name"
        done
    else
        log "[ERROR] Library folder not found for $ARCH_DIR"
        return 1
    fi
    chmod -R +x "$MAGISK_DIR/assets/"
    export MAGISKBOOT="$MAGISK_DIR/assets/magiskboot"
    return 0
}

# Function to patch boot and vendor_boot for TWRP Recovery
patch_twrp_recovery() {
    if [ -n "$1" ] && [ -f "$1" ]; then
         INSTALL_TWRP=$(grep '^INSTALL_TWRP=' "$1" | cut -d'=' -f2)
    fi

    if [ -z "$INSTALL_TWRP" ]; then
        echo -e "\nDo you want to integrate a Custom Recovery (TWRP) Ramdisk (Ensure kernel supports it)"
        echo -e "1) Yes"
        echo -e "2) No"
        while true; do
            echo -n "Enter selection (1-2): "
            read -r choice
            case "$choice" in
                1) INSTALL_TWRP=1; break ;;
                2) INSTALL_TWRP=0; break ;;
                *) echo "Invalid option." ;;
            esac
        done
        #update_field "INSTALL_TWRP" "Install TWRP" "$INSTALL_TWRP"
    fi

    [ "$INSTALL_TWRP" -ne 1 ] && return 0
    TWRP_RAMDISK_PATH="$BIN_DIR/ramdisk.cpio"
    
    log "[INFO] Downloading TWRP Ramdisk..."
    download_with_fallback \
        "$BASE_URL/files/ramdisk.cpio" \
        "$BASE_URL/files/ramdisk.cpio" \
        "$TWRP_RAMDISK_PATH" \
        "ramdisk.cpio"

    if [ ! -f "$TWRP_RAMDISK_PATH" ]; then
        log "[WARNING] Ramdisk download failed, Skipping TWRP integration..."
        return 0
    fi

    log "[INFO] Starting TWRP Ramdisk Integration..."
    local BOOT_IMG="$TARGET_DIR/images/boot.img"
    local VENDOR_BOOT_IMG="$TARGET_DIR/images/vendor_boot.img"
    local WORK_ROOT="$TARGET_DIR/twrp_patch_work"
    local WORK_BOOT="$WORK_ROOT/boot"
    local WORK_VENDOR="$WORK_ROOT/vendor"

    if [ -z "$MAGISKBOOT" ] || [ ! -f "$MAGISKBOOT" ]; then
        MAGISKBOOT="$MAGISK_DIR/assets/magiskboot"
    fi
    $BIN_DIR/busybox mkdir -p "$WORK_BOOT" "$WORK_VENDOR"
    

    log "[INFO] Patching boot.img with TWRP ramdisk..."
    if ! cd "$WORK_BOOT"; then log "[ERROR] Work dir error, Skipping..."; return 0; fi
    
    "$MAGISKBOOT" unpack "$BOOT_IMG" > unpack.log 2>&1
    if [ ! -f "kernel" ]; then
         log "[WARNING] Failed to unpack boot.img, Skipping TWRP..."
         cd "$ORIGINAL_DIR"
         $BIN_DIR/busybox rm -rf "$WORK_ROOT"
         return 0
    fi

    $BIN_DIR/busybox rm -f "ramdisk.cpio"
    $BIN_DIR/busybox cp "$TWRP_RAMDISK_PATH" "ramdisk.cpio"
    "$MAGISKBOOT" repack "$BOOT_IMG" > repack.log 2>&1
    
    if [ -f "new-boot.img" ]; then
        $BIN_DIR/busybox mv "new-boot.img" "twrp-boot.img"
        log "[INFO] boot.img patched successfully (will do vendor_boot patch now)..."
    else
        log "[WARNING] Failed to repack boot.img, Skipping TWRP..."
        cd "$ORIGINAL_DIR"
        $BIN_DIR/busybox rm -rf "$WORK_ROOT"
        return 0
    fi


    log "[INFO] Patching vendor_boot.img fstab..."
    if ! cd "$WORK_VENDOR"; then log "[ERROR] Work dir error, Skipping..."; return 0; fi
    
    "$MAGISKBOOT" unpack "$VENDOR_BOOT_IMG" > unpack.log 2>&1
    if [ ! -f "ramdisk.cpio" ]; then
         log "[WARNING] Failed to unpack vendor_boot.img, Skipping Vendor patch..."
         cd "$ORIGINAL_DIR"
         $BIN_DIR/busybox rm -rf "$WORK_ROOT"
         return 0
    fi
    
    $BIN_DIR/busybox mkdir -p ramdisk_contents
    cd ramdisk_contents
    
    # Use system cpio if available, fallback to busybox
    if command -v cpio >/dev/null 2>&1; then
        cpio -idm < ../ramdisk.cpio 2> ../cpio_err.log
    else
        $BIN_DIR/busybox cpio -idm < ../ramdisk.cpio 2> ../cpio_err.log
    fi
    
    # Filter out harmless warnings
    grep -vE "cpio: .: File exists|[0-9]+ blocks" ../cpio_err.log > ../cpio_filtered_err.log
    if [ -s "../cpio_filtered_err.log" ]; then
         log "[WARNING] Real extraction errors found in vendor ramdisk, Skipping Vendor patch..."
         cd "$ORIGINAL_DIR"
         $BIN_DIR/busybox rm -rf "$WORK_ROOT"
         return 0
    fi
    
    $BIN_DIR/busybox mkdir -p first_stage_ramdisk
    fstab_file=$(find . -type f -name "fstab.qcom" -not -path "./first_stage_ramdisk/*" | head -n 1)
    if [ -z "$fstab_file" ]; then
        log "[INFO] fstab.qcom not found outside, Searching inside first_stage_ramdisk..."
        fstab_file=$(find ./first_stage_ramdisk -type f -name "fstab.qcom" | head -n 1)
    else
        log "[INFO] Deleting any fstab.qcom files inside first_stage_ramdisk..."
        if [ -d "first_stage_ramdisk" ]; then
            find first_stage_ramdisk -type f -name "fstab.qcom" -exec rm -v {} \; > /dev/null 2>&1
        fi
    fi
    
    if [ -n "$fstab_file" ]; then
        mv "$fstab_file" first_stage_ramdisk/
        log "[INFO] Moved $fstab_file to first_stage_ramdisk/"
    else
        log "[INFO] No fstab.qcom found — generating default..."
        cat > first_stage_ramdisk/fstab.qcom <<'EOF'
# The filesystem that contains the filesystem checker binary (typically /system) cannot
# specify MF_CHECK, and must come before any filesystems that do specify MF_CHECK

#TODO: ArKT Add 'check' as fs_mgr_flags with data partition.
# Currently we dont have e2fsck compiled. So fs check would failed.

#<src>                                                 <mnt_point>            <type>  <mnt_flags and options>                            <fs_mgr_flags>
system                                                  /system                erofs   ro                                                   wait,slotselect,avb=vbmeta_system,logical,first_stage_mount,avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
system                                                  /system                ext4    ro,barrier=1,discard                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount,avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
system_ext                                              /system_ext            erofs   ro                                                   wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
system_ext                                              /system_ext            ext4    ro,barrier=1,discard                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
product                                                 /product               erofs   ro                                                   wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
product                                                 /product               ext4    ro,barrier=1,discard                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
vendor                                                  /vendor                erofs   ro                                                   wait,slotselect,avb,logical,first_stage_mount
vendor                                                  /vendor                ext4    ro,barrier=1,discard                                 wait,slotselect,avb,logical,first_stage_mount
odm                                                     /odm                   erofs   ro                                                   wait,slotselect,avb,logical,first_stage_mount
odm                                                     /odm                   ext4    ro,barrier=1,discard                                 wait,slotselect,avb,logical,first_stage_mount
mi_ext                                                  /mnt/vendor/mi_ext     ext4    ro,barrier=1,discard                                 wait,slotselect,avb=vbmeta,logical,first_stage_mount,nofail
mi_ext                                                  /mnt/vendor/mi_ext     erofs   ro                                                   wait,slotselect,avb=vbmeta,logical,first_stage_mount,nofail
/dev/block/by-name/metadata                             /metadata              ext4    noatime,nosuid,nodev,discard                         wait,check,formattable,wrappedkey,first_stage_mount
/dev/block/bootdevice/by-name/boot                      /boot                  emmc    defaults                                             recoveryonly
/dev/block/bootdevice/by-name/userdata                  /data                  f2fs    noatime,nosuid,nodev,discard,reserve_root=32768,resgid=1065,fsync_mode=nobarrier,inlinecrypt     latemount,wait,check,formattable,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0,metadata_encryption=aes-256-xts:wrappedkey_v0,keydirectory=/metadata/vold/metadata_encryption,quota,reservedsize=128M,checkpoint=fs
/dev/block/bootdevice/by-name/modem                     /vendor/firmware_mnt   vfat    ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337,context=u:object_r:firmware_file:s0 wait,slotselect
/dev/block/bootdevice/by-name/dsp                       /vendor/dsp            ext4    ro,nosuid,nodev,barrier=1                            wait,slotselect
/dev/block/bootdevice/by-name/persist                   /mnt/vendor/persist    ext4    noatime,nosuid,nodev,barrier=1                       wait,check
/dev/block/bootdevice/by-name/bluetooth                 /vendor/bt_firmware    vfat    ro,shortname=lower,uid=1002,gid=3002,dmask=227,fmask=337,context=u:object_r:bt_firmware_file:s0 wait,slotselect
# Need to have this entry in here even though the mount point itself is no longer needed.
# The update_engine code looks for this entry in order to determine the boot device address
# and fails if it does not find it.
/dev/block/bootdevice/by-name/misc                      /misc                  emmc    defaults                                             defaults
/devices/platform/soc/*.ssusb/*.dwc3/xhci-hcd.*.auto* auto                   auto    defaults                                             wait,voldmanaged=usbotg:auto
EOF
    fi

    find . -mindepth 1 ! -path './first_stage_ramdisk' ! -path './first_stage_ramdisk/*' -exec rm -rf {} +
    if command -v cpio >/dev/null 2>&1; then
        find . -mindepth 1 | cpio -o -H newc > ../new_ramdisk.cpio 2>/dev/null
    else
        find . -mindepth 1 | $BIN_DIR/busybox cpio -o -H newc > ../new_ramdisk.cpio 2>/dev/null
    fi
    cd "$WORK_VENDOR"
    $BIN_DIR/busybox mv new_ramdisk.cpio ramdisk.cpio
    "$MAGISKBOOT" repack "$VENDOR_BOOT_IMG" > repack.log 2>&1
    
    if [ -f "new-boot.img" ]; then
        $BIN_DIR/busybox mv "new-boot.img" "$VENDOR_BOOT_IMG"
        $BIN_DIR/busybox mv "$WORK_BOOT/twrp-boot.img" "$BOOT_IMG"
        log "[SUCCESS] boot.img and vendor_boot.img patched successfully."
    else
        log "[WARNING] Failed to repack vendor_boot.img. Skipping (Original files untouched)."
        return 0
    fi

    $BIN_DIR/busybox rm -rf "$WORK_ROOT"
    cd "$ORIGINAL_DIR"
    return 0
}

# Function to patch boot.img with magisk
patch_magisk_boot() {
    log "[INFO] Patching boot.img with Magisk..\n"

    # Ensure binary is extracted (idempotent check)
    if [ -z "$MAGISKBOOT" ] || [ ! -f "$MAGISKBOOT" ]; then
        # Fallback to extract if not done by TWRP patcher
        extract_magisk_tools "$1" || return 1
    fi

    # Extract API version
    sdk_version=$(strings "$TARGET_DIR/images/super.img" | grep -m 1 'ro.build.version.sdk=' | cut -d'=' -f2)
    if [ -z "$sdk_version" ]; then
    sdk_version=36
    fi
    echo -e "API level is: $sdk_version"
    # Extract ABI version
    # abi_version=$(strings "$TARGET_DIR/images/super.img" | grep -m 1 'ro.product.cpu.abi=' | cut -d'=' -f2)
    # if [ -z "$abi_version" ]; then
    abi_version=arm64-v8a
    # fi
    # echo -e "API level is: $abi_version"

    $BIN_DIR/busybox sed -i \
    -e "s|API=\$(grep_get_prop ro.build.version.sdk)|API=$sdk_version|" \
    -e "s|ABI=\$(grep_get_prop ro.product.cpu.abi)|ABI=$abi_version|" \
    "$MAGISK_DIR/assets/util_functions.sh"

    $BIN_DIR/busybox sed -i 's|echo -e "ui_print \$1\\nui_print" >> /proc/self/fd/\$OUTFD|echo -e "\$1"|' "$MAGISK_DIR/assets/util_functions.sh"
    $BIN_DIR/busybox sed -i '1 s|^.*$|#!/bin/bash|' "$MAGISK_DIR/assets/boot_patch.sh"
    $BIN_DIR/busybox sed -i 's/ui_print/echo -e/g' "$MAGISK_DIR/assets/boot_patch.sh"
    # Modify boot_patch.sh to hardcode "sda19" for NABU
    if ! $BIN_DIR/busybox sed -i 's/\$BOOTMODE && \[ -z "\$PREINITDEVICE" \] && PREINITDEVICE=\$(\.\/magisk --preinit-device)/PREINITDEVICE="sda19"/' "$MAGISK_DIR/assets/boot_patch.sh"; then
        log "[ERROR] Failed to modify boot_patch.sh"
        return 1
    fi

    "$MAGISK_DIR/assets/boot_patch.sh" "$TARGET_DIR/images/boot.img"

    if [ -f "$MAGISK_DIR/assets/new-boot.img" ]; then
        $BIN_DIR/busybox cp "$MAGISK_DIR/assets/new-boot.img" "$TARGET_DIR/images/magisk_boot.img"
        log "[SUCCESS] Patching successful! Magisk boot image saved at: $TARGET_DIR/images/magisk_boot.img"
    else
        log "[ERROR] Patching unsuccessful. Please patch manually and add to /images folder..."
        return 1
    fi
    return 0
}

# Function to prompt and update a single config field
update_field() {
    field="$1"
    label="$2"
    direct_value="$3"

    line=$(grep "^$field=" "$CONF_FILE")

    value=$(echo "$line" | $BIN_DIR/busybox sed -n "s/^$field=\"\([^\"]*\)\".*/\1/p")

    comment=$(echo "$line" | $BIN_DIR/busybox sed -n "s/^$field=\"[^\"]*\"[[:space:]]*\(.*\)/\1/p")

    if [ -n "$direct_value" ]; then
        new_value="$direct_value"
    else
        echo -e "Current $label: $value"
        echo -n "Enter new $label (leave blank to keep current): "
        read new_value
        [ -z "$new_value" ] && new_value="$value"
    fi

    escaped_new_value=$(printf '%s\n' "$new_value" | $BIN_DIR/busybox sed 's/[&/\]/\\&/g')

    new_line="$field=\"${escaped_new_value}\""
    [ -n "$comment" ] && new_line="$new_line $comment"

    $BIN_DIR/busybox sed -i "s|^$field=.*|$new_line|" "$CONF_FILE"

    echo -e "$label updated to: $new_value\n"
}

# Modified to detect both Payload and Fastboot ROMs
get_rom_zip_path() {
    local INPUT_PATH="$1"
    INPUT_PATH=$(realpath "$INPUT_PATH" 2>/dev/null)

    if [ -z "$INPUT_PATH" ] || [ ! -e "$INPUT_PATH" ]; then
        echo -e "\nPlease enter the full path to an AOSP/FASTBOOT/PORT ROM ZIP file or a folder containing multiple ROM ZIPs:\n"
        read -r INPUT_PATH
        echo " "
    fi

    #INPUT_PATH=$(echo "$INPUT_PATH" | sed 's:^~:'"$HOME"':' | sed 's:/*$::')

    [ -z "$INPUT_PATH" ] && {
        log "[INFO] No input provided. Exiting...\n"
        exit 1
    }

    candidate_zips=()
    count=0

    check_zip_type() {
        local zip_file="$1"
        local zip_content
        zip_content=$($BIN_DIR/7zzs l "$zip_file" 2>/dev/null)
        if echo "$zip_content" | grep -q "payload.bin"; then
            echo "payload"
        elif echo "$zip_content" | grep -qE "super\.(img|zst|img\.zst)"; then
            echo "fastboot"
        else
            echo -e "\n[DEBUG] Unkonwn ROM type for: $(basename "$zip_file")" >&2
            echo -e "ZIP CONTENTS\n" >&2
            echo "$zip_content" >&2
            echo "unknown"
        fi
    }

    if [ -d "$INPUT_PATH" ]; then
        log "[INFO] Searching for valid ROM ZIP files in the specified folder..."
        SAVEIFS=$IFS
        IFS=$(echo -en "\n\b")
        for zip in $(find "$INPUT_PATH" -type f -name "*.zip"); do
            type=$(check_zip_type "$zip")
            if [ "$type" != "unknown" ]; then
                candidate_zips[count]="$zip"
                count=$((count + 1))
            fi
        done
        IFS=$SAVEIFS

    elif [ -f "$INPUT_PATH" ]; then
        case "$INPUT_PATH" in
            *.zip)
                type=$(check_zip_type "$INPUT_PATH")
                if [ "$type" != "unknown" ]; then
                    candidate_zips[0]="$INPUT_PATH"
                    count=1
                fi
                ;;
            *)
                log "[ERROR] The specified file is not a .zip file. Please provide a valid ZIP archive."
                return 1
                ;;
        esac
    else
        log "[ERROR] The specified path is invalid. Please try again."
        return 1
    fi

    if [ "$count" -eq 0 ]; then
        log "[ERROR] No valid ROM files (payload.bin or super.img) found."
        return 1

    elif [ "$count" -eq 1 ]; then
        SELECTED_ZIP_FILE="${candidate_zips[0]}"
        ROM_TYPE=$(check_zip_type "$SELECTED_ZIP_FILE")
        log "[SUCCESS] Found $ROM_TYPE ROM: $(basename "$SELECTED_ZIP_FILE")"
        return 0
    else
        echo -e "\n[INFO] Multiple ROM files found:\n"
        SAVEIFS=$IFS
        IFS=$(echo -en "\n\b")
        for i in $(seq 0 $((count - 1))); do
            index=$((i + 1))
            type=$(check_zip_type "${candidate_zips[$i]}")
            echo -e "$index) [${type}] $(basename "${candidate_zips[$i]}")"
        done
        IFS=$SAVEIFS

        valid=0
        while [ "$valid" -eq 0 ]; do
            echo -e "\nPlease enter the number corresponding to the ZIP file to use (1 - $count): "
            read -r selection
            if echo "$selection" | grep -qE '^[0-9]+$'; then
                index=$((selection - 1))
                if [ "$index" -ge 0 ] && [ "$index" -lt "$count" ]; then
                    SELECTED_ZIP_FILE="${candidate_zips[$index]}"
                    ROM_TYPE=$(check_zip_type "$SELECTED_ZIP_FILE")
                    valid=1
                else
                    echo -e "[ERROR] Invalid selection. Please enter a valid number between 1 and $count."
                fi
            else
                echo -e "[ERROR] Invalid selection. Please enter a valid number between 1 and $count."
            fi
        done
    fi
    return 0
}


echo -e "\nAutomating ROM conversion for easy Fastboot/Recovery flashing for Xiaomi Pad 5 (more devices planned)\n"
echo -e "This script is Written and Made By °⊥⋊ɹ∀°, Telegram - '@ArKT_7', Github - 'ArKT-7'\n"

REQUIRED_SPACE_KB=25000000
AVAILABLE_SPACE=$(df "$WORK_DIR" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE_KB" ]; then
    log "[WARNING] Low disk space in $WORK_DIR! (Available: $((AVAILABLE_SPACE/1024)) MB)"
    
    CURRENT_MOUNT=$(df "$WORK_DIR" | awk 'NR==2 {print $6}')
    AVAIL=$(df -P | awk -v req="$REQUIRED_SPACE_KB" -v cur="$CURRENT_MOUNT" 'NR>1 && $1 !~ /loop/ && $4 > req && $6 != cur {print $6}')
    OTHER_PART=""
    for mnt in $AVAIL; do
        TARGET_BUILD_DIR="$mnt/Auto-Installer-Forge_Build"
        if mkdir -p "$TARGET_BUILD_DIR" 2>/dev/null; then
            OTHER_PART="$mnt"
            break
        elif command -v sudo >/dev/null 2>&1 && sudo mkdir -p "$TARGET_BUILD_DIR"; then
            sudo chown "$(id -u):$(id -g)" "$TARGET_BUILD_DIR"
            OTHER_PART="$mnt"
            break
        fi
    done

    if [ -n "$OTHER_PART" ]; then
        echo -e "\n[INFO] Found available storage: $OTHER_PART"
        echo -e "Would you like to switch workspace to '$OTHER_PART/Auto-Installer-Forge_Build'?"
        echo -n "Confirm Switch? [Y/n] (Default: Y): "
        read -r response
        response=${response:-Y}
        if echo "$response" | grep -Eq "^[Yy]$"; then
            log "[INFO] Switching storage location..."
            WORK_DIR="$OTHER_PART/Auto-Installer-Forge_Build/out"
            mkdir -p "$WORK_DIR"
            TARGET_DIR="$WORK_DIR/Auto-Installer_${ZIP_NAME}_FASTBOOT_RECOVERY"
            mkdir -p "$TARGET_DIR"
            log "[SUCCESS] New Workspace Active: $WORK_DIR"
            NEW_AVAIL=$(df "$WORK_DIR" | awk 'NR==2 {print $4}')
            echo -e "New Available Space: $((NEW_AVAIL/1024/1024)) GB"
        else
            log "[ERROR] Switch rejected. Exiting due to insufficient space."
            exit 1
        fi
    else
        log "[ERROR] No writable partition with >15GB free space found (sudo attempt failed)."
        echo -e "\n[INFO] Current Disk Usage:"
        df -h
        exit 1
    fi
fi

# Download required binaries
download_and_set_permissions "$URL_BUSYBOX" "$BIN_DIR/busybox"
download_and_set_permissions "$URL_PAYLOAD_DUMPER" "$BIN_DIR/otaripper"
download_and_set_permissions "$URL_LPMAKE" "$BIN_DIR/lpmake"
download_and_set_permissions "$URL_LPUNPACK" "$BIN_DIR/lpunpack"
download_and_set_permissions "$URL_FIGLET" "$BIN_DIR/figlet"
download_and_set_permissions "$URL_FONT1" "$BIN_DIR/standard.flf"
download_and_set_permissions "$URL_FONT2" "$BIN_DIR/nancyj.flf"
download_and_set_permissions "$URL_FONT3" "$BIN_DIR/sblood.flf"
download_and_set_permissions "$URL_7ZZS" "$BIN_DIR/7zzs"
download_and_set_permissions "$URL_SIMG2IMG" "$BIN_DIR/simg2img"

# URL to the checksum file
CHECKSUM_FILE="$BIN_DIR/checksum.arkt"
CHECKSUM_AVAILABLE=1  # Assume checksum is available

# Download checksum file
#echo -e "[INFO] Downloading checksum file..."
if ! download_file "$BASE_URL/bin/checksum.arkt" "$CHECKSUM_FILE"; then
    #echo -e "[WARNING] Failed to download checksum file. Continuing without checksum verification!"
    CHECKSUM_AVAILABLE=0  # Set flag to disable checksum verification
elif ! grep -q "=" "$CHECKSUM_FILE"; then
    #echo -e "[WARNING] Checksum file is invalid or empty. Skipping verification!"
    CHECKSUM_AVAILABLE=0  # Mark as unavailable if it's empty or corrupted
fi

if [ -d "$WORK_DIR" ]; then
    # Check if the directory contains any files or only empty folders
	if [ -n "$($BIN_DIR/busybox find "$WORK_DIR" -mindepth 1 -type f 2>/dev/null)" ]; then
        while true; do
            echo -e "\n[WARNING] Existing files found in $WORK_DIR. Choose an option:\n"
            echo -e "1) Delete all existing files from $WORK_DIR and start fresh"
            echo -e "2) Move old files to a backup folder"
            echo -e "3) Exit script\n"
            read -r choice

            case "$choice" in
                1)
                    log "[INFO] Deleting existing files..."
                    $BIN_DIR/busybox rm -rf "$WORK_DIR"/*
                    echo -e "[SUCCESS] Old files deleted."
                    break
                    ;;
                2)
                    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
                    BACKUP_DIR="${WORK_DIR}_backup_$TIMESTAMP"
                    log "[INFO] Moving old files to $BACKUP_DIR..."
                    $BIN_DIR/busybox mkdir -p "$BACKUP_DIR"
                    $BIN_DIR/busybox mv "$WORK_DIR"/* "$BACKUP_DIR"/
                    echo -e "[SUCCESS] Files moved to $BACKUP_DIR."
                    break
                    ;;
                3)
                    log "[INFO] Exiting script. No changes made."
                    exit 0
                    ;;
                *)
                    log "[ERROR] Invalid input. Please select a valid option (1/2/3)."
                    ;;
            esac
        done
    else
        # If only empty folders or no content exists, delete and recreate it
        # log "[INFO] Work directory is empty or contains only empty folders. Cleaning up..."
        $BIN_DIR/busybox rm -rf "$WORK_DIR"
        $BIN_DIR/busybox mkdir -p "$WORK_DIR"
        # log "[SUCCESS] Clean workspace ready."
    fi
fi

if get_rom_zip_path "$1"; then
    log "[INFO] Selected $ROM_TYPE ZIP: $SELECTED_ZIP_FILE"
    export SELECTED_PAYLOAD_ZIP="$SELECTED_ZIP_FILE"
    if [ "$ROM_TYPE" = "fastboot" ]; then
        IS_FASTBOOT_ROM=1
    else
        IS_FASTBOOT_ROM=0
    fi
else
    log "[ERROR] No valid zip selected. Exiting.\n"
    exit 1
fi

# Extract the filename (without extension) from the selected ZIP file
ZIP_NAME=$($BIN_DIR/busybox basename "$SELECTED_ZIP_FILE" .zip)
TARGET_DIR="$WORK_DIR/Auto-Installer_${ZIP_NAME}_FASTBOOT_RECOVERY"

# Create the directory
$BIN_DIR/busybox mkdir -p "$TARGET_DIR"

if [ "$ROM_TYPE" = "payload" ]; then
    echo " "
    log "[INFO] Extracting images directly from OTA ZIP..."
    echo " "
    if [ -n "$1" ]; then
        $BIN_DIR/otaripper -l "$SELECTED_ZIP_FILE"
        $BIN_DIR/otaripper -n -o "$TARGET_DIR" "$SELECTED_ZIP_FILE" > /dev/null 2>&1 || { log "[ERROR] Extraction failed!"; exit 1; }
    else
        $BIN_DIR/otaripper -n -o "$TARGET_DIR" "$SELECTED_ZIP_FILE" || { log "[ERROR] Extraction failed!"; exit 1; }
    fi
    mv "$TARGET_DIR"/extracted_*/* "$TARGET_DIR"/
    rm -rf "$TARGET_DIR"/extracted_*

else
    log "[INFO] Fastboot ROM detected. Extracting all files Please wait..."
    TEMP_EXTRACT_DIR="$TARGET_DIR/Forge-temp"
    $BIN_DIR/busybox mkdir -p "$TEMP_EXTRACT_DIR"

    $BIN_DIR/7zzs x "$SELECTED_ZIP_FILE" -o"$TEMP_EXTRACT_DIR" -y > /dev/null
    log "[INFO] Searching and moving required firmware images..."
    
    STANDARD_FILES="boot.img dtbo.img vendor_boot.img"
    MISSING_FILES=0
    
    for file in $STANDARD_FILES; do
        FOUND_PATH=$($BIN_DIR/busybox find "$TEMP_EXTRACT_DIR" -name "$file" -type f | $BIN_DIR/busybox head -n 1)
        if [ -n "$FOUND_PATH" ]; then
            $BIN_DIR/busybox mv "$FOUND_PATH" "$TARGET_DIR/"
        else
            log "[ERROR] Critical file '$file' not found in extracted ROM!"
            MISSING_FILES=1
        fi
    done

    log "[INFO] Finding super image..."
    FOUND_SUPER=$($BIN_DIR/busybox find "$TEMP_EXTRACT_DIR" -name "super.img" -type f | $BIN_DIR/busybox head -n 1)

    if [ -n "$FOUND_SUPER" ]; then
        $BIN_DIR/busybox mv "$FOUND_SUPER" "$TARGET_DIR/"
        log "[SUCCESS] Found super.img"
    else
        COMPRESSED_SUPER=$($BIN_DIR/busybox find "$TEMP_EXTRACT_DIR" -name "super.*" -type f | $BIN_DIR/busybox head -n 1)
        if [ -n "$COMPRESSED_SUPER" ]; then
            log "[INFO] Found compressed super image: $(basename "$COMPRESSED_SUPER")"
            $BIN_DIR/busybox mv "$COMPRESSED_SUPER" "$TARGET_DIR/"
            LOCAL_COMPRESSED="$TARGET_DIR/$(basename "$COMPRESSED_SUPER")"
            log "[INFO] Decompressing $(basename "$LOCAL_COMPRESSED")"
            if $BIN_DIR/7zzs e "$LOCAL_COMPRESSED" -o"$TARGET_DIR" -y > /dev/null; then
                if [ ! -f "$TARGET_DIR/super.img" ]; then
                    EXTRACTED_FILE=$($BIN_DIR/busybox find "$TARGET_DIR" -maxdepth 1 -name "super*" ! -name "$(basename "$LOCAL_COMPRESSED")" -type f | $BIN_DIR/busybox head -n 1)
                    if [ -n "$EXTRACTED_FILE" ]; then
                        mv "$EXTRACTED_FILE" "$TARGET_DIR/super.img"
                        log "[INFO] Renamed extracted file to super.img"
                    fi
                fi
                if [ -f "$TARGET_DIR/super.img" ]; then
                    log "[SUCCESS] Decompression succsesful."
                    rm -f "$LOCAL_COMPRESSED"
                else
                    log "[ERROR] Extraction ran but super.img could not be located."
                    MISSING_FILES=1
                fi
            else
                log "[ERROR] 7zzs failed to decompress the file."
                MISSING_FILES=1
            fi
        else
            log "[ERROR] Critical file 'super.img' (or compressed variant) not found!"
            MISSING_FILES=1
        fi
    fi

    log "[INFO] Deleting temporary extraction folder..."
    $BIN_DIR/busybox rm -rf "$TEMP_EXTRACT_DIR"

    if [ "$MISSING_FILES" -eq 1 ]; then
        log "[ERROR] Missing required partition images. Exiting."
        exit 1
    fi

    log "[INFO] Unpacking super.img..."
    
    if $BIN_DIR/lpunpack "$TARGET_DIR/super.img" "$TARGET_DIR" > /dev/null 2>&1; then
        log "[SUCCESS] super.img unpacked successfully."
    else
        log "[INFO] Direct unpack failed. Image is likely sparse. Converting to raw..."
        mv "$TARGET_DIR/super.img" "$TARGET_DIR/super.sparse.img"
        if $BIN_DIR/simg2img "$TARGET_DIR/super.sparse.img" "$TARGET_DIR/super.img"; then
            log "[SUCCESS] Converted sparse image to raw."
            rm "$TARGET_DIR/super.sparse.img"
            
            if $BIN_DIR/lpunpack "$TARGET_DIR/super.img" "$TARGET_DIR"; then
                log "[SUCCESS] super.img unpacked successfully."
            else
                log "[ERROR] Failed to unpack super.img even after conversion!"
                exit 1
            fi
        else
            log "[ERROR] Failed to convert sparse image! (simg2img failed)"
            exit 1
        fi
    fi

    rm "$TARGET_DIR/super.img"
    $BIN_DIR/busybox find "$TARGET_DIR" -maxdepth 1 -name "*_b.img" -type f -size 0c -delete
    log "[SUCCESS] Fastboot images prepared."
fi
log "[SUCCESS] Extraction completed."

log "[INFO] Renaming partition images for super.img..."
for img in system vendor mi_ext odm system_ext product; do
    if [ -f "$TARGET_DIR/${img}.img" ]; then
        $BIN_DIR/busybox mv "$TARGET_DIR/${img}.img" "$TARGET_DIR/${img}_a.img"
    fi
done

part_files=()
for img in system vendor mi_ext odm system_ext product; do
    if [ -f "$TARGET_DIR/${img}_a.img" ]; then
        part_files+=("$TARGET_DIR/${img}_a.img")
    fi
done

if [ -n "$2" ] && [ -f "$2" ]; then
    VERIFY_SUPER=$(grep '^VERIFY_SUPER=' "$2" | awk -F'=' '{print $2}' | awk '{print $1}')
else
    echo -e "\nVerify super.img integrity? (Extracts & hashes to ensure no corruption, but takes MUCH longer):"
    echo -e "1) Yes (Slower, but safe)"
    echo -e "2) No (Blazing fast, skips verification)\n"
    while true; do
        echo -n "Enter the number (1-2): "
        read -r VERIFY_CHOICE
        case $VERIFY_CHOICE in
            1) VERIFY_SUPER=1; echo; break ;;
            2) VERIFY_SUPER=0; echo; break ;;
            *) echo -e "Invalid input. Please enter 1 or 2.\n" ;;
        esac
    done
fi

if [ "${VERIFY_SUPER:-0}" -eq 1 ]; then
    log "[INFO] Generating original checksums..."
    $BIN_DIR/busybox sha256sum "${part_files[@]}" > "$TARGET_DIR/original_checksums.txt"
    echo -e "[SUCCESS] Checksums generated."
fi

log "[INFO] Calculating total partition size with buffer..."
TOTAL_SIZE=$($BIN_DIR/busybox du -b "${part_files[@]}" | $BIN_DIR/busybox awk '{sum += $1} END {print sum + (24 * 1024 * 1024); exit}')
echo -e "Total size (with buffer): $TOTAL_SIZE"

log "[INFO] Creating super.img..."
echo " "
partition_args=()
group_a="super_group_a"
group_b="super_group_b"

add_partition() {
    local part_name=$1
    local img_path=$2
    local part_size=$(wc -c <"$img_path")
    partition_args+=(--partition "${part_name}_a:readonly:${part_size}:${group_a}")
    partition_args+=(--image "${part_name}_a=${img_path}")
    partition_args+=(--partition "${part_name}_b:readonly:0:${group_b}")
}

if [ -f "$TARGET_DIR/mi_ext_a.img" ]; then
    add_partition "mi_ext" "$TARGET_DIR/mi_ext_a.img"
fi
for img in odm product system system_ext vendor; do
    if [ -f "$TARGET_DIR/${img}_a.img" ]; then
        add_partition "$img" "$TARGET_DIR/${img}_a.img"
    fi
done
$BIN_DIR/lpmake \
    --metadata-size 65536 \
    --metadata-slots 3 \
    --device super:9126805504 \
    --super-name super \
    --group ${group_a}:9126805504 \
    --group ${group_b}:9126805504 \
    "${partition_args[@]}" \
    --virtual-ab \
    --output "$TARGET_DIR/super.img"

log "[SUCCESS] super.img created."

log "[INFO] Truncating super.img..."
$BIN_DIR/busybox truncate -s "$TOTAL_SIZE" "$TARGET_DIR/super.img"
echo -e "[SUCCESS] Truncation complete."

log "[INFO] Cleaning up extracted img's..."
rm_files=("${part_files[@]}")
$BIN_DIR/busybox rm -f "${rm_files[@]}"
echo -e "[SUCCESS] Cleanup complete."

if [ "${VERIFY_SUPER:-0}" -eq 1 ]; then
    log "[INFO] Verifying super.img integrity (Extract & Hash)..."
    $BIN_DIR/busybox mkdir -p "$TARGET_DIR/super_extracted"
    $BIN_DIR/lpunpack "$TARGET_DIR/super.img" "$TARGET_DIR/super_extracted" || { log "[ERROR] Extraction failed!"; exit 1; }
    echo -e "[SUCCESS] super.img extracted."

    log "[INFO] Generating new checksums..."
    new_checksum_files=()
    for img in system vendor mi_ext odm system_ext product; do
        if [ -f "$TARGET_DIR/super_extracted/${img}_a.img" ]; then
            new_checksum_files+=("$TARGET_DIR/super_extracted/${img}_a.img")
        fi
    done
    $BIN_DIR/busybox sha256sum "${new_checksum_files[@]}" > "$TARGET_DIR/new_checksums.txt"
    echo -e "[SUCCESS] Checksums generated."

    log "[INFO] Normalizing checksums for comparison..."
    $BIN_DIR/busybox sed -E "s|(_a)?\.img|.img|" "$TARGET_DIR/original_checksums.txt" | $BIN_DIR/busybox sed -E "s|$TARGET_DIR|/tmp|" > "$TARGET_DIR/original_checksums_norm.txt"
    $BIN_DIR/busybox sed -E "s|(_a)?\.img|.img|" "$TARGET_DIR/new_checksums.txt" | $BIN_DIR/busybox sed -E "s|$TARGET_DIR/super_extracted|/tmp|" > "$TARGET_DIR/new_checksums_norm.txt"

    log "[INFO] Comparing checksums..."
    $BIN_DIR/busybox diff "$TARGET_DIR/original_checksums_norm.txt" "$TARGET_DIR/new_checksums_norm.txt" || log "[WARNING] Checksum mismatch detected!"
    echo -e "[SUCCESS] Checksum comparison complete."
    
    log "[INFO] Cleaning up verification files..."
    $BIN_DIR/busybox rm -rf "$TARGET_DIR/super_extracted"
    $BIN_DIR/busybox rm -f "$TARGET_DIR/original_checksums.txt" "$TARGET_DIR/new_checksums.txt" "$TARGET_DIR/original_checksums_norm.txt" "$TARGET_DIR/new_checksums_norm.txt" 
    echo -e "[SUCCESS] Verification cleanup complete."
else
    log "[INFO] Skipping super.img verification (Fast Mode enabled)."
fi

log "[COMPLETED] super.img prepared to use in fastboot/recovery!"

log "[INFO] Now will contrust folder/files and Download Scripts as required for Auto Installer!\n"

$BIN_DIR/busybox mkdir -p "$TARGET_DIR/images" 
$BIN_DIR/busybox mkdir -p "$TARGET_DIR/META-INF/com/google/android" 
$BIN_DIR/busybox mkdir -p "$TARGET_DIR/META-INF/com/arkt" 
$BIN_DIR/busybox mkdir -p "$TARGET_DIR/bin/windows/platform-tools"
$BIN_DIR/busybox mkdir -p "$TARGET_DIR/bin/windows/log-tool" 
$BIN_DIR/busybox mkdir -p "$TARGET_DIR/bin/linux/platform-tools" 
$BIN_DIR/busybox mkdir -p "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY"
$BIN_DIR/busybox mv "$TARGET_DIR"/*.img "$TARGET_DIR/images/"

#still gotta upload to mirror location for fallback
download_with_fallback \
    "$BASE_URL/files/userdata.img" \
    "$BASE_URL/files/userdata.img" \
    "$TARGET_DIR/images/userdata.img" \
    "userdata.img"
	
download_with_fallback \
    "$BASE_URL/files/empty_frp.img" \
    "$BASE_URL/files/empty_frp.img" \
    "$TARGET_DIR/images/empty_frp.img" \
    "empty_frp.img"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/7zzs" \
    "$BASE_URL/auto-installer-scripts/bin/7zzs" \
    "$TARGET_DIR/META-INF/com/arkt/7zzs" \
    "7zzs"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/bootctl" \
    "$BASE_URL/auto-installer-scripts/bin/bootctl" \
    "$TARGET_DIR/META-INF/com/arkt/bootctl" \
    "bootctl"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/busybox" \
    "$BASE_URL/auto-installer-scripts/bin/busybox" \
    "$TARGET_DIR/META-INF/com/arkt/busybox" \
    "busybox"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/libhidltransport.so" \
    "$BASE_URL/auto-installer-scripts/bin/libhidltransport.so" \
    "$TARGET_DIR/META-INF/com/arkt/libhidltransport.so" \
    "libhidltransport.so"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/libhwbinder.so" \
    "$BASE_URL/auto-installer-scripts/bin/libhwbinder.so" \
    "$TARGET_DIR/META-INF/com/arkt/libhwbinder.so" \
    "libhwbinder.so"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/dmsetup" \
    "$BASE_URL/auto-installer-scripts/bin/dmsetup" \
    "$TARGET_DIR/META-INF/com/arkt/dmsetup" \
    "dmsetup"
	
download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/make_f2fs" \
    "$BASE_URL/auto-installer-scripts/bin/make_f2fs" \
    "$TARGET_DIR/META-INF/com/arkt/make_f2fs" \
    "make_f2fs"
	
download_with_fallback \
    "$BASE_URL/auto-installer-scripts/bin/mke2fs" \
    "$BASE_URL/auto-installer-scripts/bin/mke2fs" \
    "$TARGET_DIR/META-INF/com/arkt/mke2fs" \
    "mke2fs"

if [ "$IS_FASTBOOT_ROM" -eq 1 ]; then
    SCRIPT_BASE_URL="$BASE_URL/auto-installer-scripts/port"
    PREFIX="port-"
    log "[INFO] Fastboot ROM detected. Downloading specialized scripts from 'port' folder..."
    log "[INFO] Downloading Firmware (fw.zip)..."
    download_with_fallback \
        "$BASE_URL/files/fw.zip" \
        "$BASE_URL/files/fw.zip" \
        "$TARGET_DIR/fw.zip" \
        "fw.zip"
    
    log "[INFO] Extracting fw.zip to images folder..."
    if $BIN_DIR/7zzs e "$TARGET_DIR/fw.zip" -o"$TARGET_DIR/images/" -y > /dev/null; then
        log "[SUCCESS] Firmware extracted."
        $BIN_DIR/busybox rm "$TARGET_DIR/fw.zip"
    else
        log "[ERROR] Failed to extract fw.zip! Check if the file is valid."
        exit 1
    fi
else
    SCRIPT_BASE_URL="$BASE_URL/auto-installer-scripts"
    PREFIX=""
fi

download_with_fallback \
    "$SCRIPT_BASE_URL/update-binary" \
    "$SCRIPT_BASE_URL/update-binary" \
    "$TARGET_DIR/META-INF/com/google/android/update-binary" \
    "${PREFIX}update-binary"
	
download_with_fallback \
    "$SCRIPT_BASE_URL/updater-script" \
    "$SCRIPT_BASE_URL/updater-script" \
    "$TARGET_DIR/META-INF/com/google/android/updater-script" \
    "${PREFIX}updater-script"

download_with_fallback \
    "$BASE_URL/auto-installer-scripts/autoinstaller.conf" \
    "$BASE_URL/auto-installer-scripts/autoinstaller.conf" \
    "$TARGET_DIR/META-INF/autoinstaller.conf" \
    "autoinstaller.conf"

download_with_fallback \
    "$SCRIPT_BASE_URL/install_forge_linux.sh" \
    "$SCRIPT_BASE_URL/install_forge_linux.sh" \
    "$TARGET_DIR/install_forge_linux.sh" \
    "${PREFIX}install_forge_linux.sh"
	
download_with_fallback \
    "$SCRIPT_BASE_URL/install_forge_windows.bat" \
    "$SCRIPT_BASE_URL/install_forge_windows.bat" \
    "$TARGET_DIR/install_forge_windows.bat" \
    "${PREFIX}install_forge_windows.bat"
	
download_with_fallback \
    "$SCRIPT_BASE_URL/update_forge_linux.sh" \
    "$SCRIPT_BASE_URL/update_forge_linux.sh" \
    "$TARGET_DIR/update_forge_linux.sh" \
    "${PREFIX}update_forge_linux.sh"
	
download_with_fallback \
    "$SCRIPT_BASE_URL/update_forge_windows.bat" \
    "$SCRIPT_BASE_URL/update_forge_windows.bat" \
    "$TARGET_DIR/update_forge_windows.bat" \
    "${PREFIX}update_forge_windows.bat"

log "[INFO] Downloading Platform-tools and required tools for Auto-Installer-Forge script...\n"

download_with_fallback \
    "$BASE_URL/files/platform-tools-latest-linux.zip" \
    "$BASE_URL/files/platform-tools-latest-linux.zip" \
    "$TARGET_DIR/bin/linux/platform-tools-linux.zip" \
    "platform-tools-latest-linux.zip"
	
echo -e "[INFO] Extracting Linux platform-tools..."
$BIN_DIR/7zzs x "$TARGET_DIR/bin/linux/platform-tools-linux.zip" -o"$TARGET_DIR/bin/linux/" -y > /dev/null
log "[SUCCESS] Linux platform-tools extracted.\n"

download_with_fallback \
    "$BASE_URL/files/platform-tools-latest-windows.zip" \
    "$BASE_URL/files/platform-tools-latest-windows.zip" \
    "$TARGET_DIR/bin/windows/platform-tools-windows.zip" \
    "platform-tools-latest-windows.zip"

echo -e "[INFO] Extracting Windows platform-tools..."
$BIN_DIR/7zzs x "$TARGET_DIR/bin/windows/platform-tools-windows.zip" -o"$TARGET_DIR/bin/windows/" -y > /dev/null
log "[SUCCESS] Windows platform-tools extracted.\n"

download_with_fallback \
    "https://github.com/dEajL3kA/tee-win32/releases/download/1.3.3/tee-win32.2023-11-27.zip" \
    "$BASE_URL/files/tee-win32.2023-11-27.zip" \
    "$TARGET_DIR/bin/windows/tee.zip" \
    "tee-win32.2023-11-27.zip"
	
echo -e "[INFO] Extracting tee for logging in windows..."
$BIN_DIR/7zzs x "$TARGET_DIR/bin/windows/tee.zip" -o"$TARGET_DIR/bin/windows/log-tool/" -y > /dev/null
log "[SUCCESS] TEE for windows extracted."

log "[INFO] Now will Download KernelSU NEXT and Magisk APK for ROOT access!\n"

download_with_fallback \
    "https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk" \
    "$BASE_URL/files/Magisk_v30.7.apk" \
    "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/Magisk_v30.7.apk" \
    "Magisk-v30.7.apk"


CONF_FILE="$TARGET_DIR/META-INF/autoinstaller.conf"
if [ -n "$2" ] && [ -f "$2" ]; then
    echo -e "Replacing $CONF_FILE from $2"
    cp "$2" "$CONF_FILE"
else
    echo -e "\nUsing default $CONF_FILE"
fi

extract_magisk_tools "Magisk_v30.7.apk"
patch_twrp_recovery "$2"
patch_magisk_boot "Magisk_v30.7.apk"

IMAGES_DIR="$TARGET_DIR/images"

# Generate the new HASH_PAIRS lines
tmp_hashes=$(mktemp)
for img in "$IMAGES_DIR"/*.img; do
  [ -f "$img" ] || continue
  name=$(basename "$img")

  # Skip super.img because its a big file, if verify then it will take alot of time
  [ "$name" = "super.img" ] && continue

  sha1=$($BIN_DIR/busybox sha1sum "$img" | $BIN_DIR/busybox awk '{print $1}')
  echo "  \"images/$name\" \"$sha1\"" >> "$tmp_hashes"
done

$BIN_DIR/busybox sed -i '/^HASH_PAIRS=(/,/^)/ {
  /^HASH_PAIRS=(/!{/^)/!d}
}' "$CONF_FILE"

# Insert new hashes
$BIN_DIR/busybox sed -i "/^HASH_PAIRS=(/r $tmp_hashes" "$CONF_FILE"

#echo -e "[INFO] HASH_PAIRS inside autoinstaller.conf block updated with current img's in images folder"

# Extract build date
log "[INFO] Detecting build date..."

if [ "$IS_FASTBOOT_ROM" -eq 1 ]; then
    log "[INFO] Fastboot ROM detected. Reading ZIP metadata..."
    raw_date=$($BIN_DIR/7zzs l "$SELECTED_ZIP_FILE" | grep "super.img" | head -n 1 | awk '{print $1}')
    parsed_build_date=$($BIN_DIR/busybox date -d "$raw_date" +"%d %b %Y")
    echo -e "Parsed date (Metadata): $parsed_build_date"

else
    log "[INFO] Extracting build date from ROM..\n"
    raw_build_date=$(strings "$TARGET_DIR/images/super.img" | grep -m 1 'build.date=' | cut -d'=' -f2)
    parsed_input=$(echo "$raw_build_date" | $BIN_DIR/busybox sed -E 's/ [A-Z]{3} / /')
    parsed_build_date=$($BIN_DIR/busybox date -d "$parsed_input" -D "%a %b %d %T %Y" +"%d %b %Y")
    echo -e "Parsed date: $parsed_build_date"
fi

update_field "BUILD_DATE" "Build date" "$parsed_build_date"

log "[SUCCESS] Auto-Installer-Forge files processing finished!\n"

log "[INFO] Now, let's update configration file for this rom!\n"

# fields to update 
#update_field "DEVICE_CODE" "DEVICE CODE"
if [ -n "$2" ] && [ -f "$2" ]; then
    log "[INFO] using config from $2"
    ROOT_TYPE=$(grep '^ROOT_TYPE=' "$CONF_FILE" | cut -d'=' -f2)
else
	update_field "ROM_NAME" "ROM name"
	update_field "ROM_MAINTAINER" "ROM maintainer"
	update_field "ANDROID_VER" "Android version"
	update_field "DEVICE_NAME" "Device name"
	update_field "BUILD_DATE" "Build date"
	update_field "SECURITY_PATCH" "Security patch"
	update_field "ROM_VERSION" "ROM Build version"
    echo -e "\nChoose root method present in ROM:\n"
    echo -e "0) With root (KSU-N - Kernel SU NEXT v3.2.0)"
    echo -e "1) With root (KSU-N - Kernel SU NEXT v1.1.1)"
    echo -e "2) With root (KSU - Kernel SU v1.0.5-80-legacy)"
    echo -e "3) With root (KSU - Kernel SU v1.0.1)"
    echo -e "4) With root (SukiSU-Ultra)"
    echo -e "5) Without root\n"
    while true; do
    echo -n "Enter the number (0-5): "
    read -r ROOT_TYPE
    case $ROOT_TYPE in
        [0-5]) echo; break ;;
        *) echo -e "Invalid input. Please enter a number from 0 to 5.\n" ;;
    esac
    done

    echo -e "\nChoose the default behavior when flashing ROM via recovery:\n"
    echo -e "1) Dirty Flash (Update only - keeps user data)"
    echo -e "2) Clean Flash (Factory reset - wipes all data)\n"
    while true; do
    echo -n "Enter the number (1-2): "
    read -r FORMAT_MODE
    case $FORMAT_MODE in
        1|2) echo; break ;;
        *) echo -e "Invalid input. Please enter 1 or 2.\n" ;;
    esac
    done
    [ "$FORMAT_MODE" -eq 1 ] && FORMAT_MODE=0 || FORMAT_MODE=1
    $BIN_DIR/busybox sed -i "s/^FORMAT_DEFAULT=.*/FORMAT_DEFAULT=$FORMAT_MODE  # set 1 if want format default selected/" "$CONF_FILE"
fi
$BIN_DIR/busybox sed -i "s/^VERIFY_SUPER=.*/VERIFY_SUPER=${VERIFY_SUPER:-0}  # set 1 to enable slow super.img extraction and hashing/" "$CONF_FILE"

case "$ROOT_TYPE" in
  0) root="Root with (KSU-N - Kernel SU NEXT v3.2.0)"
    log "[INFO] Selected Kernel SU NEXT v3.2.0, Downloading APK..."
    download_with_fallback \
        "https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0-spoofed_33129-release.apk" \
        "$BASE_URL/files/KernelSU_Next_v3.2.0.apk" \
        "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/KernelSU_Next_v3.2.0.apk" \
        "KernelSU_Next_v3.2.0.apk"
    ;;
  1) root="Root with (KSU-N - Kernel SU NEXT v1.1.1)"
    log "[INFO] Selected Kernel SU NEXT v1.1.1, Downloading APK..."
    download_with_fallback \
        "https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v1.1.1/KernelSU_Next_v1.1.1_12851-release.apk" \
        "$BASE_URL/files/KernelSU_Next_v1.1.1.apk" \
        "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/KernelSU_Next_v1.1.1.apk" \
        "KernelSU_Next_v1.1.1.apk"
    ;;
  2) root="Root with (KSU - Kernel SU v1.0.5-80-legacy)"
    log "[INFO] Selected Kernel SU v1.0.5-80-legacy, Downloading APK..."
    download_with_fallback \
        "https://github.com/rsuntk/KernelSU/releases/download/v1.0.5-80-legacy/KernelSU_v1.0.5-80-legacy_12328-release.apk" \
        "$BASE_URL/files/KernelSU_v1.0.5-80-legacy.apk" \
        "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/KernelSU_v1.0.5-80-legacy.apk" \
        "KernelSU_v1.0.5-80-legacy.apk"
    ;;
  3) root="Root with (KSU - Kernel SU v1.0.1)"
    log "[INFO] Selected Kernel SU v1.0.1, Downloading APK..."
    download_with_fallback \
        "https://github.com/tiann/KernelSU/releases/download/v1.0.1/KernelSU_v1.0.1_11928-release.apk" \
        "$BASE_URL/files/KernelSU_v1.0.1.apk" \
        "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/KernelSU_v1.0.1.apk" \
        "KernelSU_v1.0.1.apk"
    ;;
  4) root="Root with (SukiSU-Ultra)"
    log "[INFO] Selected SukiSU-Ultra, Downloading APK..."
    download_with_fallback \
        "https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases/download/v3.1.6/SukiSU_v3.1.6_13165-release.apk" \
        "$BASE_URL/files/SukiSU_v3.1.6.apk" \
        "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/SukiSU_v3.1.6.apk" \
        "SukiSU_v3.1.6.apk"
    ;;
  5) root="Without root" ;;
  *) root="Root with (KSU-N - Kernel SU NEXT v3.2.0)"
    download_with_fallback \
        "https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0-spoofed_33129-release.apk" \
        "$BASE_URL/files/KernelSU_Next_v3.2.0.apk" \
        "$TARGET_DIR/ROOT_APK_INSTALL_THIS_ONLY/KernelSU_Next_v3.2.0.apk" \
        "KernelSU_Next_v3.2.0.apk"
    ;;
esac

bases_linux=(install_forge_linux.sh update_forge_linux.sh)
bases_windows=(install_forge_windows.bat update_forge_windows.bat)

# Update root method in Linux flasher scripts
$BIN_DIR/busybox sed -i "s|Root with idk|$root|g" "$CONF_FILE"
for base in "${bases_linux[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i "s/^root=\".*\"/root=\"$root\"/" "$TARGET_DIR/$base"
done
# Update root method in Windows flasher scripts
for base in "${bases_windows[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i "s/^set root=.*/set root=$root/" "$TARGET_DIR/$base"
done

# Extract Rom Maintainer value from config
maintainer=$(grep '^ROM_MAINTAINER=' "$CONF_FILE" | sed -n 's/^ROM_MAINTAINER="\([^"]*\)".*/\1/p')

# Update Maintainer value in Linux flasher scripts
for base in "${bases_linux[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i "s/^ROM_MAINTAINER=\".*\"/ROM_MAINTAINER=\"$maintainer\"/" "$TARGET_DIR/$base"
done
# Update Maintainer value in Windows flasher scripts
for base in "${bases_windows[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i "s/^set ROM_MAINTAINER=.*/set ROM_MAINTAINER=$maintainer/" "$TARGET_DIR/$base"
done

# Extract ROM Name value from config
line=$(grep "^ROM_NAME=" "$CONF_FILE")

# Extract value and optional comment
value=$(echo "$line" | $BIN_DIR/busybox sed -n 's/^ROM_NAME="\([^"]*\)".*/\1/p')
#comment=$(echo "$line" | $BIN_DIR/busybox sed -n 's/^ROM_NAME="[^"]*"[[:space:]]*\(.*\)/\1/p')
#echo -e "Current ROM Name: $value"
#echo -e "Sanitized: $(echo "$value" | $BIN_DIR/busybox tr ' ' '_' | $BIN_DIR/busybox tr -cd '[:alnum:]_-')"

# Sanitize ROM name by removing non-alphanum and replace space with _ underscore
sanitized_name=$(echo "$value" | $BIN_DIR/busybox tr ' ' '_' | $BIN_DIR/busybox tr -cd '[:alnum:]_-')

# Generate ASCII and replace in autoinstaller.conf
$BIN_DIR/figlet -f $BIN_DIR/standard.flf -w 100 $value > $BIN_DIR/ascii
$BIN_DIR/busybox sed -i 's#\\#\\\\#g' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i 's/^/"/;s/$/"/' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '/ASCII_ART_LINES=(/,/^)/ { /ASCII_ART_LINES=(/!{/^)/!d } }' "$CONF_FILE"
$BIN_DIR/busybox sed -i "/ASCII_ART_LINES=(/r $BIN_DIR/ascii" "$CONF_FILE"

# derp it...
lowercase_derp=$(echo "$value" | $BIN_DIR/busybox tr '[:upper:]' '[:lower:]')
if echo "$lowercase_derp" | $BIN_DIR/busybox grep -q "derp"; then
    FIGLET_FONT="$BIN_DIR/sblood.flf"
else
    FIGLET_FONT="$BIN_DIR/nancyj.flf"
fi

# Generate ASCII and replace in Linux flasher scripts
rm -f $BIN_DIR/ascii
$BIN_DIR/figlet -f $FIGLET_FONT -w 100 $value > $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '/^[[:space:]]*$/d' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i 's/^/    echo -e " /;s/$/"/' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '1s/^/    echo\n/' $BIN_DIR/ascii
for base in "${bases_linux[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i '/print_ascii() {/ { n; N; N; N; N; N; N; d; }' "$TARGET_DIR/$base" && \
  $BIN_DIR/busybox sed -i "/print_ascii()/r $BIN_DIR/ascii" "$TARGET_DIR/$base"
done
rm -f $BIN_DIR/ascii
$BIN_DIR/figlet -f $FIGLET_FONT -w 100 $value > $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '/^[[:space:]]*$/d' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i 's/^/    echo -e " /;s/$/\" | tee -a "$log_file"/' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '1s/^/    echo\n/' $BIN_DIR/ascii
for base in "${bases_linux[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i '/print_log_ascii() {/ { n; N; N; N; N; N; N; d; }' "$TARGET_DIR/$base" && \
  $BIN_DIR/busybox sed -i "/print_log_ascii()/r $BIN_DIR/ascii" "$TARGET_DIR/$base"
done

# Generate ASCII and replace in Windows flasher scripts
rm -f $BIN_DIR/ascii
$BIN_DIR/figlet -f $FIGLET_FONT -w 100 $value > $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '/^[[:space:]]*$/d' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i 's/^/echo /' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '1s/^/echo.\n/' $BIN_DIR/ascii
for base in "${bases_windows[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i '/^:print_ascii[[:space:]]*$/ { n; N; N; N; N; N; N; d; }' "$TARGET_DIR/$base" && \
  $BIN_DIR/busybox sed -i "/^:print_ascii[[:space:]]*$/r $BIN_DIR/ascii" "$TARGET_DIR/$base"
done
rm -f $BIN_DIR/ascii
$BIN_DIR/figlet -f $FIGLET_FONT -w 100 $value > $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '/^[[:space:]]*$/d' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i 's/^/call :log  " /;s/$/"/' $BIN_DIR/ascii
$BIN_DIR/busybox sed -i '1s/^/echo.\n/' $BIN_DIR/ascii
for base in "${bases_windows[@]}"; do
  [ -f "$TARGET_DIR/$base" ] && \
  $BIN_DIR/busybox sed -i '/^:print_log_ascii[[:space:]]*$/ { n; N; N; N; N; N; N; d; }' "$TARGET_DIR/$base" && \
  $BIN_DIR/busybox sed -i "/^:print_log_ascii[[:space:]]*$/r $BIN_DIR/ascii" "$TARGET_DIR/$base"
done

# Rename auto-insatller scripts file with new rom name
all_bases=("${bases_linux[@]}" "${bases_windows[@]}")
for base in "${all_bases[@]}"; do
  src="$TARGET_DIR/$base"
  if [ -f "$src" ]; then
    new_name=$(echo "$base" | $BIN_DIR/busybox sed "s/forge/$sanitized_name/")
    $BIN_DIR/busybox mv "$src" "$TARGET_DIR/$new_name"
    #echo -e "Renamed: $base → $new_name"
  fi
done

# Convert .sh and .bat files (once, after renaming)
for file in "$TARGET_DIR"/*.sh "$TARGET_DIR"/*.bat; do
  [ -f "$file" ] || continue
  case "$file" in
    *.sh)  $BIN_DIR/busybox dos2unix "$file" ;;
    *.bat) $BIN_DIR/busybox dos2unix -d "$file" ;;
  esac
done

$BIN_DIR/busybox dos2unix "$CONF_FILE"
log "[INFO] Cleaning up..."
$BIN_DIR/busybox rm -f "$tmp_hashes" "$TARGET_DIR/bin/linux/platform-tools-linux.zip" "$TARGET_DIR/bin/windows/platform-tools-windows.zip" "$TARGET_DIR/bin/windows/tee.zip"
cd
rm -rf $BIN_DIR
echo -e "[SUCCESS] Cleanup complete."

log "[NOTE] you can also change configrations in META-INF/autoinstaller.conf file anytime!"
log "[COMPLETED] Auto-Installer-Forge process finished successfully!\n"
echo "$TARGET_DIR" > "$ORIGINAL_DIR/final_product_path.txt"
