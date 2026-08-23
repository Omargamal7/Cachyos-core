#!/usr/bin/env python3
"""Merge our extra key bindings into an Openbox rc.xml.

    merge-keybindings.py <rc.xml> <keybindings.xml>

Adds every <keybind> from the fragment to rc.xml's <keyboard> section,
replacing any existing binding for the same key so re-running is a no-op.
The rest of rc.xml -- mouse bindings, theme, window rules -- is left as the
distro shipped it.
"""
import sys
import xml.etree.ElementTree as ET

RC_NS = "http://openbox.org/3.4/rc"


def main(rc_path, frag_path):
    ET.register_namespace("", RC_NS)
    rc = ET.parse(rc_path)
    root = rc.getroot()

    # Openbox releases differ on whether rc.xml carries the namespace.
    ns = ""
    if root.tag.startswith("{"):
        ns = root.tag[: root.tag.index("}") + 1]

    keyboard = root.find(f"{ns}keyboard")
    if keyboard is None:
        keyboard = ET.SubElement(root, f"{ns}keyboard")

    frag = ET.parse(frag_path).getroot()
    incoming = frag.findall("keybind")
    if not incoming:
        sys.exit(f"{frag_path}: no <keybind> elements found")

    wanted = {kb.get("key") for kb in incoming}
    for existing in list(keyboard.findall(f"{ns}keybind")):
        if existing.get("key") in wanted:
            keyboard.remove(existing)

    for kb in incoming:
        # Re-tag the fragment's elements into rc.xml's namespace.
        for el in kb.iter():
            if not el.tag.startswith("{"):
                el.tag = f"{ns}{el.tag}"
        keyboard.append(kb)

    ET.indent(rc, space="  ")
    rc.write(rc_path, encoding="UTF-8", xml_declaration=True)
    print(f"merged {len(incoming)} key binding(s) into {rc_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
