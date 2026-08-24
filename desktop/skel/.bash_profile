# Start the graphical session on the first console. There is no display
# manager on this system by design -- log in, and the session comes up.
#
# Which session depends on what desktop/install.sh laid down: it installs the
# config for exactly one compositor, so the first match wins. The `command -v`
# tests matter on the live ISO, whose /etc/skel carries every session's
# dotfiles while only Openbox is installed.
if [[ -z $DISPLAY && -z ${WAYLAND_DISPLAY:-} && $XDG_VTNR -eq 1 ]]; then
    # dbus-run-session because neither compositor starts a session bus itself,
    # and the tray applet, the PolicyKit agent and the notification daemon all
    # expect one.
    if [[ -r $HOME/.config/labwc/rc.xml ]] && command -v labwc >/dev/null 2>&1; then
        exec dbus-run-session labwc
    elif [[ -r $HOME/.config/sway/config ]] && command -v sway >/dev/null 2>&1; then
        exec dbus-run-session sway
    else
        exec startx
    fi
fi
