#!/usr/bin/env zsh -f

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export MAVEN_OPTS="-Djansi.passthrough=true -Dstyle.color=never $MAVEN_OPTS"

MY_HOME=/Users/nsano
export HOME="${MY_HOME}"

case "$1" in
  *.lzh | *.LZH | *.lha | *.LHA | *.arj | *.ARJ | *.cab | *.CAB | *.asar | *.ASAR | *.d88 | *.D88 | *.gca | *.GCA )
    echo "<!DOCTYPE html><html><head><meta charset='utf-8'><style>body{color:#66FF00;background-color:black;font-family:Monaco,monospace;font-size:12px;margin:12px} table{border-collapse:collapse;width:100%} th,td{text-align:left;padding:3px 12px;white-space:nowrap} th{border-bottom:1px solid #66FF00}</style></head><body>"
    ${MY_HOME}/bin/vavi_util_archive "$1" "$2"
    echo "</body></html>"
    ;;
  *.chd | *.CHD )
    echo "<!DOCTYPE html><html><head><meta charset='utf-8'><style>body{color:#66FF00;background-color:black;font-family:Monaco,monospace;font-size:12px;margin:12px}</style></head><body>"
    echo "<pre style='font-family:Monaco,monospace;font-size:12px'>"
    ${MY_HOME}/bin/chdman info -v -i "$1"
    echo "</pre>"
    echo "</body></html>"
    ;;
  *.wmf | *.WMF | *.emf | *.EMF | *.img | *.IMG | *.mag | *.MAG | *.maki | *.MAKI | *.mki | *.MKI | *.pi | *.PI | *.pic | *.PIC | *.zim | *.ZIM )
    echo "<body>"
    echo "<pre>"
    ${MY_HOME}/bin/vavi_image_anigif "$1" "$2"
    echo "</pre>"
    echo "</body>"
    ;;
  * )
    ;;
esac
