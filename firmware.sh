#!/bin/bash
#


#############################
# Install coreboot Firmware #
#############################
function flash_coreboot()
{

fwTypeStr=""
if [[ "$hasLegacyOption" = true && "$unlockMenu" = true ]]; then
    fwTypeStr="Legacy/UEFI"
else
    fwTypeStr="UEFI"
fi

echo_green "\nInstall/Update ${fwTypeStr} Full ROM Firmware"
echo_yellow "IMPORTANT: flashing the firmware has the potential to brick your device, 
requiring relatively inexpensive hardware and some technical knowledge to 
recover.Not all boards can be tested prior to release, and even then slight 
differences in hardware can lead to unforseen failures.
If you don't have the ability to recover from a bad flash, you're taking a risk.

You have been warned."

[[ "$isChromeOS" = true ]] && echo_yellow "Also, flashing Full ROM firmware will remove your ability to run ChromeOS."

read -ep "Do you wish to continue? [y/N] "
[[ "$REPLY" = "y" || "$REPLY" = "Y" ]] || return

#spacing
echo -e ""

# ensure hardware write protect disabled
[[ "$wpEnabled" = true ]] && { exit_red "\nHardware write-protect enabled, cannot flash Full ROM firmware."; return 1; }

#special warning for CR50 devices
if [[ "$isStock" = true && "$hasCR50" = true ]]; then
echo_yellow "NOTICE: flashing your Chromebook is serious business. 
To ensure recovery in case something goes wrong when flashing,
be sure to set the ccd capability 'FlashAP Always' using your 
USB-C debug cable, otherwise recovery will involve disassembling
your device (which is very difficult in some cases)."

echo_yellow "If you wish to continue, type: 'I ACCEPT' and press enter."
read -e
[[ "$REPLY" = "I ACCEPT" ]] || return
fi

#Only flash UEFI  firmware
useUEFI=true

#UEFI notice if flashing from ChromeOS or Legacy
if [[ "$useUEFI" = true && ! -d /sys/firmware/efi ]]; then
    [[ "$isChromeOS" = true ]] && currOS="ChromeOS" || currOS="Your Legacy-installed OS"
    echo_yellow "
NOTE: After flashing UEFI firmware, you will need to install a UEFI-compatible
OS; ${currOS} will no longer be bootable. See https://mrchromebox.tech/#faq"
    REPLY=""
    read -ep "Press Y to continue or any other key to abort. "
    [[ "$REPLY" = "y" || "$REPLY" = "Y" ]] || return
fi

#determine correct file / URL
firmware_source=${fullrom_source}
if [[ "$hasUEFIoption" = true || "$hasLegacyOption" = true ]]; then
    if [ "$useUEFI" = true ]; then
        eval coreboot_file=$`echo "coreboot_uefi_${device}"`
    else
        eval coreboot_file=$`echo "coreboot_${device}"`
    fi
else
    exit_red "Unknown or unsupported device (${device^^}); cannot continue."; return 1
fi

#auron special case (upgrade from coolstar legacy rom)
if [ "$device" = "auron" ]; then
    echo -e ""
    echo_yellow "Unable to determine Chromebook model"
    echo -e "Because of your current firmware, I'm unable to
determine the exact mode of your Chromebook.  Are you using
an Acer C740 (Auron_Paine) or Acer C910/CB5-571 (Auron_Yuna)?
"
    REPLY=""
    while [[ "$REPLY" != "P" && "$REPLY" != "p" && "$REPLY" != "Y" && "$REPLY" != "y"  ]]
    do
        read -ep "Enter 'P' for Auron_Paine, 'Y' for Auron_Yuna: "
        if [[ "$REPLY" = "Y" || "$REPLY" = "y" ]]; then
            if [ "$useUEFI" = true ]; then
                coreboot_file=${coreboot_uefi_auron_yuna}
            else
                coreboot_file=${coreboot_auron_yuna}
            fi
        else
            if [ "$useUEFI" = true ]; then
                coreboot_file=${coreboot_uefi_auron_paine}
            else
                coreboot_file=${coreboot_auron_paine}
            fi
        fi
    done
fi

#rammus special case (upgrade from older UEFI firmware)
if [ "$device" = "rammus" ]; then
    echo -e ""
    echo_yellow "Unable to determine Chromebook model"
    echo -e "Because of your current firmware, I'm unable to
determine the exact mode of your Chromebook.  Are you using
an Asus C425 (LEONA) or Asus C433/C434 (SHYVANA)?
"
    REPLY=""
    while [[ "$REPLY" != "L" && "$REPLY" != "l" && "$REPLY" != "S" && "$REPLY" != "s"  ]]
    do
        read -ep "Enter 'L' for LEONA, 'S' for SHYVANA: "
        if [[ "$REPLY" = "S" || "$REPLY" = "s" ]]; then
            coreboot_file=${coreboot_uefi_shyvana}
        else
            coreboot_file=${coreboot_uefi_leona}
        fi
    done
fi

#extract device serial if present in cbfs
${cbfstoolcmd} /tmp/bios.bin extract -n serial_number -f /tmp/serial.txt >/dev/null 2>&1

# create backup if existing firmware is stock
if [[ "$isStock" == "true" ]]; then
    if [[ "$hasShellball" = "false" && "$isEOL" = "false" ]]; then
        REPLY=y
    else
        echo_yellow "\nCreate a backup copy of your stock firmware?"
        read -ep "This is highly recommended in case you wish to return your device to stock
configuration/run ChromeOS, or in the (unlikely) event that things go south
and you need to recover using an external EEPROM programmer. [Y/n] "
    fi
    [[ "$REPLY" = "n" || "$REPLY" = "N" ]] && true || backup_firmware
    #check that backup succeeded
    [ $? -ne 0 ] && return 1
fi

#download firmware file
cd /tmp
echo_yellow "\nDownloading Full ROM firmware\n(${coreboot_file})"
$CURL -sLO "${firmware_source}${coreboot_file}"
$CURL -sLO "${firmware_source}${coreboot_file}.sha1"

#verify checksum on downloaded file
sha1sum -c ${coreboot_file}.sha1 --quiet > /dev/null 2>&1
[[ $? -ne 0 ]] && { exit_red "Firmware download checksum fail; download corrupted, cannot flash."; return 1; }

#persist serial number?
if [ -f /tmp/serial.txt ]; then
    echo_yellow "Persisting device serial number"
    ${cbfstoolcmd} ${coreboot_file} add -n serial_number -f /tmp/serial.txt -t raw > /dev/null 2>&1
fi

#Persist RW_MRC_CACHE UEFI Full ROM firmware
${cbfstoolcmd} /tmp/bios.bin read -r RW_MRC_CACHE -f /tmp/mrc.cache > /dev/null 2>&1
if [[ $isUEFI = "true" &&  $isFullRom = "true" && $? -eq 0 ]]; then
    ${cbfstoolcmd} ${coreboot_file} write -r RW_MRC_CACHE -f /tmp/mrc.cache > /dev/null 2>&1
fi

#Persist SMMSTORE if exists
${cbfstoolcmd} /tmp/bios.bin read -r SMMSTORE -f /tmp/smmstore > /dev/null 2>&1
if [[ $useUEFI = "true" &&  $? -eq 0 ]]; then
    ${cbfstoolcmd} ${coreboot_file} write -r SMMSTORE -f /tmp/smmstore > /dev/null 2>&1
fi

# persist VPD if possible
if extract_vpd /tmp/bios.bin ; then
    # try writing to RO_VPD FMAP region
    if ! ${cbfstoolcmd} ${coreboot_file} write -r RO_VPD -f /tmp/vpd.bin > /dev/null 2>&1 ; then
        # fall back to vpd.bin in CBFS
        ${cbfstoolcmd} ${coreboot_file} add -n vpd.bin -f /tmp/vpd.bin -t raw > /dev/null 2>&1
    fi
fi

#disable software write-protect
echo_yellow "Disabling software write-protect and clearing the WP range"
${flashromcmd} --wp-disable > /dev/null 2>&1
if [[ $? -ne 0 && $swWp = "enabled" ]]; then
    exit_red "Error disabling software write-protect; unable to flash firmware."; return 1
fi

#clear SW WP range
${flashromcmd} --wp-range 0 0 > /dev/null 2>&1
if [ $? -ne 0 ]; then
	# use new command format as of commit 99b9550
	${flashromcmd} --wp-range 0,0 > /dev/null 2>&1
	if [[ $? -ne 0 && $swWp = "enabled" ]]; then
		exit_red "Error clearing software write-protect range; unable to flash firmware."; return 1
	fi
fi

#flash Full ROM firmware

#flash without verify, to avoid IFD mismatch upon verification 
echo_yellow "Installing Full ROM firmware (may take up to 90s)"
${flashromcmd} -n -w "${coreboot_file}" -o /tmp/flashrom.log > /dev/null 2>&1
if [ $? -ne 0 ]; then
    cat /tmp/flashrom.log
    exit_red "An error occurred flashing the Full ROM firmware. DO NOT REBOOT!"; return 1
else
    echo_green "Full ROM firmware successfully installed/updated."

    #Prevent from trying to boot stock ChromeOS install
    if [[ "$isStock" = true && "$isChromeOS" = true ]]; then
       rm -rf /tmp/boot/efi > /dev/null 2>&1
       rm -rf /tmp/boot/syslinux > /dev/null 2>&1
    fi

    #Warn about long RAM training time
    echo_yellow "IMPORTANT:\nThe first boot after flashing may take substantially
longer than subsequent boots -- up to 30s or more.
Be patient and eventually your device will boot :)"

    # Add note on touchpad firmware for EVE
    if [[ "${device^^}" = "EVE" && "$isStock" = true ]]; then
        echo_yellow "IMPORTANT:\n
If you're going to run Windows on your Pixelbook, you must downgrade
the touchpad firmware now (before rebooting) otherwise it will not work.
Select the D option from the main main in order to do so."
    fi
    #set vars to indicate new firmware type
    isStock=false
    isFullRom=true
    # Add NVRAM reset note for 4.12 release
    if [[ "$isUEFI" = true && "$useUEFI" = true ]]; then
        echo_yellow "IMPORTANT:\n
This update uses a new format to store UEFI NVRAM data, and
will reset your BootOrder and boot entries. You may need to 
manually Boot From File and reinstall your bootloader if 
booting from the internal storage device fails."
    fi
    if [[ "$useUEFI" = "true" ]]; then
        firmwareType="Full ROM / UEFI (pending reboot)"
        isUEFI=true
    else
        firmwareType="Full ROM / Legacy (pending reboot)"
    fi
fi

read -ep "Press [Enter] to return to the main menu."
}

#########################
# Downgrade Touchpad FW #
#########################
function downgrade_touchpad_fw()
{
# offer to downgrade touchpad firmware on EVE
if [[ "${device^^}" = "EVE" ]]; then
    echo_green "\nDowngrade Touchpad Firmware"
    echo_yellow "If you plan to run Windows on your Pixelbook, it is necessary to downgrade 
the touchpad firmware, otherwise the touchpad will not work."
    echo_yellow "You should do this after flashing the UEFI firmware, but before rebooting."
    read -ep "Do you wish to downgrade the touchpad firmware now? [y/N] "
    if [[ "$REPLY" = "y" || "$REPLY" = "Y" ]] ; then
        # ensure firmware write protect disabled
        [[ "$wpEnabled" = true ]] && { exit_red "\nHardware write-protect enabled, cannot downgrade touchpad firmware."; return 1; }
        # download TP firmware
        echo_yellow "\nDownloading touchpad firmware\n(${touchpad_eve_fw})"
        $CURL -s -LO "${other_source}${touchpad_eve_fw}"
        $CURL -s -LO "${other_source}${touchpad_eve_fw}.sha1"
        #verify checksum on downloaded file
        sha1sum -c ${touchpad_eve_fw}.sha1 --quiet > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            # flash TP firmware
            echo_green "Flashing touchpad firmware -- do not touch the touchpad while updating!"
            ${flashromcmd#${flashrom_params}} -p ec:type=tp -i EC_RW -w ${touchpad_eve_fw} -o /tmp/flashrom.log >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo_green "Touchpad firmware successfully downgraded."
                echo_yellow "Please reboot your Pixelbook now."
            else 
                echo_red "Error flashing touchpad firmware:"
                cat /tmp/flashrom.log
                echo_yellow "\nThis function sometimes doesn't work under Linux, in which case it is\nrecommended to try under ChromiumOS."
            fi
        else
            echo_red "Touchpad firmware download checksum fail; download corrupted, cannot flash."
        fi
        read -ep "Press [Enter] to return to the main menu."
    fi
fi
}

##########################
# Restore Stock Firmware #
##########################
function restore_stock_firmware()
{
echo_green "\nRestore Stock Firmware"
echo_yellow "Standard disclaimer: flashing the firmware has the potential to
brick your device, requiring relatively inexpensive hardware and some
technical knowledge to recover.  You have been warned."

read -ep "Do you wish to continue? [y/N] "
[[ "$REPLY" = "Y" || "$REPLY" = "y" ]] || return

# check if EOL
if [ "$isEOL" = true ]; then
	echo_yellow "\nVERY IMPORTANT:
Your device has reached end of life (EOL) and is no longer supported by Google.
Returning the to stock firmware **IS NOT REFCOMMENDED**.
MrChromebox will not provide any support for EOL devices running anything
other than the latest UEFI Full ROM firmware release."

	read -ep "Do you wish to continue? [y/N] "
	[[ "$REPLY" = "Y" || "$REPLY" = "y" ]] || return
fi

#spacing
echo -e ""

# ensure hardware write protect disabled
[[ "$wpEnabled" = true ]] && { exit_red "\nHardware write-protect enabled, cannot restore stock firmware."; return 1; }

firmware_file=""

read -ep "Do you have a firmware backup file on USB? [y/N] "
if [[ "$REPLY" = "y" || "$REPLY" = "Y" ]]; then
    read -ep "
Connect the USB/SD device which contains the backed-up stock firmware and press [Enter] to continue. "
    list_usb_devices
    [ $? -eq 0 ] || { exit_red "No USB devices available to read firmware backup."; return 1; }
    read -ep "Enter the number for the device which contains the stock firmware backup: " usb_dev_index
    [ $usb_dev_index -gt 0 ] && [ $usb_dev_index  -le $num_usb_devs ] || { exit_red "Error: Invalid option selected."; return 1; }
    usb_device="${usb_devs[${usb_dev_index}-1]}"
    mkdir /tmp/usb > /dev/null 2>&1
    mount "${usb_device}" /tmp/usb > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        mount "${usb_device}1" /tmp/usb
    fi
    if [ $? -ne 0 ]; then
        echo_red "USB device failed to mount; cannot proceed."
        read -ep "Press [Enter] to return to the main menu."
        umount /tmp/usb > /dev/null 2>&1
        return
    fi
    #select file from USB device
    echo_yellow "\n(Potential) Firmware Files on USB:"
    ls  /tmp/usb/*.{rom,ROM,bin,BIN} 2>/dev/null | xargs -n 1 basename 2>/dev/null
    if [ $? -ne 0 ]; then
        echo_red "No firmware files found on USB device."
        read -ep "Press [Enter] to return to the main menu."
        umount /tmp/usb > /dev/null 2>&1
        return
    fi
    echo -e ""
    read -ep "Enter the firmware filename:  " firmware_file
    firmware_file=/tmp/usb/${firmware_file}
    if [ ! -f ${firmware_file} ]; then
        echo_red "Invalid filename entered; unable to restore stock firmware."
        read -ep "Press [Enter] to return to the main menu."
        umount /tmp/usb > /dev/null 2>&1
        return
    fi
    #text spacing
    echo -e ""
else
    exit_red "No stock firmware available to restore"
	return 1
fi

#disable software write-protect
${flashromcmd} --wp-disable > /dev/null 2>&1
if [[ $? -ne 0 && $swWp = "enabled" ]]; then
#if [[ $? -ne 0 && ( "$isBsw" = false || "$isFullRom" = false ) ]]; then
    exit_red "Error disabling software write-protect; unable to restore stock firmware."; return 1
fi

#clear SW WP range
${flashromcmd} --wp-range 0 0 > /dev/null 2>&1
if [ $? -ne 0 ]; then
	# use new command format as of commit 99b9550
	${flashromcmd} --wp-range 0,0 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		exit_red "Error clearing software write-protect range; unable to restore stock firmware."; return 1
	fi
fi

#flash stock firmware
echo_yellow "Restoring stock firmware"
# we won't verify here, since we need to flash the entire BIOS region
# but don't want to get a mismatch from the IFD or ME 
${flashromcmd} -n -w "${firmware_file}" -o /tmp/flashrom.log > /dev/null 2>&1
if [ $? -ne 0 ]; then
    cat /tmp/flashrom.log
    exit_red "An error occurred restoring the stock firmware. DO NOT REBOOT!"; return 1
fi

#all good
echo_green "Stock firmware successfully restored."
echo_green "After rebooting, you will need to restore ChromeOS using the ChromeOS recovery media,
then re-run this script to reset the Firmware Boot Flags (GBB Flags) to factory default."
read -ep "Press [Enter] to return to the main menu."
#set vars to indicate new firmware type
isStock=true
isFullRom=false
isUEFI=false
firmwareType="Stock ChromeOS (pending reboot)"
}


########################
# Extract firmware VPD #
########################
function extract_vpd()
{
#check params
[[ -z "$1" ]] && { exit_red "Error: extract_vpd(): missing function parameter"; return 1; }

firmware_file="$1"

#try FMAP extraction
if ! ${cbfstoolcmd} ${firmware_file} read -r RO_VPD -f /tmp/vpd.bin >/dev/null 2>&1 ; then
    #try CBFS extraction
    if ! ${cbfstoolcmd} ${firmware_file} extract -n vpd.bin -f /tmp/vpd.bin >/dev/null 2>&1 ; then
        return 1
    fi
fi
echo_yellow "VPD extracted from current firmware"
return 0
}


#########################
# Backup stock firmware #
#########################
function backup_firmware()
{
echo -e ""
read -ep "Connect the USB/SD device to store the firmware backup and press [Enter]
to continue.  This is non-destructive, but it is best to ensure no other
USB/SD devices are connected. "
list_usb_devices
if [ $? -ne 0 ]; then
    backup_fail "No USB devices available to store firmware backup."
    return 1
fi

read -ep "Enter the number for the device to be used for firmware backup: " usb_dev_index
if [ $usb_dev_index -le 0 ] || [ $usb_dev_index  -gt $num_usb_devs ]; then
    backup_fail "Error: Invalid option selected."
    return 1
fi

usb_device="${usb_devs[${usb_dev_index}-1]}"
mkdir /tmp/usb > /dev/null 2>&1
mount "${usb_device}" /tmp/usb > /dev/null 2>&1
if [ $? != 0 ]; then
    mount "${usb_device}1" /tmp/usb
fi
if [ $? -ne 0 ]; then
    backup_fail "USB backup device failed to mount; cannot proceed."
    return 1
fi
backupname="stock-firmware-${boardName}-$(date +%Y%m%d).rom"
echo_yellow "\nSaving firmware backup as ${backupname}"
cp /tmp/bios.bin /tmp/usb/${backupname}
if [ $? -ne 0 ]; then
    backup_fail "Failure reading stock firmware for backup; cannot proceed."
    return 1
fi
sync
umount /tmp/usb > /dev/null 2>&1
rmdir /tmp/usb
echo_green "Firmware backup complete. Remove the USB stick and press [Enter] to continue."
read -ep ""
}

function backup_fail()
{
umount /tmp/usb > /dev/null 2>&1
rmdir /tmp/usb > /dev/null 2>&1
exit_red "\n$@"
}


function clear_nvram() {
echo_green "\nClear UEFI NVRAM"
echo_yellow "Clearing the NVRAM will remove all EFI variables\nand reset the boot order to the default."
read -ep "Would you like to continue? [y/N] "
[[ "$REPLY" = "y" || "$REPLY" = "Y" ]] || return

echo_yellow "\nClearing NVRAM..."
${flashromcmd} -E -i SMMSTORE > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo_red "\nFailed to erase SMMSTORE firmware region; NVRAM not cleared."
    return 1;
fi
#all done
echo_green "NVRAM has been cleared."
read -ep "Press Enter to continue"
}

########################
# Firmware Update Menu #
########################
function menu_fwupdate() {

    if [[ "$isFullRom" = true ]]; then
        uefi_menu
    else
        stock_menu
    fi
}

function show_header() {
    printf "\ec"
    echo -e "${NORMAL}\n ChromeOS Device Firmware Utility Script ${script_date} ${NORMAL}"
    echo -e "${NORMAL} (c) Mr Chromebox <mrchromebox@gmail.com> ${NORMAL}"
    echo -e "${MENU}*********************************************************${NORMAL}"
    echo -e "${MENU}**${NUMBER}   Device: ${NORMAL}${deviceDesc} (${boardName^^})"
    echo -e "${MENU}**${NUMBER} Platform: ${NORMAL}$deviceCpuType"
    echo -e "${MENU}**${NUMBER}  Fw Type: ${NORMAL}$firmwareType"
    echo -e "${MENU}**${NUMBER}   Fw Ver: ${NORMAL}$fwVer ($fwDate)"
    if [[ $isUEFI == true && $hasUEFIoption = true ]]; then
        # check if update available
        curr_yy=`echo $fwDate | cut -f 3 -d '/'`
        curr_mm=`echo $fwDate | cut -f 1 -d '/'`
        curr_dd=`echo $fwDate | cut -f 2 -d '/'`
        eval coreboot_file=$`echo "coreboot_uefi_${device}"`
        date=`echo $coreboot_file | grep -o "mrchromebox.*" | cut -f 2 -d '_' | cut -f 1 -d '.'`
        uefi_yy=`echo $date | cut -c1-4`
        uefi_mm=`echo $date | cut -c5-6`
        uefi_dd=`echo $date | cut -c7-8`
        if [[ ("$firmwareType" != *"pending"*) && (($uefi_yy > $curr_yy) || \
            ($uefi_yy == $curr_yy && $uefi_mm > $curr_mm) || \
            ($uefi_yy == $curr_yy && $uefi_mm == $curr_mm && $uefi_dd > $curr_dd)) ]]; then
            echo -e "${MENU}**${NORMAL}           ${GREEN_TEXT}Update Available ($uefi_mm/$uefi_dd/$uefi_yy)${NORMAL}"
        fi
    fi
    if [ "$wpEnabled" = true ]; then
        echo -e "${MENU}**${NUMBER}    Fw WP: ${RED_TEXT}Enabled${NORMAL}"
	WP_TEXT=${RED_TEXT}
    else
        echo -e "${MENU}**${NUMBER}    Fw WP: ${NORMAL}Disabled"
	WP_TEXT=${GREEN_TEXT}
    fi
    echo -e "${MENU}*********************************************************${NORMAL}"
}

function stock_menu() {
    
    show_header

    if [[ "$unlockMenu" = true || ( "$isFullRom" = false && "$isBootStub" = false && "$isUnsupported" = false && "$isEOL" = false ) ]]; then
        echo -e "${MENU}**${WP_TEXT}     ${NUMBER} 1)${MENU} Install/Update RW_LEGACY Firmware ${NORMAL}"
    else
        echo -e "${GRAY_TEXT}**     ${GRAY_TEXT} 1)${GRAY_TEXT} Install/Update RW_LEGACY Firmware ${NORMAL}"
    fi

    if [[ "$unlockMenu" = true || "$hasUEFIoption" = true || "$hasLegacyOption" = true ]]; then
        echo -e "${MENU}**${WP_TEXT} [WP]${NUMBER} 2)${MENU} Install/Update UEFI (Full ROM) Firmware ${NORMAL}"
    else
        echo -e "${GRAY_TEXT}**     ${GRAY_TEXT} 2)${GRAY_TEXT} Install/Update UEFI (Full ROM) Firmware${NORMAL}"
    fi
    if [[ "${device^^}" = "EVE" ]]; then
        echo -e "${MENU}**${WP_TEXT} [WP]${NUMBER} D)${MENU} Downgrade Touchpad Firmware ${NORMAL}"
    fi
    if [[ "$unlockMenu" = true || "$isUEFI" = true ]]; then
        echo -e "${MENU}**${WP_TEXT}     ${NUMBER} C)${MENU} Clear UEFI NVRAM ${NORMAL}"
    fi
    echo -e "${MENU}*********************************************************${NORMAL}"
    echo -e "${ENTER_LINE}Select a menu option or${NORMAL}"
    echo -e "${nvram}${RED_TEXT}R${NORMAL} to reboot ${NORMAL} ${RED_TEXT}P${NORMAL} to poweroff ${NORMAL} ${RED_TEXT}Q${NORMAL} to quit ${NORMAL}"
    
    read -e opt
    case $opt in

        1)  if [[ "$unlockMenu" = true || "$isChromeOS" = true || "$isFullRom" = false \
                    && "$isBootStub" = false && "$isUnsupported" = false && "$isEOL" = false  ]]; then
                flash_rwlegacy
            fi
            menu_fwupdate
            ;;

        2)  if [[  "$unlockMenu" = true || "$hasUEFIoption" = true || "$hasLegacyOption" = true ]]; then
                flash_coreboot
            fi
            menu_fwupdate
            ;;

        [dD])  if [[  "${device^^}" = "EVE" ]]; then
                downgrade_touchpad_fw
            fi
            menu_fwupdate
            ;;

        [rR])  echo -e "\nRebooting...\n";
            cleanup
            reboot
            exit
            ;;

        [pP])  echo -e "\nPowering off...\n";
            cleanup
            poweroff
            exit
            ;;

        [qQ])  cleanup;
            exit;
            ;;

        [U])  if [ "$unlockMenu" = false ]; then
                echo_yellow "\nAre you sure you wish to unlock all menu functions?"
                read -ep "Only do this if you really know what you are doing... [y/N]? "
                [[ "$REPLY" = "y" || "$REPLY" = "Y" ]] && unlockMenu=true
            fi
            menu_fwupdate
            ;;

        [cC]) if [[ "$unlockMenu" = true || "$isUEFI" = true ]]; then
                clear_nvram
            fi
            menu_fwupdate
            ;;

        *)  clear
            menu_fwupdate;
            ;;
    esac
}

function uefi_menu() {
    
    show_header

    if [[ "$hasUEFIoption" = true ]]; then
        echo -e "${MENU}**${WP_TEXT} [WP]${NUMBER} 1)${MENU} Install/Update UEFI (Full ROM) Firmware ${NORMAL}"
    else
        echo -e "${GRAY_TEXT}**     ${GRAY_TEXT} 1)${GRAY_TEXT} Install/Update UEFI (Full ROM) Firmware${NORMAL}"
    fi
    if [[ "$isChromeOS" = false  && "$isFullRom" = true ]]; then
        echo -e "${MENU}**${WP_TEXT} [WP]${NUMBER} 2)${MENU} Restore Stock Firmware ${NORMAL}"
    else
        echo -e "${GRAY_TEXT}**     ${GRAY_TEXT} 2)${GRAY_TEXT} Restore Stock ChromeOS Firmware ${NORMAL}"
    fi
    if [[ "${device^^}" = "EVE" ]]; then
        echo -e "${MENU}**${WP_TEXT} [WP]${NUMBER} D)${MENU} Downgrade Touchpad Firmware ${NORMAL}"
    fi
    if [[ "$unlockMenu" = true || "$isUEFI" = true ]]; then
        echo -e "${MENU}**${WP_TEXT}     ${NUMBER} C)${MENU} Clear UEFI NVRAM ${NORMAL}"
    fi
    echo -e "${MENU}*********************************************************${NORMAL}"
    echo -e "${ENTER_LINE}Select a menu option or${NORMAL}"
    echo -e "${nvram}${RED_TEXT}R${NORMAL} to reboot ${NORMAL} ${RED_TEXT}P${NORMAL} to poweroff ${NORMAL} ${RED_TEXT}Q${NORMAL} to quit ${NORMAL}"

    read -e opt
    case $opt in

        1)  if [[ "$hasUEFIoption" = true ]]; then
                flash_coreboot
            fi
            uefi_menu
            ;;

        2)  if [[ "$isChromeOS" = false && "$isUnsupported" = false \
                    && "$isFullRom" = true ]]; then
                restore_stock_firmware
                menu_fwupdate
            else
              uefi_menu
            fi
            ;;

        [dD])  if [[  "${device^^}" = "EVE" ]]; then
                downgrade_touchpad_fw
            fi
            uefi_menu
            ;;

        [rR])  echo -e "\nRebooting...\n";
            cleanup
            reboot
            exit
            ;;

        [pP])  echo -e "\nPowering off...\n";
            cleanup
            poweroff
            exit
            ;;

        [qQ])  cleanup;
            exit;
            ;;

        [cC]) if [[ "$isUEFI" = true ]]; then
                clear_nvram
            fi
            uefi_menu
            ;;

        *)  clear
            uefi_menu;
            ;;
    esac
}
