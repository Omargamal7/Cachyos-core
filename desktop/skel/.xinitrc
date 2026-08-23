#!/bin/sh
# Started by `startx`. Openbox is launched through openbox-session so that
# its autostart file runs and the session ends cleanly on logout.

userresources=$HOME/.Xresources
[ -f "$userresources" ] && xrdb -merge "$userresources"

# The panel, xfsettingsd and friends live in ~/.config/openbox/autostart.
exec openbox-session
