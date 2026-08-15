#!/usr/bin/env zsh -f

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export MAVEN_OPTS="-Djansi.passthrough=true -Dstyle.color=never $MAVEN_OPTS"

MY_HOME=/Users/nsano
export HOME="${MY_HOME}"

case "$1" in
  *.wmf | *.WMF | *.emf | *.EMF )
    echo "<body>"
    echo "<pre>"
    ${MY_HOME}/bin/vavi_image_anigif "$1" "$2"
    echo "</pre>"
    echo "</body>"
    ;;
  * )
    ;;
esac
