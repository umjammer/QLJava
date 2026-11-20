#!/bin/zsh -f
#
# Builds QLJavaApp.app (which embeds the QLJava preview and thumbnail Quick Look extensions),
# installs it and registers the extensions with the system.
#
# usage: ./install.sh [install|uninstall|status]   (default: install)
#
# environment:
#   PREFIX         install directory          (default: ~/Applications)
#   CONFIGURATION  Xcode build configuration  (default: Release)
#

set -euo pipefail

cd "${0:A:h}"

APP_NAME=QLJavaApp
PREFIX="${PREFIX:-$HOME/Applications}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="$PWD/build"
DEST="$PREFIX/$APP_NAME.app"
EXT_IDS=(com.vavi.QLJava.Preview com.vavi.QLJava.Thumbnail)
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

info() { print -P "%F{green}==>%f $*" }
warn() { print -P "%F{yellow}warning:%f $*" >&2 }

# move to the trash instead of deleting
trash() {
  local target=$1
  [[ -e $target ]] || return 0
  local name=${target:t}
  local dest="$HOME/.Trash/$name"
  [[ -e $dest ]] && dest="$HOME/.Trash/${name:r} $(date +%Y%m%d-%H%M%S).${name:e}"
  mv "$target" "$dest"
}

# paths pluginkit currently knows for an extension id
registered_paths() {
  pluginkit -m -A -D -v -i "$1" 2>/dev/null | awk -F'\t' 'NF>=4 {print $NF}'
}

# drop registrations of our extensions that are not inside $DEST (Xcode DerivedData, old copies, ...)
unregister_stale() {
  local id p
  for id in $EXT_IDS; do
    registered_paths $id | while read -r p; do
      [[ -z $p || $p == "$DEST"/* ]] && continue
      info "unregistering stale $id at $p"
      pluginkit -r "$p" 2>/dev/null || true
      [[ -d ${p:h:h:h} && ${p:h:h:h} == *.app ]] && $LSREGISTER -u "${p:h:h:h}" 2>/dev/null || true
    done
  done
  # legacy: appex bundles copied into ~/Library/QuickLook are never loaded by macOS
  local legacy
  for legacy in "$HOME/Library/QuickLook/QLJava.appex" "$HOME/Library/QuickLook/QLJavaThumbnail.appex"; do
    if [[ -e $legacy ]]; then
      info "moving legacy $legacy to the trash"
      trash "$legacy"
    fi
  done
}

reset_quicklook() {
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
}

status() {
  local id line ok=0
  for id in $EXT_IDS; do
    line=$(pluginkit -m -v -i $id 2>/dev/null | head -1)
    if [[ -z $line ]]; then
      warn "$id: not registered"; ok=1
    elif [[ $line == +* ]]; then
      info "$id: enabled  (${line##*$'\t'})"
    else
      warn "$id: registered but not enabled -> System Settings > General > Login Items & Extensions > Quick Look"
      ok=1
    fi
  done
  return $ok
}

do_install() {
  info "building $APP_NAME ($CONFIGURATION)"
  xcodebuild -project QLJava.xcodeproj -target $APP_NAME -configuration $CONFIGURATION \
    SYMROOT="$BUILD_DIR" build -quiet

  local built="$BUILD_DIR/$CONFIGURATION/$APP_NAME.app"
  [[ -d $built ]] || { warn "build product not found: $built"; exit 1 }

  pkill -x $APP_NAME 2>/dev/null || true

  info "installing to $DEST"
  mkdir -p "$PREFIX"
  if [[ -e $DEST ]]; then
    pluginkit -r "$DEST/Contents/PlugIns/QLJava.appex" 2>/dev/null || true
    pluginkit -r "$DEST/Contents/PlugIns/QLJavaThumbnail.appex" 2>/dev/null || true
    trash "$DEST"
  fi
  ditto "$built" "$DEST"

  info "registering extensions"
  $LSREGISTER -f -R -trusted "$DEST"
  local appex
  for appex in "$DEST"/Contents/PlugIns/*.appex; do
    pluginkit -a "$appex"
  done
  unregister_stale
  local id
  for id in $EXT_IDS; do
    pluginkit -e use -i $id
  done
  reset_quicklook

  status
}

do_uninstall() {
  pkill -x $APP_NAME 2>/dev/null || true
  local id p
  for id in $EXT_IDS; do
    registered_paths $id | while read -r p; do
      [[ -n $p ]] && pluginkit -r "$p" 2>/dev/null || true
    done
  done
  if [[ -e $DEST ]]; then
    $LSREGISTER -u "$DEST" 2>/dev/null || true
    info "moving $DEST to the trash"
    trash "$DEST"
  fi
  unregister_stale
  reset_quicklook
  info "uninstalled"
}

case "${1:-install}" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    status ;;
  *) print "usage: $0 [install|uninstall|status]" >&2; exit 2 ;;
esac
