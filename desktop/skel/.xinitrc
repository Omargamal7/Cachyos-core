#!/bin/sh
# Started by `startx`. Openbox is launched through openbox-session so that
# its autostart file runs and the session ends cleanly on logout.

userresources=$HOME/.Xresources
if [ -f "$userresources" ] && command -v xrdb >/dev/null 2>&1; then
    xrdb -merge "$userresources"
fi

# The panel, xfsettingsd and friends live in ~/.config/openbox/autostart.
exec openbox-session
