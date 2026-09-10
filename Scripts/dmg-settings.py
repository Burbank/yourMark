# dmgbuild settings — written into .DS_Store so Finder shows the PNG.
import os

_root = os.environ["YOURMARK_DMG_ROOT"]
_app = os.environ["YOURMARK_DMG_APP"]
_bg = os.environ["YOURMARK_DMG_BG"]
_out = os.environ["YOURMARK_DMG_OUT"]

filename = _out
volume_name = "yourMark"
format = "UDZO"
filesystem = "HFS+"

files = [_app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["yourMark.app"]

background = _bg
default_view = "icon-view"
icon_size = 256
text_size = 16
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

# ((x, y), (width, height)) — width/height must match the PNG.
window_rect = ((220, 160), (800, 480))

icon_locations = {
    "yourMark.app": (190, 250),
    "Applications": (610, 250),
}
