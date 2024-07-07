#!/system/bin/sh

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

if [ "$BOOTMODE" != true ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Please install in Magisk"
  ui_print "! Install from recovery is NOT supported"
  abort "-----------------------------------------------------------"
fi

# if [ "$API" -lt 28 ]; then
  # ui_print "! Unsupported sdk: $API"
  # abort "! Minimal supported sdk is 28 (Android 9)"
# else
  # ui_print "- Device sdk: $API"
# fi

service_dir="/data/adb/service.d"
ui_print "- Magisk version: $MAGISK_VER ($MAGISK_VER_CODE)"

mkdir -p "${service_dir}"

if [ -d "/data/adb/modules/box_for_magisk" ]; then
  rm -rf "/data/adb/modules/box_for_magisk"
  ui_print "- Old module deleted."
fi

ui_print "- Installing Box for Magisk"
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

if [ -d "/data/adb/box" ]; then
  ui_print "- Backup box"
  latest=$(date '+%Y-%m-%d_%H-%M')
  mkdir -p "/data/adb/box/${latest}"
  mv /data/adb/box/* "/data/adb/box/${latest}/"
  mv "$MODPATH/box/"* /data/adb/box/
else
  mv "$MODPATH/box" /data/adb/
fi

ui_print "- Create directories"
mkdir -p /data/adb/box/
mkdir -p /data/adb/box/run/
mkdir -p /data/adb/box/bin/

ui_print "- Extract the files uninstall.sh and box_service.sh into the $MODPATH folder and ${service_dir}"
unzip -j -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >&2
unzip -j -o "$ZIPFILE" 'box_service.sh' -d "${service_dir}" >&2

ui_print "- Setting permissions"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive /data/adb/box/ 0 3005 0755 0644
set_perm_recursive /data/adb/box/scripts/  0 3005 0755 0700
set_perm ${service_dir}/box_service.sh  0  0  0755
set_perm $MODPATH/uninstall.sh  0  0  0755
set_perm /data/adb/box/scripts/  0  0  0755

# fix "set_perm_recursive /data/adb/box/scripts" not working on some phones.
chmod ugo+x ${service_dir}/box_service.sh
chmod ugo+x $MODPATH/uninstall.sh
chmod ugo+x /data/adb/box/scripts/*

ui_print "-----------------------------------------------------------"
ui_print "- Do you want to download Kernel(xray hysteria clash v2fly sing-box) and GeoX(geosite geoip mmdb)? size: ±100MB."
ui_print "- Make sure you have a good internet connection."
ui_print "- [ Vol UP(+): Yes ]"
ui_print "- [ Vol DOWN(-): No ]"

START_TIME=$(date +%s)
while true ; do
  NOW_TIME=$(date +%s)
  timeout 1 getevent -lc 1 2>&1 | grep KEY_VOLUME > "$TMPDIR/events"
  if [ $(( NOW_TIME - START_TIME )) -gt 9 ] ; then
    ui_print "- No input detected after 10 seconds"
    break
  else
    if $(cat $TMPDIR/events | grep -q KEY_VOLUMEUP) ; then
      ui_print "- It will take a while...."
      /data/adb/box/scripts/box.tool all
      break
    elif $(cat $TMPDIR/events | grep -q KEY_VOLUMEDOWN) ; then
      ui_print "- Skip download Kernel and Geox"
      break
    fi
  fi
done

if [ -z "$(find /data/adb/box/bin -type f)" ]; then
  sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ 😱 Module installed but you need to download Kernel(xray hysteria clash v2fly sing-box) and GeoX(geosite geoip mmdb) manually ] /g' $MODPATH/module.prop
fi

sed -i "s/name=.*/name=Box for Magisk/g" $MODPATH/module.prop

ui_print "- Delete leftover files"
rm -rf /data/adb/box/bin/.bin
rm -rf $MODPATH/box
rm -f $MODPATH/box_service.sh

ui_print "- Installation is complete, reboot your device"
