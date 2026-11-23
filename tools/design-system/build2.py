"""The WoW Forever UI system, modern: Forever's own window kit (its -c60 atlases) as components."""
import json, os, sys, datetime, re
ROOT, MODERN, RAW = sys.argv[1], sys.argv[2], sys.argv[3]
P = lambda *parts: os.path.join(ROOT, "project", *parts)
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
NEW = {
 "Bars/common-stat-bar-bg.png": "ba61d06957f31bcd94485aecf4e53f54", "Bars/common-stat-bar-blue.png": "bd85e09cdf52774c4ebc8485c51c09b0",
 "Bars/common-stat-bar-white.png": "1b44351afc29b718e9ebb8d990d67749", "Buttons/128-redbutton-center-disabled.png": "b776917e00546c6a08ee58f83fc84ab3",
 "Buttons/128-redbutton-center-pressed.png": "9e811125b6504aa85b85f908520e28ab", "Buttons/128-redbutton-center.png": "fd9e820f4721824f1db7b1a51cca869b",
 "Buttons/128-redbutton-highlight.png": "cce913c39424778fa3292dd00dfc16a9", "Buttons/128-redbutton-left-disabled.png": "26e0631634baeb19aed6e947645b5e4a",
 "Buttons/128-redbutton-left-pressed.png": "935ebb36510c49f61c7dbaa2106593fe", "Buttons/128-redbutton-left.png": "5ea64d5c4efe93d2439fa8c9879aad49",
 "Buttons/128-redbutton-right-disabled.png": "d19c24abaa932449b44cac9c253bfa5a", "Buttons/128-redbutton-right-pressed.png": "b3e57d98486d47123a9ab90c1670e983",
 "Buttons/128-redbutton-right.png": "ffbad23bd08c9b7386c701f48c675a7f", "Inset/ui-frame-innerbotleftcorner.png": "0c485d44e18e496da2e22aecbc4136dc",
 "Inset/ui-frame-innerbotright.png": "a3e5515ec58be0cd42b544b3395f3d8a", "Inset/ui-frame-innerbottile.png": "a254f044aa348b189ba147712dbeb571",
 "Inset/ui-frame-innerlefttile.png": "142156a624e3699d3ff4610e042bf1e2", "Inset/ui-frame-innerrighttile.png": "cde1c33d48f7f3681a2fffeed43aaaa6",
 "Inset/ui-frame-innertopleft.png": "7f640dfb74dac120defdcc3e30428ce1", "Inset/ui-frame-innertopright.png": "937d90845529dc0a0dd5a404cbc10460",
 "Inset/ui-frame-innertoptile.png": "a4719e20fe55938d23e52717b981a62d", "Lists/campaign_headericon_closed.png": "237c1f976e6451d925b60027ea682eab",
 "Lists/campaign_headericon_open.png": "86e21a7408a67bd552c9a3f391aee1ef", "Lists/checkbox-minimal.png": "74a9214d8d5604d26198d47f16a0bb55",
 "Lists/checkmark-minimal.png": "fe598544da3e971d6df7245847bd7b41", "Lists/common-button-list-minus.png": "3b65f85f71380e54ccb8b7fc4129bdbf",
 "Lists/common-button-list-plus.png": "886bede6697dc9f4d80a7090e96ff537", "Lists/common-dropdown-a-button.png": "03ce9e4384d6d55544488221dc473c49",
 "Lists/common-search-border-left.png": "0e03b9d854556608a0ab42359fdbb766", "Lists/common-search-border-middle.png": "d7e688b03c994ae5dadbe7d0e3989b43",
 "Lists/common-search-border-right.png": "77a00e3deda2cbeb8614683432e5c4e9", "Lists/common-search-magnifyingglass.png": "87bf01ffe5e4de262245d9baf3bd0a61",
 "Lists/spellbook-skilllinetab.png": "b08d1560bc8ec8b0c81da4e6f201e0ed", "Lists/ui-character-info-gearslot.png": "d67aabee69194bbc53816eebcc140c9d",
 "Lists/ui-character-info-scrollline-long.png": "e4bd3d8258848a6a07a6381663d7a188", "Lists/ui-character-info-scrollline.png": "e0b6abc3b167ed64bf6878da3d9d7eca",
 "Lists/ui-character-info-title.png": "365e0180c1704e8df9289fa5091272c9", "Professions/heavybronze-frame-basic.png": "a177630440ac3b98fd9019c388e1ec8e",
 "Professions/professions-slot-frame.png": "f63dfd69544cd0cd6ee38fc7a537fe09", "Spellbook/spellbook-divider.png": "0330cd31c398cf35b3aa2a421e60326a",
 "Spellbook/spellbook-item-backplate.png": "3645d6cff053413fb69444cf10ebd5fb", "Spellbook/spellbook-page-left.png": "d8d4ba10f343b0894f95dc8905528b33",
 "Spellbook/spellbook-page-right.png": "7fda5d368f2de40408f7bd510f9a2c85", "Tooltip/tooltip-nineslice-center.png": "bee7cf2517b870b6eefbf9f13adb1733",
 "Tooltip/tooltip-nineslice-cornerbottomleft.png": "f5a82eaa303f8c121adaec382b7bb55a", "Tooltip/tooltip-nineslice-cornerbottomright.png": "47079fd8b2c2758468564eae13db3bf7",
 "Tooltip/tooltip-nineslice-cornertopleft.png": "a3f3f56ffa838827fc44c6263389cc42", "Tooltip/tooltip-nineslice-cornertopright.png": "28bd7c645a927d5806d6d9f283874341",
 "Tooltip/tooltip-nineslice-edgebottom.png": "025da1d5d908342d19ca8d457ef1c8d3", "Tooltip/tooltip-nineslice-edgeleft.png": "e83c01fa0d01b40e1a512b1982177224",
 "Tooltip/tooltip-nineslice-edgeright.png": "bbd20b8423a37623478a13c489c78d49", "Tooltip/tooltip-nineslice-edgetop.png": "e5873b7736bc7e5da62e7abe5b51070f",
 "Window/redbutton-exit.png": "94553e5ef9f3afedced5ca846ab06c05", "Window/ui-background-marble.png": "bc28eb4f87df7e23959b0c1eb88a44cf",
 "Window/ui-background-rock.png": "30ace8b96e0aa708b9e1a0bd3fb99b1f", "Window/ui-frame-metal-cornerbottomleft.png": "980cb1b2057ced12b7cb5f987a11e47f",
 "Window/ui-frame-metal-cornerbottomright.png": "0c6d743469638763cb1ae29438cc5062", "Window/ui-frame-metal-cornertopright.png": "cb4c2acfc1669279da25f357191711d9",
 "Window/ui-frame-metal-edgebottom.png": "384623cd2ecd684a9fae502b6cd336a6", "Window/ui-frame-metal-edgeleft.png": "9e16f886cd5e179e47d1eeed3df9e1c8",
 "Window/ui-frame-metal-edgeright.png": "00d7a139551b9331c7d2e1892792203c", "Window/ui-frame-metal-edgetop.png": "a8659b908107c9fefa591da17f9df816",
 "Window/ui-frame-portraitmetal-cornertopleft.png": "e202e375b9471da9b4f1430e5fe97bb1", "Window/ui-frame-toptilestreaks.png": "70ee5b81f66d812ae5e88032a1bbdc41",
}
KEPT = {  # still right: money, map marks, icons
 "Money/ui-coppericon.png": "040628cde515bff79d2b6fe38f99f786", "Money/ui-goldicon.png": "6ac8dc4ee70acc8840fdd4cdaa6dec58", "Money/ui-silvericon.png": "b8a295099dc58cf25fba0389ad83eb42",
 "Map marks/dungeon.png": "e51d836bb274977d22f6d93343b19e30", "Map marks/questdaily.png": "766d47097adb62ff5c15cd9f26ab15e8", "Map marks/questnormal.png": "f06c285270ba70fd4c03038bb5caa28a",
 "Map marks/questturnin.png": "8b8ef702b70ab3012cae35b7a8186265", "Map marks/raid.png": "560ee6688d94343efaa39e31e8ec7571", "Map marks/trivialquests.png": "21571f8998157ccb1289eb47ff94c0ba",
 "Icons/ability_tracking.png": "3dda39becb2bc87457cf7f9b6469efcd", "Icons/inv_misc_coin_01.png": "c64da4f76477a0580cf1d72b4a7b3d61",
 "Icons/inv_misc_pocketwatch_01.png": "0b9b83647452669cae335687f23ecad8", "Icons/inv_misc_ticket_tarot_madness.png": "b807364555bc149e56ac71faadf47bb7",
 "Icons/inv_scroll_03.png": "56f52b821467ae814310d1d943384f9a", "Icons/xp_icon.png": "915d1427cfaf22db82631671b324ca21",
}
CLASSIC = {  # the older art: still in the client, not what Forever's windows are made of
 "Frames/ui-dialogbox-border.png": "83bb84b4c8dc99d17ffa467c890a9a62", "Frames/ui-dialogbox-background.png": "007f067a355920c4dd62bd87292cee75",
 "Frames/ui-dialogbox-header.png": "b32c8d1531f2cf5eede118b4376d5a4d", "Frames/ui-tooltip-border.png": "b7279c2e57b6e66ee4ebf62e70fa58d2",
 "Frames/ui-tooltip-background.png": "02b38cf44e20b0ca95bb918806e8580f", "Frames/questbg.png": "95d7b3fc106fdff94467eb7d15dffe90",
 "Buttons/ui-panel-button-up.png": "d5f4b1acd3b5787fd3dd6b06ed613718", "Buttons/ui-checkbox-up.png": "dd18b56551047eb2a8cbb6fdeef2c95d",
 "Buttons/ui-checkbox-check.png": "7bb80b7bceac2f65afcaa31d8d440a7e", "Items/ui-questitemnameframe.png": "6b4fe1ea96db03446e4a9234252f4415",
 "Items/ui-quickslot2.png": "76a6152b847edee667c0bfb44ce18fe3", "Bars/ui-statusbar.png": "602fac777ccc7be83e97049fc43e4827",
}
SIZES = json.load(open(os.path.join(MODERN, "sizes.json")))
def b(name):
    for table in (NEW, KEPT):
        for path, bid in table.items():
            if path.split("/")[-1] == name + ".png":
                return "/_blob/" + bid
    raise KeyError(name)
def drawn(name):
    for path, info in SIZES.items():
        if path.split("/")[-1] == name + ".png":
            return info.get("drawn") or info["pixels"]
    raise KeyError(name)

FONTS = "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Archivo+Narrow:wght@400;600&family=Marcellus&family=Metamorphous&display=swap\">"
def preview(group, height, body, script="", subtitle="", ground="#14110d"):
    sub = f' subtitle="{subtitle}"' if subtitle else ""
    return (f'<!-- @dsCard group="{group}" height={height}{sub} -->\n<!doctype html>\n<html><head><meta charset="utf-8">{FONTS}\n'
            f'<style>body{{margin:0;padding:22px;background:{ground};color:var(--highlight-font);font-family:var(--font-friz)}}'
            '.label{font:11px var(--font-narrow);color:var(--lightgray-font);letter-spacing:.02em}.abs{position:absolute}'
            '.shadow{text-shadow:1px -1px 0 #000}</style></head>\n'
            f'<body>{body}' + (f'<script>{script}</script>' if script else '') + '</body></html>\n')
def component(name, group, height, readme, body, script="", ground="#14110d"):
    write(P("components", name, "README.md"), readme)
    write(P("components", name, "preview.html"), preview(group, height, body, script, ground=ground))

def window(width, height, title, inner, icon="inv_scroll_03"):
    """PortraitFrameTemplate with Forever's -c60 metal pieces, placed as NineSliceLayouts plus Forever's overrides"""
    tl, tr, bl, br = drawn("ui-frame-portraitmetal-cornertopleft"), drawn("ui-frame-metal-cornertopright"), drawn("ui-frame-metal-cornerbottomleft"), drawn("ui-frame-metal-cornerbottomright")
    et, eb, el, er = drawn("ui-frame-metal-edgetop"), drawn("ui-frame-metal-edgebottom"), drawn("ui-frame-metal-edgeleft"), drawn("ui-frame-metal-edgeright")
    # corner offsets: TopLeft (-13, +16), TopRight (+4 -2, +16), BottomLeft (-13, -8), BottomRight (+4 -2, -8)
    L, T, R, B = -13, -16, width + 2, height + 8
    parts = [
        (b("ui-frame-portraitmetal-cornertopleft"), L, T, tl[0], tl[1], "no-repeat"),
        (b("ui-frame-metal-cornertopright"), R - tr[0], T, tr[0], tr[1], "no-repeat"),
        (b("ui-frame-metal-cornerbottomleft"), L, B - bl[1], bl[0], bl[1], "no-repeat"),
        (b("ui-frame-metal-cornerbottomright"), R - br[0], B - br[1], br[0], br[1], "no-repeat"),
        (b("ui-frame-metal-edgetop"), L + tl[0], T, (R - tr[0]) - (L + tl[0]), et[1], "repeat-x"),
        (b("ui-frame-metal-edgebottom"), L + bl[0], B - eb[1], (R - br[0]) - (L + bl[0]), eb[1], "repeat-x"),
        (b("ui-frame-metal-edgeleft"), L, T + tl[1], el[0], (B - bl[1]) - (T + tl[1]), "repeat-y"),
        (b("ui-frame-metal-edgeright"), R - er[0], T + tr[1], er[0], (B - br[1]) - (T + tr[1]), "repeat-y"),
    ]
    sizes = {0: f"{tl[0]}px {tl[1]}px", 1: f"{tr[0]}px {tr[1]}px", 2: f"{bl[0]}px {bl[1]}px", 3: f"{br[0]}px {br[1]}px",
             4: f"{et[0]}px {et[1]}px", 5: f"{eb[0]}px {eb[1]}px", 6: f"{el[0]}px {el[1]}px", 7: f"{er[0]}px {er[1]}px"}
    frame = "".join(f'<div class="abs" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;background:url({src}) 0 0/{sizes[i]} {rep};z-index:3"></div>'
                    for i, (src, x, y, w, h, rep) in enumerate(parts))
    return (f'<div style="position:relative;width:{width}px;height:{height}px;margin:24px 18px 14px 20px">'
            f'<div class="abs" style="inset:2px;background:#1b1712 url({b("ui-background-rock")}) 0 0/512px 512px"></div>'
            f'<div class="abs" style="left:2px;right:2px;top:2px;height:22px;background:url({b("ui-frame-toptilestreaks")}) 0 0/256px 43px repeat-x;opacity:.9"></div>'
            f'<div class="abs" style="left:-6px;top:-8px;width:60px;height:60px;border-radius:50%;background:url({b(icon)}) center/112%;z-index:2"></div>'
            f'{frame}'
            f'<div class="abs shadow" style="left:0;right:0;top:4px;text-align:center;font:12px var(--font-friz);color:var(--normal-font);z-index:4">{title}</div>'
            f'<div class="abs" style="right:-2px;top:-2px;width:{drawn("redbutton-exit")[0] - 6}px;height:{drawn("redbutton-exit")[1] - 6}px;background:url({b("redbutton-exit")}) center/contain no-repeat;z-index:5"></div>'
            f'<div class="abs" style="left:12px;right:10px;top:32px;bottom:10px;z-index:1">{inner}</div></div>')

def inset(width, height, inner=""):
    c = 6
    pieces = [("ui-frame-innertopleft", 0, 0, c, c, "no-repeat"), ("ui-frame-innertopright", width - c, 0, c, c, "no-repeat"),
              ("ui-frame-innerbotleftcorner", 0, height - c + 1, c, c, "no-repeat"), ("ui-frame-innerbotright", width - c, height - c + 1, c, c, "no-repeat"),
              ("ui-frame-innertoptile", c, 0, width - 2 * c, 3, "repeat-x"), ("ui-frame-innerbottile", c, height - 3 + 1, width - 2 * c, 3, "repeat-x"),
              ("ui-frame-innerlefttile", 0, c, 3, height - 2 * c, "repeat-y"), ("ui-frame-innerrighttile", width - 3, c, 3, height - 2 * c, "repeat-y")]
    edge = "".join(f'<div class="abs" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;background:url({b(n)}) 0 0 {rep}"></div>' for n, x, y, w, h, rep in pieces)
    return (f'<div style="position:relative;width:{width}px;height:{height}px">'
            f'<div class="abs" style="inset:2px;background:#110e0a url({b("ui-background-marble")}) 0 0/256px 256px"></div>{edge}'
            f'<div class="abs" style="inset:6px 10px">{inner}</div></div>')

def red_button(label, width, state="", height=26):
    s = height / 128
    suffix = {"pressed": "-pressed", "disabled": "-disabled"}.get(state, "")
    lw, rw = round(114 * s), round(292 * s)
    color = "var(--disabled-font)" if state == "disabled" else "var(--normal-font)"
    hl = f'<div class="abs" style="inset:0;background:url({b("128-redbutton-highlight")}) center/{round(441 * s * 1.1)}px {height}px no-repeat;mix-blend-mode:screen;opacity:.8"></div>' if state == "hover" else ""
    return (f'<div style="position:relative;width:{width}px;height:{height}px">'
            f'<div class="abs" style="left:0;top:0;width:{lw}px;height:{height}px;background:url({b("128-redbutton-left" + suffix)}) 0 0/{lw}px {height}px"></div>'
            f'<div class="abs" style="left:{lw}px;right:{min(rw, width - lw - 4)}px;top:0;height:{height}px;background:url({b("128-redbutton-center" + suffix)}) 0 0/{round(64 * s)}px {height}px repeat-x"></div>'
            f'<div class="abs" style="right:0;top:0;width:{min(rw, width - lw - 4)}px;height:{height}px;background:url({b("128-redbutton-right" + suffix)}) right 0/{rw}px {height}px no-repeat"></div>{hl}'
            f'<div class="abs shadow" style="inset:0;display:flex;align-items:center;justify-content:center;font:13px var(--font-friz);color:{color};{"padding-top:1px;" if state == "pressed" else ""}">{label}</div></div>')

# ---- components ----------------------------------------------------------------------------------------------
component("Window", "Frames", 300,
"""# Window
Forever's window (PortraitFrameTemplate): a heavy bronze-and-iron frame, a round portrait at its top left, the title in gold, a red close button.

- The frame is a nine-slice of Forever's own art: `UI-Frame-PortraitMetal-CornerTopLeft-c60` (with the portrait ring), `UI-Frame-Metal-CornerTopRight-c60`, `-CornerBottomLeft-c60`, `-CornerBottomRight-c60`, tiled `_UI-Frame-Metal-EdgeTop/Bottom-c60` and `!UI-Frame-Metal-EdgeLeft/Right-c60`. Corners sit 13 left, 16 above, and (Forever's override) 8 below the window.
- Ground: `Interface\\FrameGeneral\\UI-Background-Rock`, tiled; `_UI-Frame-TopTileStreaks` along the top under the title.
- Title: GameFontNormal (`normal-font`), centred in the top 24px. Close: `RedButton-Exit-c60` at the top right.
- Portrait: a 60px round icon (SetPortraitToTexture) under the ring.
- In an addon: inherit `PortraitFrameTemplate` (or `ButtonFrameTemplate` for one with an inset), never redraw the frame.
""", window(420, 220, "Professions", ""))

component("InsetPanel", "Frames", 200,
"""# InsetPanel
A sunken panel inside a window (InsetFrameTemplate): darker marble ground with a thin carved edge.

- Ground `Interface\\FrameGeneral\\UI-Background-Marble`; edge pieces `UI-Frame-InnerTopLeft`, `-InnerTopRight`, `-InnerBotLeftCorner`, `-InnerBotRight` (6px) and tiles `_UI-Frame-InnerTopTile`, `_UI-Frame-InnerBotTile`, `!UI-Frame-InnerLeftTile`, `!UI-Frame-InnerRightTile` (3px).
- Groups content inside a window: a list, a details pane, a profession's area. Headings in GameFontNormal (`normal-font`), values in `highlight-font`.
- In an addon: inherit `InsetFrameTemplate`.
""", '<div style="display:flex;gap:14px">' + inset(260, 140, '<div class="shadow" style="font:14px var(--font-friz);color:var(--normal-font);margin:6px 4px">Leatherworking</div><div style="font:12px var(--font-friz);color:var(--highlight-font);margin:0 4px">Apprentice · 20/75</div>') + inset(170, 140, '<div class="shadow" style="font:14px var(--font-friz);color:var(--normal-font);text-align:center;margin-top:6px">Cooking</div>') + '</div>')

component("RedButton", "Controls", 110,
"""# RedButton
Forever's red action button: dark red face, carved gold-bronze rim, gold label.

- Three slices of the `128-RedButton` kit: `128-RedButton-Left`, `_128-RedButton-Center` (stretched), `128-RedButton-Right`; `-Pressed` and `-Disabled` variants; `128-RedButton-Highlight` added on hover. Drawn at 22 to 26px high.
- Label in GameFontNormal (`normal-font`); disabled: grey face, `disabled-font` label.
- Seen as Create, Create All, Untrack, Focus, Abandon. In an addon: `UIPanelButtonTemplate` (its art in this client is this kit).
""", '<div style="display:flex;gap:16px;flex-wrap:wrap;align-items:flex-end">' + "".join(
    f'<div><div>{red_button(l, w, st)}</div><div class="label" style="margin-top:4px">{st or "normal"}</div></div>'
    for l, w, st in [("Create", 120, ""), ("Focus", 110, "hover"), ("Abandon", 120, "pressed"), ("Create All [0]", 140, "disabled")]) + '</div>')

def tip(lines, width=280):
    c = 7
    names = [("tooltip-nineslice-cornertopleft", f"left:0;top:0;width:{c}px;height:{c}px"), ("tooltip-nineslice-cornertopright", f"right:0;top:0;width:{c}px;height:{c}px"),
             ("tooltip-nineslice-cornerbottomleft", f"left:0;bottom:0;width:{c}px;height:{c}px"), ("tooltip-nineslice-cornerbottomright", f"right:0;bottom:0;width:{c}px;height:{c}px"),
             ("tooltip-nineslice-edgetop", f"left:{c}px;right:{c}px;top:0;height:{c}px;background-repeat:repeat-x !important"),
             ("tooltip-nineslice-edgebottom", f"left:{c}px;right:{c}px;bottom:0;height:{c}px;background-repeat:repeat-x !important"),
             ("tooltip-nineslice-edgeleft", f"left:0;top:{c}px;bottom:{c}px;width:{c}px;background-repeat:repeat-y !important"),
             ("tooltip-nineslice-edgeright", f"right:0;top:{c}px;bottom:{c}px;width:{c}px;background-repeat:repeat-y !important")]
    edge = "".join(f'<div class="abs" style="{pos};background:url({b(n)}) 0 0 no-repeat"></div>' for n, pos in names)
    return (f'<div style="position:relative;width:{width}px;padding:9px 11px;box-sizing:border-box">'
            f'<div class="abs" style="inset:2px;background:var(--tooltip-ground);opacity:.92"></div>{edge}<div style="position:relative">{lines}</div></div>')
component("Tooltip", "Frames", 170,
"""# Tooltip
The game's tooltip (GameTooltip, `TooltipDefaultLayout`): a near-black blue ground in a thin grey edge with soft corners.

- Nine-slice `Tooltip-NineSlice-CornerTopLeft`, `-CornerTopRight`, `-CornerBottomLeft`, `-CornerBottomRight` (7px), tiles `_Tooltip-NineSlice-EdgeTop/Bottom` and `!Tooltip-NineSlice-EdgeLeft/Right`, the centre `Tooltip-NineSlice-Center` tinted `tooltip-ground`.
- First line in GameFontNormalLarge coloured by meaning (`normal-font` for a quest, an item's quality colour, a class colour); then GameFontNormal lines: `highlight-font` facts, `green-font` met, `red-font` unmet, `lightyellow-font` flavour. AddDoubleLine for label and value.
""", tip('<div style="font:15px/19px var(--font-friz);color:var(--normal-font)">[20] The Guns of Northwatch</div>'
         '<div style="display:flex;justify-content:space-between;font:12px/16px var(--font-friz)"><span>Captain Fairmount slain</span><span>done</span></div>'
         '<div style="display:flex;justify-content:space-between;font:12px/16px var(--font-friz)"><span>Theramore Medal</span><span>6/10</span></div>'
         '<div style="font:12px/16px var(--font-friz);color:var(--green-font)">Turn in to Captain Thalo\'thas Brightsun</div>'))

component("CheckBox", "Controls", 80,
"""# CheckBox
Forever's minimal checkbox: a small dark square with a fine rim, a gold tick when on.

- `checkbox-minimal` (30x29) and `checkmark-minimal` over it; `checkmark-minimal-disabled` when unavailable.
- Label right of it in GameFontHighlight (`highlight-font`), or `disabled-font` beside a disabled box. Seen as Track Recipe.
""", '<div style="display:flex;gap:30px;align-items:center">' + "".join(
    f'<label style="display:flex;align-items:center;gap:6px;font:13px var(--font-friz);color:var(--{col})"><span style="position:relative;width:30px;height:29px;background:url({b("checkbox-minimal")}) 0 0/30px 29px">{tick}</span>{text}</label>'
    for text, tick, col in [("Track Recipe", "", "disabled-font"), ("Show low-level quests", f'<span class="abs" style="inset:0;background:url({b("checkmark-minimal")}) 0 0/30px 29px"></span>', "highlight-font")]) + '</div>')

component("SearchBox", "Controls", 90,
"""# SearchBox
The search field (SearchBoxTemplate): a dark rounded field in a thin bronze rim, a magnifying glass, grey instructions.

- Three slices `common-search-border-left`, `-middle` (stretched), `-right` (40px high, drawn at 28 to 32); `common-search-magnifyingglass` at the left; `common-search-clearbutton` once text is typed.
- Instructions in GameFontDisable (`disabled-font`): "Search", "Enter search text". Beside it, a dropdown button `common-dropdown-a-button` (27px).
""", (f'<div style="display:flex;gap:10px;align-items:center"><div style="position:relative;width:300px;height:30px">'
      f'<div class="abs" style="left:0;top:0;width:12px;height:30px;background:url({b("common-search-border-left")}) 0 0/12px 30px"></div>'
      f'<div class="abs" style="left:12px;right:12px;top:0;height:30px;background:url({b("common-search-border-middle")}) 0 0/100% 30px"></div>'
      f'<div class="abs" style="right:0;top:0;width:12px;height:30px;background:url({b("common-search-border-right")}) 0 0/12px 30px"></div>'
      f'<img class="abs" src="{b("common-search-magnifyingglass")}" width="18" style="left:10px;top:6px">'
      f'<div class="abs" style="left:34px;top:7px;font:13px var(--font-friz);color:var(--disabled-font)">Enter search text</div></div>'
      f'<img src="{b("common-dropdown-a-button")}" width="27" height="27"></div>'))

def stat_row(label, value, shade, value_color="var(--highlight-font)"):
    bg = f"background:url({b('ui-character-info-scrollline')}) bottom/100% 7px no-repeat;" if shade else ""
    return (f'<div style="display:flex;justify-content:space-between;padding:4px 10px;font:13px var(--font-friz);{bg}">'
            f'<span class="shadow" style="color:var(--normal-font)">{label}</span><span class="shadow" style="color:{value_color}">{value}</span></div>')
component("StatList", "Lists", 260,
"""# StatList
The character window's lists: a section title on a carved plate, then label-and-value lines.

- Title plate `UI-Character-Info-Title-c60` (201x32), its text centred in GameFontHighlight (`highlight-font`): General, Primary Attributes, Weapons.
- Lines: label left in GameFontNormal (`normal-font`), value right in `highlight-font` (or `green-font` when raised), each line ruled by `UI-Character-Info-ScrollLine-c60`; `UI-Character-Info-ScrollLine-Long-c60` for full-width rows.
- Collapsible groups (the Skills window) put `common-button-list-minus` / `common-button-list-plus` at the right of the header; the campaign-style `campaign_headericon_open` / `_closed` where a header is a button.
""", ('<div style="width:380px">' +
      f'<div style="position:relative;height:32px;background:url({b("ui-character-info-title")}) center/100% 32px no-repeat;display:flex;align-items:center;justify-content:center;font:14px var(--font-friz);color:var(--highlight-font)" class="shadow">General</div>' +
      stat_row("Health:", "292", True) + stat_row("Mana:", "318", False) + stat_row("Movement Speed:", "102%", True) +
      f'<div style="position:relative;height:32px;margin-top:6px;background:url({b("ui-character-info-title")}) center/100% 32px no-repeat;display:flex;align-items:center;justify-content:center;font:14px var(--font-friz);color:var(--highlight-font)" class="shadow">Primary Attributes</div>' +
      stat_row("Strength:", "23", True, "var(--green-font)") + stat_row("Agility:", "41", False, "var(--green-font)") +
      f'<div style="display:flex;align-items:center;gap:8px;margin-top:10px;font:14px var(--font-friz);color:var(--normal-font)" class="shadow">Professions<span style="flex:1"></span><img src="{b("common-button-list-minus")}" width="13" height="4" style="margin-right:8px"><img src="{b("campaign_headericon_open")}" width="22"></div>' +
      '</div>'))

def skill_bar(text, share, width=300, fill="common-stat-bar-blue"):
    return (f'<div style="position:relative;width:{width}px;height:24px;border-image:url({b("common-stat-bar-bg")}) 10 fill / 10px stretch;box-sizing:border-box">'
            f'<div class="abs" style="left:4px;top:4px;bottom:4px;width:{(width - 8) * share:.0f}px;background:url({b(fill)}) 0 0/100% 100%"></div>'
            f'<div class="abs shadow" style="inset:0;display:flex;align-items:center;justify-content:center;font:600 13px var(--font-narrow);color:#fff">{text}</div></div>')
component("SkillBar", "Bars", 140,
"""# SkillBar
Forever's coloured progress bar (ColoredProgressBarTemplate): a dark rounded track, a fill in a colour, the value centred in white.

- Track `common-stat-bar-BG-c60` (a three-part frame, stretched); fill `common-stat-bar-blue-c60` for skills, `-green-c60` and `-red-c60` for other measures, `-white-c60` tinted for anything else.
- Value: "20 / 75" or "Leatherworking 20/75", white, Arial Narrow, centred.
- Professions also fill it with the profession's own art; skills always blue.
""", '<div style="display:flex;flex-direction:column;gap:10px">' + skill_bar("20 / 75", 20 / 75) + skill_bar("40 / 45", 40 / 45) + skill_bar("1 / 45", 1 / 45) + '</div>')

def gear(icon):
    return (f'<div style="position:relative;width:52px;height:52px"><div class="abs" style="inset:0;background:url({b("ui-character-info-gearslot")}) 0 0/52px 52px"></div>'
            f'<div class="abs" style="inset:7px;background:url({b(icon)}) center/112%"></div></div>')
component("Slots", "Items", 120,
"""# Slots
Frames that hold an icon: the character's gear slot, the profession slot, the spellbook tab, and the bronze frame of a big icon.

- `UI-Character-Info-GearSlot-c60` (55x55): the slot's ground, an equipped item's icon over it, inset 7px; empty, the slot's silhouette shows.
- `Professions-Slot-Frame` (40): a reagent or a profession's icon, its count bottom-right.
- `spellbook-skilllinetab` (40x58): a tab at the spellbook's side, the line's icon over it; the selected one glows gold.
- `heavybronze-frame-basic-c60` (80): a large icon's bronze square.
""", ('<div style="display:flex;gap:18px;align-items:flex-end">' + gear("inv_scroll_03") + gear("ability_tracking") +
      f'<div style="position:relative;width:40px;height:40px"><div class="abs" style="inset:3px;background:url({b("inv_misc_coin_01")}) center/112%"></div><div class="abs" style="inset:0;background:url({b("professions-slot-frame")}) 0 0/40px 40px"></div><div class="abs shadow" style="right:3px;bottom:1px;font:600 12px var(--font-narrow)">5</div></div>'
      f'<div style="position:relative;width:40px;height:58px"><div class="abs" style="inset:0;background:url({b("spellbook-skilllinetab")}) 0 0/40px 58px"></div><div class="abs" style="left:7px;top:15px;width:26px;height:26px;background:url({b("xp_icon")}) center/112%"></div></div>'
      f'<div style="position:relative;width:80px;height:80px"><div class="abs" style="inset:10px;background:url({b("inv_misc_pocketwatch_01")}) center/112%"></div><div class="abs" style="inset:0;background:url({b("heavybronze-frame-basic")}) 0 0/80px 80px"></div></div>'
      '</div>'))

component("SpellbookPage", "Frames", 330,
"""# SpellbookPage
Forever's parchment: the spellbook's page (`spellbook-Page-Right-C60`, `-Left-C60`), a heading, a drawn rule, entries of an icon with its name.

- Heading: dark ink, large (QuestTitleFont's place: `parchment-title`), then `spellbook-divider` (657x11) as its rule.
- Entries: the icon in its frame, its name in ink (`parchment-text`), a smaller grey-brown second line (the spellbook's "Rank 1"; here a chronicle's figures).
- The only parchment in Forever's windows: content that is read (a book, a page of things), not a panel of controls. No boxes on it.
""", (f'<div style="position:relative;width:390px;height:280px;background:url({b("spellbook-page-right")}) -2px -28px/405px 341px no-repeat;overflow:hidden">'
      '<div class="abs" style="left:58px;top:16px;font:26px var(--font-friz);color:var(--parchment-title);opacity:.85">At a glance</div>'
      f'<div class="abs" style="left:34px;top:56px;width:330px;height:6px;background:url({b("spellbook-divider")}) 0 0/330px 6px no-repeat"></div>'
      + "".join(f'<div class="abs" style="left:{x}px;top:{y}px;display:flex;gap:10px;align-items:center"><div style="width:38px;height:38px;background:url({b(icon)}) center/112%;box-shadow:0 0 0 2px #3a2a17"></div>'
                f'<div><div style="font:15px var(--font-friz);color:var(--parchment-text)">{name}</div><div style="font:12px var(--font-friz);color:#6b5530">{sub}</div></div></div>'
                for x, y, icon, name, sub in [(60, 80, "inv_misc_coin_01", "Gold", "12g 40s today"), (220, 80, "xp_icon", "Experience", "18,450 today"),
                                              (60, 136, "inv_scroll_03", "Quests", "14 today"), (220, 136, "inv_misc_pocketwatch_01", "Played", "2 h 51 m")]) + '</div>'), ground="#1b1712")

# Money and MapMarks stay as they were (unchanged files)

# ---- README ----------------------------------------------------------------------------------------------------
write(P("README.md"), """Build OneMoreQuest's windows from Forever's own window kit, so nothing looks bolted on. Every value here comes from the WoW Forever client (build 1.60.1): its templates (PortraitFrameTemplate, InsetFrameTemplate, NineSliceLayouts and Forever's own overrides), its atlases (Forever's variants end in `-c60`), its font styles (FontStyles.xml) and its colour table (GlobalColor). In an addon, inherit the game's templates and set atlases by name; never ship copies of the art.

## Two materials

- **Dark iron and stone**: windows, panels, lists, bars, tooltips. Forever's heavy bronze-and-iron frame (Window), rock and marble grounds, sunken panels (InsetPanel). Labels gold (`normal-font`, GameFontNormal), values white (`highlight-font`), state colours bright (`green-font`, `red-font`, `disabled-font`).
- **Parchment**: only for pages that are read, as the spellbook's (SpellbookPage). Dark ink (`parchment-text`), a large dark heading (`parchment-title`) over a drawn rule (`spellbook-divider`), entries as an icon with its name. Parchment carries **no boxes, fills or borders**.

Never mix them: no gold or white text on parchment, no ink on iron, no light rounded cards anywhere.

## Structure inside a window

- A window is a Window (portrait, title, close), holding one or more InsetPanels.
- Sections: a carved title plate (`UI-Character-Info-Title-c60`) with its name centred, then label-and-value lines ruled by `UI-Character-Info-ScrollLine-c60` (StatList).
- Collapsible groups: the group's name in gold, `common-button-list-minus` / `-plus` at the right (StatList).
- Progress: the SkillBar, its value centred in white.
- Things: an icon in its frame (Slots), never a bare square.
- Actions: RedButtons along the bottom; a CheckBox for options; a SearchBox and dropdown button above lists.

## Type

- Friz Quadrata (`Fonts\\FRIZQT__.TTF`) for nearly everything: GameFontNormalSmall 10, GameFontNormal 12, QuestFont 13, GameFontNormalLarge 16, GameFontNormalHuge 20.
- Morpheus (`Fonts\\MORPHEUS.ttf`) for quest titles and decorative headings: QuestTitleFont 18, QuestFont_Large 15, Fancy22Font 22.
- Arial Narrow (`Fonts\\ARIALN.TTF`) for numbers on bars and icons, and chat.
- On iron, text has a 1px black shadow; on parchment none.
- These pages show close free faces in their place (Marcellus, Metamorphous, Archivo Narrow); the real ones are the game's and are not copied here.

## Colour by meaning

- Quest levels: `difficulty-impossible` to `difficulty-trivial` against the player's level.
- Items: `quality-poor` to `quality-artifact` on names only.
- People: `class-warrior` to `class-druid` on names.
- Gains and losses: `green-font` and `red-font` on iron.

## Showing numbers

1. **A stat line**: label left in gold, value right in white, on a ruled line (StatList).
2. **A bar**: the SkillBar with "20 / 75" centred.
3. **An icon with a number**: a Slot with its count bottom-right, or an icon beside a label and value.

## Iconography

- Icons are the game's `Interface\\Icons\\*`, always inside a frame (Slots), cropped a little when the frame has none.
- Map and NPC marks are the game's atlases (MapMarks), never redrawn or recoloured.
- No emoji, no line-icon sets.

## Voice

- Short labels in sentence case, as the game writes them: "Track Recipe", "Show low-level quests", "Turn in to Rane Yorick".
- Numbers the game's way: "20 / 75", "6/10 Theramore Medal", "850 experience", "2 h 51 m".
""")

# ---- tokens: spacing for the modern kit -----------------------------------------------------------------------
t = json.load(open(P("tokens.json")))
t["spacing"]["tokens"] = [
    {"name": "window-corner", "value": "95px", "usage": "Forever's frame corners (-c60), drawn at their atlas size; the top-left holds the portrait ring."},
    {"name": "window-title", "value": "24px", "usage": "The title strip at a window's top; the title centred in it."},
    {"name": "inset-edge", "value": "6px", "usage": "InsetPanel corners; its edge tiles are 3px."},
    {"name": "tooltip-edge", "value": "7px", "usage": "Tooltip nine-slice corners and edges."},
    {"name": "button-height", "value": "24px", "usage": "RedButton height (22 to 26)."},
    {"name": "checkbox-size", "value": "30px", "usage": "checkbox-minimal, 30x29."},
    {"name": "search-height", "value": "30px", "usage": "SearchBox height; its art is 40 tall, drawn smaller."},
    {"name": "stat-line", "value": "28px", "usage": "A StatList line: label and value, ruled underneath."},
    {"name": "title-plate", "value": "32px", "usage": "UI-Character-Info-Title-c60, a section's carved title plate."},
    {"name": "gear-slot", "value": "55px", "usage": "UI-Character-Info-GearSlot-c60."},
    {"name": "profession-slot", "value": "40px", "usage": "Professions-Slot-Frame."},
]
for c in t["color"]["tokens"]:
    if c["name"] == "frame-ground":
        c["value"] = "#1b1712"; c["usage"] = "The rock ground of windows (UI-Background-Rock, its average): only for a flat fill where the texture cannot be used."
    if c["name"] == "parchment-ground":
        c["usage"] = "The spellbook page's parchment (spellbook-Page-Right-C60), roughly: only for a flat fill where the page cannot be used."
write(P("tokens.json"), json.dumps(t, indent=1, ensure_ascii=False))

# ---- asset groups ---------------------------------------------------------------------------------------------
NOTES = {
 "Window": "Forever's window frame (-c60 metal corners and edges with the portrait ring), the red close button, the rock and marble grounds and the title streaks.",
 "Inset": "The sunken panel's carved edge: 6px corners and 3px tiles (InsetFrameTemplate).",
 "Tooltip": "The tooltip's nine-slice: 7px corners and edges, and its centre (tinted tooltip-ground).",
 "Lists": "The character and skills windows' pieces: the title plate, ruled lines, gear slot, spellbook tab, list +/- and header buttons, the minimal checkbox and tick, the search field's three parts and glass, the dropdown button.",
 "Bars": "The coloured progress bar: its track, the blue fill of skills and the white fill to tint.",
 "Buttons": "The 128-RedButton kit: left, centre and right in normal, pressed and disabled, and the highlight.",
 "Professions": "The profession slot frame and the heavy bronze frame of a big icon.",
 "Spellbook": "The spellbook's parchment pages, its drawn divider and the backplate behind an entry.",
 "Money": "The gold, silver and copper coins written after money amounts.",
 "Map marks": "The game's quest and instance marks: questnormal, trivialquests, questdaily, questturnin, dungeon, raid.",
 "Icons": "Game icons used in the previews and OneMoreQuest's tiles.",
 "Classic textures": "Older art still in the client (the classic dialog box, tooltip border, quest parchment, panel button and checkbox, reward name frame, status bar). Forever's own windows do not use it: kept only to tell it apart.",
}
groups, order = {}, []
def add(table, group_of):
    for path, bid in table.items():
        group = group_of(path)
        name = path.split("/", 1)[1]
        source = os.path.join(MODERN if table is NEW else RAW, path)
        if group not in groups:
            groups[group] = {"name": group, "tile": "s" if group in ("Money", "Map marks", "Lists", "Inset", "Tooltip") else "m", "order": [], "files": {}}
            order.append(group)
        groups[group]["order"].append(name)
        groups[group]["files"][name] = {"name": name, "blob": bid, "size": os.path.getsize(source), "type": "image/png"}
add(NEW, lambda p: p.split("/")[0]); add(KEPT, lambda p: p.split("/")[0]); add(CLASSIC, lambda p: "Classic textures")
for group in order:
    write(P("assets", group, "README.md"), "# " + group + "\n\n" + NOTES[group] + " From the WoW Forever client (1.60.1), as PNG; in an addon set them by atlas name or game path.\n")
idx = json.load(open(P("design-system.json")))
idx["groups"] = order
idx["assetGroups"] = groups
idx["lastChange"] = {"by": "Claude", "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "via": "Claude Code",
                     "note": "Rebuilt on Forever's own window kit (-c60 atlases): Window, InsetPanel, RedButton, Tooltip, CheckBox, SearchBox, StatList, SkillBar, Slots, SpellbookPage"}
write(P("design-system.json"), json.dumps(idx, indent=1, ensure_ascii=False))
print(order)
