#!/usr/bin/env zsh -f

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MY_HOME=/Users/nsano

case "$1" in
  *.lzh | *.LZH | *.arj | *.ARJ | *.cab | *.CAB | *.asar | *.d88 | *.D88 )
    echo "<style>table{display: flex; flex-direction: column; border-collapse: separate; border-spacing: 50px 0} th,td{font-size:small; overflow: auto} td:nth-child(1){flex-grow: 1} td:nth-child(2){flex-basis: 15%; max-width: 15%} td:nth-child(3){flex-basis: 10%; max-width: 10%}</style>"
    echo "<body style='color:#66FF00;background-color:black'>"
    echo "<pre style='font-family:monaco'>"
    ${MY_HOME}/bin/vavi_util_archive "$1" "$2"
    echo "</pre>"
    echo "</body>"
    ;;
  *.chd | *.CHD )
    echo "<body style='color:#66FF00;background-color:black'>"
    echo "<pre style='font-family:monaco;font-size:small'>"
    ${MY_HOME}/bin/chdman info -v -i "$1"
    echo "</pre>"
    echo "</body>"
    ;;
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
