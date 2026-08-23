# Start the graphical session on the first console. There is no display
# manager on this system by design -- log in, and X comes up.
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]]; then
    exec startx
fi
