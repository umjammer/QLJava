#!/usr/bin/env zsh -f

MY_HOME=/Users/nsano

case "$1" in
  *.wmf | *.emf )
    ${MY_HOME}/bin/vavi_image_anigif "$1" "$2"
    ;;
  * )
    ;;
esac
