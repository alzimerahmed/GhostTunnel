#!/bin/sh
app_root="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
login_src="${BUILT_PRODUCTS_DIR}/PassepartoutLoginItem.app"
appex_src="${BUILT_PRODUCTS_DIR}/PassepartoutTunnel.appex"
widgets_src="${BUILT_PRODUCTS_DIR}/PassepartoutWidgets.appex"
topshelf_src="${BUILT_PRODUCTS_DIR}/PassepartoutTopShelf.appex"
watch_src="${BUILT_PRODUCTS_DIR}/PassepartoutWatch.app"
sysex_src="${BUILT_PRODUCTS_DIR}/${CFG_TUNNEL_ID}.systemextension"
platform_mac="macosx"
sysex_cfg="ReleaseMac"

mkdir_alias="mkdir -p"
cp_alias="cp -RH"

if [ "$PLATFORM_NAME" == "$platform_mac" ]; then
    login_dst="${app_root}/Contents/Library/LoginItems"
    $mkdir_alias "$login_dst"
    $cp_alias "$login_src" "$login_dst"
fi

if [ "$CONFIGURATION" == "$sysex_cfg" ]; then
    sysex_dst="${app_root}/Contents/Library/SystemExtensions"
    $mkdir_alias "$sysex_dst"
    $cp_alias "$sysex_src" "$sysex_dst"
    exit
fi

if [ "$PLATFORM_NAME" == "$platform_mac" ]; then
    appex_dst="${app_root}/Contents/PlugIns"
else
    appex_dst="${app_root}/PlugIns"
fi
$mkdir_alias "$appex_dst"
$cp_alias "$appex_src" "$appex_dst"
if [ -d "$widgets_src" ]; then
    $cp_alias "$widgets_src" "$appex_dst"
fi
if [ -d "$topshelf_src" ]; then
    $cp_alias "$topshelf_src" "$appex_dst"
fi
# Phase 14: embed the watchOS companion app. Not built on macOS (the target
# dependency is ios-filtered), so the -d guard keeps the mac path a no-op.
if [ -d "$watch_src" ]; then
    watch_dst="${app_root}/Watch"
    $mkdir_alias "$watch_dst"
    $cp_alias "$watch_src" "$watch_dst"
fi
