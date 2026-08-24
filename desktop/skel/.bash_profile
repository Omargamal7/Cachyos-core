# Start the graphical session on the first console. There is no display
# manager on this system by design -- log in, and the session comes up.
#
# desktop/install.sh writes ~/.config/mba62-session with the session it just
# installed. That file, not the presence of a config directory, is what decides
# this: re-running the installer to switch sessions leaves the previous
# session's config in place, so guessing from config files would keep starting
# the old one.
if [[ -z $DISPLAY && -z ${WAYLAND_DISPLAY:-} && $XDG_VTNR -eq 1 ]]; then
    session=""
    [[ -r $HOME/.config/mba62-session ]] && read -r session < "$HOME/.config/mba62-session"

    # dbus-run-session because neither compositor starts a session bus itself,
    # and the tray applet, the PolicyKit agent and the notification daemon all
    # expect one. A missing binary falls through to the detection below rather
    # than failing the login.
    case $session in
        labwc)   command -v labwc >/dev/null 2>&1 && exec dbus-run-session labwc ;;
        sway)    command -v sway  >/dev/null 2>&1 && exec dbus-run-session sway ;;
        openbox) exec startx ;;
    esac

    # No marker: an install from before it existed, or the live ISO, whose
    # /etc/skel carries every session's dotfiles while only Openbox is present.
    if [[ -r $HOME/.config/labwc/rc.xml ]] && command -v labwc >/dev/null 2>&1; then
        exec dbus-run-session labwc
    elif [[ -r $HOME/.config/sway/config ]] && command -v sway >/dev/null 2>&1; then
        exec dbus-run-session sway
    fi
    exec startx
fi
