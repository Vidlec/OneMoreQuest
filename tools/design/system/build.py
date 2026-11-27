"""The WoW Forever UI design system: files under project/ for the Design System artifact."""
import json, os, datetime, sys
ROOT = sys.argv[1]
RAW = sys.argv[2]
P = lambda *parts: os.path.join(ROOT, "project", *parts)
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)

BLOBS = {  # file -> (group, blob id)
 "Bars/ui-statusbar.png": "602fac777ccc7be83e97049fc43e4827", "Buttons/common-input-border.png": "11fe4c867f7679fafa9e8bdb08452fbf",
 "Buttons/ui-character-activetab.png": "0976b9f8b95e2911daa8da5d179cb221", "Buttons/ui-character-inactivetab.png": "dc9fc3dab338d131e7373f11bad807b3",
 "Buttons/ui-checkbox-check.png": "7bb80b7bceac2f65afcaa31d8d440a7e", "Buttons/ui-checkbox-up.png": "dd18b56551047eb2a8cbb6fdeef2c95d",
 "Buttons/ui-panel-button-disabled.png": "b1cfa88a0ba20c2b2f131534bd418f13", "Buttons/ui-panel-button-down.png": "390b3ebc9149fb9b07303013cf7bec81",
 "Buttons/ui-panel-button-highlight.png": "b0d7c184f388eebf90101b4057d8db89", "Buttons/ui-panel-button-up.png": "d5f4b1acd3b5787fd3dd6b06ed613718",
 "Buttons/ui-panel-minimizebutton-up.png": "3a2667dd6eeea5d93872244abd1b8e56", "Buttons/ui-scrollbar-knob.png": "567dc75c0dce2f401ce575fbc4e18ffe",
 "Buttons/ui-scrollbar-scrollupbutton-up.png": "b7f32714ccb0a890c53e1590399ef3bc", "Buttons/ui-sliderbar-button-horizontal.png": "3ca6ae09dc58d2873485fffd34a414f1",
 "Frames/chatframebackground.png": "e29586f722b957c5de32639f702961d1", "Frames/questbg.png": "95d7b3fc106fdff94467eb7d15dffe90",
 "Frames/ui-dialogbox-background.png": "007f067a355920c4dd62bd87292cee75", "Frames/ui-dialogbox-border.png": "83bb84b4c8dc99d17ffa467c890a9a62",
 "Frames/ui-dialogbox-gold-border.png": "26a52e8a502f1ca43a304cf1112bd3b6", "Frames/ui-dialogbox-header.png": "b32c8d1531f2cf5eede118b4376d5a4d",
 "Frames/ui-tooltip-background.png": "02b38cf44e20b0ca95bb918806e8580f", "Frames/ui-tooltip-border.png": "b7279c2e57b6e66ee4ebf62e70fa58d2",
 "Icons/ability_tracking.png": "3dda39becb2bc87457cf7f9b6469efcd", "Icons/inv_misc_coin_01.png": "c64da4f76477a0580cf1d72b4a7b3d61",
 "Icons/inv_misc_pocketwatch_01.png": "0b9b83647452669cae335687f23ecad8", "Icons/inv_misc_ticket_tarot_madness.png": "b807364555bc149e56ac71faadf47bb7",
 "Icons/inv_scroll_03.png": "56f52b821467ae814310d1d943384f9a", "Icons/xp_icon.png": "915d1427cfaf22db82631671b324ca21",
 "Items/ui-emptyslot-white.png": "5c79636981641e149924b014697d9b77", "Items/ui-paperdoll-slot-chest.png": "a4ba2e2e439e8341fa74ce0969f8527f",
 "Items/ui-questitemhighlight.png": "7cf01475808a37989824b828ba3b46b0", "Items/ui-questitemnameframe.png": "6b4fe1ea96db03446e4a9234252f4415",
 "Items/ui-quickslot2.png": "76a6152b847edee667c0bfb44ce18fe3", "Map marks/dungeon.png": "e51d836bb274977d22f6d93343b19e30",
 "Map marks/questdaily.png": "766d47097adb62ff5c15cd9f26ab15e8", "Map marks/questnormal.png": "f06c285270ba70fd4c03038bb5caa28a",
 "Map marks/questturnin.png": "8b8ef702b70ab3012cae35b7a8186265", "Map marks/raid.png": "560ee6688d94343efaa39e31e8ec7571",
 "Map marks/trivialquests.png": "21571f8998157ccb1289eb47ff94c0ba", "Money/ui-coppericon.png": "040628cde515bff79d2b6fe38f99f786",
 "Money/ui-goldicon.png": "6ac8dc4ee70acc8840fdd4cdaa6dec58", "Money/ui-silvericon.png": "b8a295099dc58cf25fba0389ad83eb42",
}
def blob(name):
    for path, bid in BLOBS.items():
        if path.endswith("/" + name + ".png"):
            return "/_blob/" + bid
    raise KeyError(name)

def argb(v):  # GlobalColor ints: signed ARGB
    u = v & 0xFFFFFFFF
    return "#%06x" % (u & 0xFFFFFF)
def rgb(r, g, b):
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))

# ---- tokens -----------------------------------------------------------------------------------------------
C = []
def color(name, value, usage):
    C.append({"name": name, "value": value, "usage": usage})
color("normal-font", argb(-11776), "NORMAL_FONT_COLOR, the game's gold: labels, headings and titles on dark frames (GameFontNormal). On `frame-ground` and `tooltip-ground`.")
color("highlight-font", argb(-1), "HIGHLIGHT_FONT_COLOR: values, names and anything hovered or selected on dark frames (GameFontHighlight). On `frame-ground` and `tooltip-ground`.")
color("disabled-font", argb(-8355712), "DISABLED_FONT_COLOR / GRAY_FONT_COLOR: unavailable choices and secondary notes on dark frames (GameFontDisable).")
color("lightgray-font", argb(-6710887), "LIGHTGRAY_FONT_COLOR: quiet notes on dark frames, a step above `disabled-font`.")
color("red-font", argb(-57312), "RED_FONT_COLOR: errors, unmet requirements, money spent (GameFontRed). On dark frames only; on parchment use `dim-red-font`.")
color("dim-red-font", argb(-3401447), "DIM_RED_FONT_COLOR: a softer red for warnings that should not shout.")
color("green-font", argb(-15073511), "GREEN_FONT_COLOR: met requirements, gains, success (GameFontGreen). On dark frames.")
color("yellow-font", argb(-256), "YELLOW_FONT_COLOR: pure yellow for alerts and new things; not a substitute for `normal-font`.")
color("lightyellow-font", argb(-103), "LIGHTYELLOW_FONT_COLOR: flavour text in tooltips (item descriptions, quotes).")
color("orange-font", argb(-32704), "ORANGE_FONT_COLOR: cautions between yellow and red.")
color("blue-font", argb(-16728077), "BLUE_FONT_COLOR: system links and hints.")
color("passive-spell-font", argb(-3890432), "PASSIVE_SPELL_FONT_COLOR: passive effects in tooltips.")
color("parchment-text", argb(-13754609), "PARCHMENT_MATERIAL_TEXT_COLOR: running text on parchment (quest descriptions, objectives). On `parchment-ground`.")
color("parchment-title", argb(-16777216), "PARCHMENT_MATERIAL_TITLETEXT_COLOR: headings set in the quest title face on parchment.")
color("quest-title-brown", rgb(0.49, 0.35, 0.05), "QuestFont_Shadow_Huge's colour: the brown-gold of section headings on parchment (\"Rewards\", \"Description\").")
color("objective-font", argb(-3355444), "QUEST_OBJECTIVE_FONT_COLOR: objectives in the objective tracker, on the world.")
color("objective-highlight-font", argb(-1), "QUEST_OBJECTIVE_HIGHLIGHT_FONT_COLOR: a hovered objective.")
color("objective-disabled-font", argb(-8421505), "QUEST_OBJECTIVE_DISABLED_FONT_COLOR: an objective already done.")
color("parchment-ground", "#c79659", "The parchment's average colour (Interface\\QuestFrame\\QuestBG, sampled): only for a flat fill where the texture cannot be used.")
color("frame-ground", "#00000099", "UI-DialogBox-Background as drawn: black at 60%. The ground of dark windows and panels.")
color("tooltip-ground", argb(-15263952), "TOOLTIP_DEFAULT_BACKGROUND_COLOR, the tint over UI-Tooltip-Background: the tooltip's dark blue-black.")
color("tooltip-border", argb(-1), "TOOLTIP_DEFAULT_COLOR: the tint of the tooltip's border (white leaves its silver as drawn).")
for key, value, word, note in [("poor", -6447715, "Poor", "grey junk"), ("common", -1, "Common", "white"), ("uncommon", -14745856, "Uncommon", "green"),
                               ("rare", -16748323, "Rare", "blue"), ("epic", -6081042, "Epic", "purple"), ("legendary", -32768, "Legendary", "orange"),
                               ("artifact", -1651584, "Artifact", "pale gold")]:
    color("quality-" + key, argb(value), f"ITEM_{word.upper() if key not in ('uncommon','rare','common') else {'uncommon':'GOOD','rare':'SUPERIOR','common':'STANDARD'}[key]}_COLOR: names of {word} ({note}) items, in links, tooltips and loot.")
for key, (r, g, b), note in [("impossible", (1, 0.1, 0.1), "five or more levels above you"), ("verydifficult", (1, 0.5, 0.25), "three or four above"),
                             ("difficult", (1, 0.82, 0), "about your level"), ("standard", (0.25, 0.75, 0.25), "a little below"), ("trivial", (0.5, 0.5, 0.5), "far below: little reward"),
                             ("header", (0.7, 0.7, 0.7), "zone headers in quest lists")]:
    color("difficulty-" + key, rgb(r, g, b), f"QuestDifficultyColors.{key}: a quest's level and title, {note}.")
for key, (r, g, b) in [("warrior", (198, 155, 109)), ("paladin", (244, 140, 186)), ("hunter", (170, 211, 114)), ("rogue", (255, 244, 104)), ("priest", (255, 255, 255)),
                       ("shaman", (0, 112, 221)), ("mage", (63, 199, 235)), ("warlock", (135, 136, 238)), ("druid", (255, 124, 10))]:
    color("class-" + key, "#%02x%02x%02x" % (r, g, b), f"RAID_CLASS_COLORS.{key.upper()} (ChrClasses): a {key.title()}'s name in party frames, chat and tooltips.")

tokens = {
    "name": "WoW Forever UI", "version": 1,
    "color": {"themes": [{"id": "game", "name": "Game"}], "tokens": C},
    "type": {
        "fonts": [],
        "families": {"friz": "\"Marcellus\", \"Friz Quadrata TT\", Georgia, serif", "morpheus": "\"Metamorphous\", \"Morpheus\", Georgia, serif",
                     "narrow": "\"Archivo Narrow\", \"Arial Narrow\", Arial, sans-serif"},
        "groups": [
            {"name": "Game fonts (Fonts\\FRIZQT__.TTF)", "family": "friz", "styles": [
                {"name": "GameFontWhiteTiny", "fontSize": "9px", "lineHeight": "11px", "fontWeight": 400, "usage": "Tiny white labels: counts on icons, badges.", "sample": "12/40"},
                {"name": "GameFontNormalSmall", "fontSize": "10px", "lineHeight": "12px", "fontWeight": 400, "usage": "Small gold labels; GameFontHighlightSmall is the same in white.", "sample": "Quest objectives"},
                {"name": "GameFontNormal", "fontSize": "12px", "lineHeight": "14px", "fontWeight": 400, "usage": "The default: labels in `normal-font`; GameFontHighlight is the same in `highlight-font`.", "sample": "Tracked quests"},
                {"name": "QuestFont", "fontSize": "13px", "lineHeight": "16px", "fontWeight": 400, "usage": "Running text on parchment, in `parchment-text`.", "sample": "Bring me 8 Plainstrider Beaks."},
                {"name": "GameFontNormalLarge", "fontSize": "16px", "lineHeight": "19px", "fontWeight": 400, "usage": "Window titles and big numbers, gold.", "sample": "Map & Quest Log"},
                {"name": "GameFontNormalHuge", "fontSize": "20px", "lineHeight": "24px", "fontWeight": 400, "usage": "Headlines on dark frames, gold.", "sample": "Level 30"},
            ]},
            {"name": "Quest titles (Fonts\\MORPHEUS.ttf)", "family": "morpheus", "styles": [
                {"name": "QuestFont_Large", "fontSize": "15px", "lineHeight": "18px", "fontWeight": 400, "usage": "Section headings on parchment (\"Rewards\", \"Description\").", "sample": "Description"},
                {"name": "QuestTitleFont", "fontSize": "18px", "lineHeight": "21px", "fontWeight": 400, "usage": "A quest's title on parchment, in `parchment-title` (black).", "sample": "Centaur and Beast"},
                {"name": "Fancy22Font", "fontSize": "22px", "lineHeight": "26px", "fontWeight": 400, "usage": "Large decorative headings.", "sample": "The Barrens"},
            ]},
            {"name": "Numbers and chat (Fonts\\ARIALN.TTF)", "family": "narrow", "styles": [
                {"name": "NumberFontNormal", "fontSize": "14px", "lineHeight": "16px", "fontWeight": 400, "usage": "Stack counts and cooldown numbers, outlined.", "sample": "20"},
                {"name": "ChatFontNormal", "fontSize": "14px", "lineHeight": "17px", "fontWeight": 400, "usage": "Chat lines, white with a shadow.", "sample": "[Party] Garra: ready"},
            ]},
        ],
    },
    "spacing": {"tokens": [
        {"name": "tooltip-edge", "value": "16px", "usage": "Tooltip border pieces (UI-Tooltip-Border), edgeSize 16."},
        {"name": "tooltip-inset", "value": "5px", "usage": "Tooltip ground inset from the outside edge."},
        {"name": "dialog-edge", "value": "32px", "usage": "Dialog border pieces (UI-DialogBox-Border), edgeSize 32 (BACKDROP_DIALOG_32_32)."},
        {"name": "dialog-inset", "value": "11px", "usage": "Dialog ground inset: 11 left and bottom, 12 right and top."},
        {"name": "button-height", "value": "22px", "usage": "UIPanelButtonTemplate's height; its caps are 12px wide."},
        {"name": "checkbox-size", "value": "32px", "usage": "UICheckButtonTemplate, drawn at 32 or scaled to 24."},
        {"name": "item-slot", "value": "37px", "usage": "ItemButtonTemplate: an icon with its slot border."},
        {"name": "icon-reward", "value": "39px", "usage": "A quest reward's icon beside its name frame."},
    ]},
    "radius": {"tokens": [
        {"name": "radius-none", "value": "0px", "usage": "Everything in the game's frames is square; corners come from the border textures, never from rounding."},
    ]},
}
write(P("tokens.json"), json.dumps(tokens, indent=1, ensure_ascii=False))

# ---- shared preview helpers --------------------------------------------------------------------------------
FONTS = "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Archivo+Narrow:wght@400;600&family=Marcellus&family=Metamorphous&display=swap\">"
BACKDROP_JS = """
// Draws a backdrop as the game's Backdrop.lua does: a tiled ground inside the insets, and an edge texture of
// eight pieces (left, right, top, bottom, then the four corners), the top and bottom stored turned on their side
function drawBackdrop(canvas, groundSrc, edgeSrc, edge, insets, tint, groundAlpha) {
  const ctx = canvas.getContext("2d");
  const W = canvas.width, H = canvas.height;
  const load = (src) => new Promise((done) => { const img = new Image(); img.onload = () => done(img); img.src = src; });
  return Promise.all([load(groundSrc), load(edgeSrc)]).then(([ground, border]) => {
    ctx.save();
    ctx.globalAlpha = groundAlpha;
    const pattern = ctx.createPattern(ground, "repeat");
    ctx.fillStyle = pattern;
    ctx.fillRect(insets, insets, W - 2 * insets, H - 2 * insets);
    if (tint) { ctx.globalCompositeOperation = "multiply"; ctx.fillStyle = tint; ctx.fillRect(insets, insets, W - 2 * insets, H - 2 * insets); }
    ctx.restore();
    const tw = border.width, th = border.height;
    const piece = (index) => [tw * (index / 8 + 1 / 128), th * 0.0625, tw * 0.109375, th * 0.875];
    const draw = (index, x, y, w, h) => { const [sx, sy, sw, sh] = piece(index); ctx.drawImage(border, sx, sy, sw, sh, x, y, w, h); };
    for (let y = edge; y < H - edge; y += edge) { const h = Math.min(edge, H - edge - y); draw(0, 0, y, edge, h); draw(1, W - edge, y, edge, h); }
    for (let x = edge; x < W - edge; x += edge) {
      const w = Math.min(edge, W - edge - x);
      [[2, 0], [3, H - edge]].forEach(([index, y]) => {
        ctx.save(); ctx.translate(x + w, y); ctx.rotate(Math.PI / 2);
        const [sx, sy, sw, sh] = piece(index);
        ctx.drawImage(border, sx, sy, sw * (w / edge), sh, 0, 0, edge, w);
        ctx.restore();
      });
    }
    draw(4, 0, 0, edge, edge); draw(5, W - edge, 0, edge, edge); draw(6, 0, H - edge, edge, edge); draw(7, W - edge, H - edge, edge, edge);
  });
}
"""
def preview(group, height, body, script="", subtitle=""):
    sub = f' subtitle="{subtitle}"' if subtitle else ""
    return (f'<!-- @dsCard group="{group}" height={height}{sub} -->\n<!doctype html>\n<html><head><meta charset="utf-8">{FONTS}\n'
            '<style>body{margin:0;padding:16px;background:#14110d;color:var(--highlight-font);font-family:var(--font-friz)}'
            '.label{font:11px var(--font-narrow);color:var(--lightgray-font);letter-spacing:.02em}</style></head>\n'
            f'<body>{body}' + (f'<script>{script}</script>' if script else '') + '</body></html>\n')

COMP = {}
def component(name, group, height, readme, body, script="", subtitle=""):
    COMP[name] = True
    write(P("components", name, "README.md"), readme)
    write(P("components", name, "preview.html"), preview(group, height, body, script, subtitle))

# Button
component("PanelButton", "Controls", 100,
"""# PanelButton
The game's red panel button (UIPanelButtonTemplate), for actions in windows: Accept, Abandon, Done, Share.

- Built from three slices of `Interface\\Buttons\\UI-Panel-Button-Up`: a 12px left cap, a middle stretched to the width, a 12px right cap; 22px high (`button-height`). The top 22 of its 32 rows are used.
- States are other textures: `-Down` while pressed (the text moves 1px down and right), `-Highlight` added over it on hover (additive), `-Disabled` when unavailable.
- Label in GameFontNormal, `normal-font`; `highlight-font` while hovered; `disabled-font` when disabled.
- Provide: the label and the width (80 to 120 for one word; the game sizes to the text plus 20 to 40).
- Don't: round it, recolour it, or set it on parchment without the window's dark bottom bar behind it.
""",
"""<div style="display:flex;gap:18px;align-items:flex-end;flex-wrap:wrap">
<div><div class="pb" data-tex="up" style="width:96px">Accept</div><div class="label">up</div></div>
<div><div class="pb" data-tex="up" data-hover="1" style="width:96px;color:var(--highlight-font)">Abandon</div><div class="label">hover</div></div>
<div><div class="pb" data-tex="down" style="width:96px;padding-top:1px;padding-left:1px">Share</div><div class="label">pressed</div></div>
<div><div class="pb" data-tex="disabled" style="width:96px;color:var(--disabled-font)">Untrack</div><div class="label">disabled</div></div>
</div>
<style>.pb{position:relative;height:22px;display:flex;align-items:center;justify-content:center;font:12px var(--font-friz);color:var(--normal-font);text-shadow:1px -1px 0 #000;box-sizing:border-box}
.pb>i{position:absolute;top:0;height:22px;background-repeat:no-repeat;z-index:-1}.pb>span{position:relative}</style>""",
f"""const TEX = {{up: "{blob('ui-panel-button-up')}", down: "{blob('ui-panel-button-down')}", disabled: "{blob('ui-panel-button-disabled')}", hl: "{blob('ui-panel-button-highlight')}"}};
document.querySelectorAll('.pb').forEach((b) => {{
  const w = b.offsetWidth, mid = w - 24, url = TEX[b.dataset.tex];
  const text = b.textContent; b.textContent = '';
  const add = (src, css) => {{ const i = document.createElement('i'); i.style.cssText = css + `background-image:url(${{src}})`; b.appendChild(i); }};
  const layers = [url].concat(b.dataset.hover ? [TEX.hl] : []);
  layers.forEach((src, n) => {{
    const blend = n ? 'mix-blend-mode:screen;' : '';
    add(src, blend + `left:0;width:12px;background-size:128px 32px;background-position:0 0;`);
    add(src, blend + `left:12px;width:${{mid}}px;background-size:${{128 * mid / 56}}px 32px;background-position:${{-12 * mid / 56}}px 0;`);
    add(src, blend + `right:0;width:12px;background-size:128px 32px;background-position:-68px 0;`);
  }});
  const s = document.createElement('span'); s.textContent = text; b.appendChild(s);
}});""")

# CheckButton
component("CheckButton", "Controls", 90,
"""# CheckButton
The game's checkbox (UICheckButtonTemplate): a dark gold-rimmed square with a gold tick.

- `Interface\\Buttons\\UI-CheckBox-Up` drawn at 32px (`checkbox-size`), or scaled to 24 in dense lists; `UI-CheckBox-Check` over it when checked.
- Its label sits to the right in GameFontHighlight (`highlight-font`), 0 to 2px from the box's art edge (the texture has its own margin).
- Provide: the label and the checked state. Don't draw a separate border or rounding.
""",
f"""<div style="display:flex;gap:28px;align-items:center;flex-wrap:wrap">
<label style="display:flex;align-items:center;font:12px var(--font-friz);color:var(--highlight-font)"><span style="position:relative;width:32px;height:32px;background:url({blob('ui-checkbox-up')}) 0 0/32px 32px"></span>Show low-level quests</label>
<label style="display:flex;align-items:center;font:12px var(--font-friz);color:var(--highlight-font)"><span style="position:relative;width:32px;height:32px;background:url({blob('ui-checkbox-up')}) 0 0/32px 32px"><span style="position:absolute;inset:0;background:url({blob('ui-checkbox-check')}) 0 0/32px 32px"></span></span>Track quests automatically</label>
</div>""")

# Tooltip
component("Tooltip", "Frames", 170,
"""# Tooltip
The game's tooltip (GameTooltip): a dark blue-black ground in a thin silver border with round corners drawn by the texture.

- Backdrop: ground `Interface\\Tooltips\\UI-Tooltip-Background` tinted `tooltip-ground`, border `UI-Tooltip-Border` at `tooltip-edge` (16), ground inset `tooltip-inset` (5).
- First line: the subject in GameFontNormalLarge, coloured by meaning (an item's quality colour, `normal-font` for a quest, a class colour for a player). Then GameFontNormal lines: `highlight-font` for facts, `normal-font` for labels, `green-font` met, `red-font` unmet, `lightyellow-font` flavour.
- Two-column lines (AddDoubleLine) put a label left and its value right.
- Provide: the lines and their colours. Don't add icons in a column, separators or headings in other fonts.
""",
f"""<div style="position:relative;width:300px;height:132px">
<canvas id="tip" width="300" height="132" style="position:absolute;inset:0"></canvas>
<div style="position:relative;padding:10px 12px;font:12px/16px var(--font-friz)">
<div style="font-size:15px;line-height:19px;color:var(--normal-font)">[20] The Guns of Northwatch</div>
<div style="display:flex;justify-content:space-between;color:var(--highlight-font)"><span>Captain Fairmount slain</span><span>done</span></div>
<div style="display:flex;justify-content:space-between;color:var(--highlight-font)"><span>Theramore Medal</span><span>6/10</span></div>
<div style="color:var(--green-font)">Turn in to Captain Thalo'thas Brightsun</div>
<div style="color:var(--lightyellow-font)">"The Alliance has grown bold."</div>
</div></div>""",
BACKDROP_JS + f"""drawBackdrop(document.getElementById('tip'), "{blob('ui-tooltip-background')}", "{blob('ui-tooltip-border')}", 16, 5, getComputedStyle(document.documentElement).getPropertyValue('--tooltip-ground').trim() || '#171730', 0.92);""")

# DialogFrame
component("DialogFrame", "Frames", 230,
"""# DialogFrame
The game's dialog window (BACKDROP_DIALOG_32_32): a translucent black ground in a heavy carved silver-and-gold border, often with a header plate.

- Ground `Interface\\DialogFrame\\UI-DialogBox-Background` (black at 60%, `frame-ground`), tiled 32; border `UI-DialogBox-Border` at `dialog-edge` (32), insets `dialog-inset` (11/12).
- The header plate is `UI-DialogBox-Header`, centred on the top edge, its title in GameFontNormal (`normal-font`).
- Content: GameFontHighlight text, PanelButtons at the bottom. `UI-DialogBox-Gold-Border` is the gold variant for special prompts.
- Provide: the title, the text and the buttons. Keep content clear of the border by the insets plus 6 to 10px.
""",
f"""<div style="position:relative;width:340px;height:170px;margin-top:14px">
<canvas id="dlg" width="340" height="170" style="position:absolute;inset:0"></canvas>
<div style="position:absolute;left:50%;top:-14px;width:256px;height:64px;transform:translateX(-50%);background:url({blob('ui-dialogbox-header')}) 0 0/256px 64px no-repeat"></div>
<div style="position:absolute;left:0;right:0;top:-2px;text-align:center;font:12px var(--font-friz);color:var(--normal-font)">Abandon quest?</div>
<div style="position:absolute;left:24px;right:24px;top:44px;text-align:center;font:12px/16px var(--font-friz);color:var(--highlight-font)">Abandon "The Guns of Northwatch"? Its items will be lost.</div>
</div>""",
BACKDROP_JS + f"""drawBackdrop(document.getElementById('dlg'), "{blob('ui-dialogbox-background')}", "{blob('ui-dialogbox-border')}", 32, 11, null, 1);""")

# ParchmentPage
component("ParchmentPage", "Frames", 230,
"""# ParchmentPage
The quest page's parchment (QuestFrame): `Interface\\QuestFrame\\QuestBG` behind dark ink text.

- Title in QuestTitleFont (Morpheus 18, `parchment-title`); section headings in QuestFont_Large (Morpheus 15, `quest-title-brown`); running text in QuestFont (Friz 13, `parchment-text`).
- No boxes, fills or borders on parchment: structure comes from headings and spacing. Numbers stay ink; gains and losses take the darker `dim-red-font` or a deep green, never the bright dark-frame colours.
- Provide: the title, the sections and their text.
""",
f"""<div style="width:360px;height:200px;background:#3a2a17 url({blob('questbg')}) 0 0/512px 512px;padding:14px 18px;box-sizing:border-box;color:var(--parchment-text)">
<div style="font:18px var(--font-morpheus);color:var(--parchment-title)">Centaur and Beast</div>
<div style="font:13px/17px var(--font-friz);margin:6px 0 10px">Bring 8 Plainstrider Beaks and 10 Zhevra Hooves to Sergra Darkthorn in the Crossroads.</div>
<div style="font:15px var(--font-morpheus);color:var(--quest-title-brown)">Rewards</div>
<div style="font:13px/17px var(--font-friz);margin-top:4px">You will receive: 850 experience</div>
</div>""")

# RewardItem
component("RewardItem", "Items", 120,
"""# RewardItem
A quest reward as the quest page shows it: the item's icon in a slot, its name in a dark rounded name frame beside it.

- Icon 39px (`icon-reward`), its count bottom-right in NumberFontNormal; `Interface\\QuestFrame\\UI-QuestItemNameFrame` (128x64) behind the name, starting under the icon's right edge.
- Name in GameFontHighlight coloured by quality (`quality-uncommon` and so on); `UI-QuestItemHighlight` over the frame when chosen.
- This is the game's own way to show "a thing with a label" on parchment.
- Provide: icon, name, quality, count.
""",
f"""<div style="display:flex;gap:14px;flex-wrap:wrap;background:#3a2a17 url({blob('questbg')}) 0 0/512px 512px;padding:14px">
<div style="position:relative;width:170px;height:44px">
<div style="position:absolute;left:28px;top:-10px;width:128px;height:64px;background:url({blob('ui-questitemnameframe')}) 0 0/128px 64px"></div>
<div style="position:absolute;left:0;top:2px;width:39px;height:39px;background:url({blob('inv_misc_coin_01')}) center/cover;box-shadow:0 0 0 1px #000"></div>
<div style="position:absolute;left:46px;top:6px;width:100px;font:12px/14px var(--font-friz);color:var(--highlight-font)">22 Silver</div>
</div>
<div style="position:relative;width:170px;height:44px">
<div style="position:absolute;left:28px;top:-10px;width:128px;height:64px;background:url({blob('ui-questitemnameframe')}) 0 0/128px 64px"></div>
<div style="position:absolute;left:0;top:2px;width:39px;height:39px;background:url({blob('xp_icon')}) center/cover;box-shadow:0 0 0 1px #000"></div>
<div style="position:absolute;left:46px;top:6px;width:100px;font:12px/14px var(--font-friz);color:var(--quality-uncommon)">Scholarly Robes</div>
</div></div>""")

# StatusBar
component("StatusBar", "Bars", 120,
"""# StatusBar
A bar filled with `Interface\\TargetingFrame\\UI-StatusBar`, tinted by what it measures.

- The texture is white-grey with a soft top highlight; the game tints it with SetStatusBarColor: health green, mana blue, experience purple with the rested part blue, reputation by standing.
- A dark ground behind the empty part (black at 50%), a 1px black edge; the value centred on it in NumberFontNormal or GameFontHighlightSmall.
- Provide: the value, the maximum and the tint.
""",
"".join(f"""<div style="margin-bottom:10px"><div class="label">{label}</div><div style="position:relative;width:260px;height:{h}px;background:#00000080;box-shadow:0 0 0 1px #000">
<div style="position:absolute;left:0;top:0;bottom:0;width:{share}%;background:url({blob('ui-statusbar')}) 0 0/100% 100%;background-color:{tint};background-blend-mode:multiply"></div>
<div style="position:relative;text-align:center;font:600 11px/{h}px var(--font-narrow);color:#fff;text-shadow:1px 1px 0 #000">{text}</div></div></div>"""
for label, share, tint, h, text in [("Health", 82, "#00ff00", 12, "1,240 / 1,512"), ("Mana", 45, "#0000ff", 12, "640 / 1,420"), ("Experience (rested part follows)", 42, "#9900cc", 10, "42%")]))

# Money
component("Money", "Items", 70,
"""# Money
Money as the game writes it: gold, silver and copper, each number followed by its coin (`Interface\\MoneyFrame\\UI-GoldIcon`, `UI-SilverIcon`, `UI-CopperIcon`).

- In text, GetMoneyString / GetCoinTextureString give "12|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t …": the coin at text height, 2px after its number.
- Leave out empty higher units (no "0 gold"); keep copper only where it matters (small sums, exact totals).
- A loss is the same coins after a minus sign, the text in `red-font` (dark frames) or `dim-red-font` (parchment).
""",
f"""<div style="display:flex;gap:26px;align-items:center;font:14px var(--font-friz);color:var(--highlight-font);flex-wrap:wrap">
<span>8<img src="{blob('ui-goldicon')}" width="14" style="margin:0 6px 0 3px;vertical-align:-2px">27<img src="{blob('ui-silvericon')}" width="14" style="margin:0 6px 0 3px;vertical-align:-2px">37<img src="{blob('ui-coppericon')}" width="14" style="margin:0 0 0 3px;vertical-align:-2px"></span>
<span style="color:var(--red-font)">-13<img src="{blob('ui-silvericon')}" width="14" style="margin:0 6px 0 3px;vertical-align:-2px">43<img src="{blob('ui-coppericon')}" width="14" style="margin:0 0 0 3px;vertical-align:-2px"></span>
</div>""")

# Icons
component("ItemSlot", "Items", 100,
"""# ItemSlot
An icon in its slot (ItemButtonTemplate): the square icon at 37px (`item-slot`), framed by `Interface\\Buttons\\UI-Quickslot2`'s dark bevel.

- Icons are the game's own `Interface\\Icons\\*` (64x64), drawn cropped 0.08 in from each side to lose their baked border when shown bare.
- An empty slot shows `UI-EmptySlot-White` or a paper-doll slot picture (`UI-PaperDoll-Slot-*`).
- A quantity sits bottom-right in NumberFontNormal; quality shows as the name's colour, not as a border, in the classic UI.
""",
"<div style=\"display:flex;gap:14px;align-items:center\">" + "".join(
f"""<div style="position:relative;width:46px;height:46px"><div style="position:absolute;inset:0;background:url({blob('ui-quickslot2')}) center/64px 64px"></div>
<div style="position:absolute;inset:5px;background:url({blob(name)}) center/118% no-repeat"></div>{f'<div style="position:absolute;right:5px;bottom:3px;font:600 13px var(--font-narrow);color:#fff;text-shadow:1px 1px 0 #000,-1px -1px 0 #000">{count}</div>' if count else ''}</div>"""
for name, count in [("inv_scroll_03", ""), ("ability_tracking", "20"), ("inv_misc_pocketwatch_01", ""), ("inv_misc_ticket_tarot_madness", "3")]) +
f"""<div style="position:relative;width:46px;height:46px;background:url({blob('ui-paperdoll-slot-chest')}) center/40px 40px no-repeat;box-shadow:inset 0 0 0 1px #000"></div></div>""")

# MapMarks
component("MapMarks", "Map", 110,
"""# MapMarks
The game's own quest marks on the map and over NPCs, from its atlases.

- `questnormal`: a gold "!" for a quest to take. `trivialquests`: the grey "!" of a quest far below you. `questdaily`: the blue "!" of a repeatable one. `questturnin`: the gold "?" of a quest to hand in.
- `dungeon` and `raid`: entrance icons.
- Draw them at 16 to 24px on the map; never recolour them, and keep the game's meaning: gold is available or ready, grey is trivial, blue is repeatable.
""",
"<div style=\"display:flex;gap:22px;align-items:flex-end;flex-wrap:wrap;background:#5a4a2a;padding:12px\">" + "".join(
f"""<div style="text-align:center"><img src="{blob(name)}" width="{size}" height="{size}"><div class="label" style="color:#e8dcc0">{name}</div></div>"""
for name, size in [("questnormal", 26), ("trivialquests", 26), ("questdaily", 26), ("questturnin", 26), ("dungeon", 30), ("raid", 30)]) + "</div>")

# Scroll and tabs (pieces)
component("ScrollAndTabs", "Controls", 120,
"""# ScrollAndTabs
The small controls of scrolling lists and tabbed windows.

- Scroll bars: `Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up` (and Down) at 18 to 24px, the knob `UI-ScrollBar-Knob` riding a thin dark track.
- Close button: `UI-Panel-MinimizeButton-Up`, the red-and-gold X, at a window's top-right corner.
- Character tabs: `Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab` for the selected one, `-InactiveTab` for the rest, each label in GameFontNormalSmall (`highlight-font` when active).
""",
f"""<div style="display:flex;gap:24px;align-items:center;flex-wrap:wrap">
<img src="{blob('ui-scrollbar-scrollupbutton-up')}" width="28"><img src="{blob('ui-scrollbar-knob')}" width="28"><img src="{blob('ui-panel-minimizebutton-up')}" width="30"><img src="{blob('ui-sliderbar-button-horizontal')}" width="28">
<div style="display:flex;gap:0;align-items:flex-end">
<div style="position:relative;width:96px;height:48px;background:url({blob('ui-character-activetab')}) 0 0/96px 48px;text-align:center;font:10px/56px var(--font-friz);color:var(--highlight-font)">Character</div>
<div style="position:relative;width:96px;height:24px;background:url({blob('ui-character-inactivetab')}) 0 0/96px 24px;text-align:center;font:10px/26px var(--font-friz);color:var(--normal-font)">Reputation</div>
</div></div>""")

# Cover
write(P("components", "Cover", "preview.html"), f"""<!-- @dsCard height=300 -->
<!doctype html>
<html><head><meta charset="utf-8">{FONTS}
<style>
html,body{{margin:0;height:100%}}
body{{background:#14110d;width:960px;height:300px;position:relative;overflow:hidden;font-family:var(--font-friz)}}
.gold{{fill:var(--normal-font)}} .parch{{fill:var(--parchment-ground)}} .ink{{fill:var(--parchment-text)}} .blue{{fill:var(--quality-rare)}} .epic{{fill:var(--quality-epic)}} .green{{fill:var(--quality-uncommon)}}
.name{{position:absolute;left:44px;bottom:58px;font:400 72px/.94 var(--font-morpheus);color:var(--normal-font);max-width:440px}}
.tag{{position:absolute;left:46px;bottom:30px;font:13px var(--font-friz);color:var(--lightgray-font)}}
</style></head><body>
<svg width="960" height="300" style="position:absolute;inset:0">
<!-- blocks: parchment-ground 300x300 slab, normal-font gold 140x160, parchment-text ink 140x140, quality-rare 70x70
     arrangement: one tall parchment slab right with gold and ink satellites, square like the game's frames
     pattern: the item qualities as a strip of square slots at item-slot (37) pitch: the game's own way to say value
     steps and radii: item-slot 37, dialog-edge 32, radius-none 0 -->
<rect class="parch" x="660" y="0" width="300" height="300"/>
<rect class="gold" x="520" y="0" width="140" height="160"/>
<rect class="ink" x="520" y="160" width="140" height="140"/>
<rect class="blue" x="590" y="230" width="70" height="70"/>
<g>
<rect class="green" x="692" y="232" width="32" height="32"/><rect class="blue" x="729" y="232" width="32" height="32"/><rect class="epic" x="766" y="232" width="32" height="32"/><rect class="gold" x="803" y="232" width="32" height="32"/>
</g>
</svg>
<div class="name">WoW Forever UI</div>
<div class="tag">The game's own frames, fonts and colours, for addons that belong in it.</div>
</body></html>
""")

# ---- README -------------------------------------------------------------------------------------------------
write(P("README.md"), """Build OneMoreQuest's windows from the game's own parts, so nothing looks bolted on. Every value here comes from the WoW Forever client (build 1.60.1): its font styles (FontStyles.xml), its colour table (GlobalColor), its backdrops (Backdrop.lua) and its textures. In an addon, load the textures by their game path and the fonts with the game's font objects; never ship copies.

## Two materials

The game has two grounds, and every window uses one of them for each part:

- **Dark frames**: windows, tooltips, the tracker, bars. Text is gold for labels (`normal-font`, GameFontNormal) and white for values (`highlight-font`, GameFontHighlight); state colours are the bright `green-font`, `red-font`, `disabled-font`. Grounds are `frame-ground` (UI-DialogBox-Background) or `tooltip-ground`.
- **Parchment**: the quest page, books, letters. Text is dark ink (`parchment-text`), titles black in Morpheus (`parchment-title`), section headings brown-gold (`quest-title-brown`). Parchment carries **no boxes, fills or borders**: only headings, spacing and the game's own inset pieces (the reward name frame, the dark reward strip).

Never mix them: no white or gold text on parchment, no dark ink on dark frames, no light rounded cards anywhere.

## Type

- Friz Quadrata (`Fonts\\FRIZQT__.TTF`) for nearly everything: GameFontNormalSmall 10, GameFontNormal 12, QuestFont 13, GameFontNormalLarge 16, GameFontNormalHuge 20.
- Morpheus (`Fonts\\MORPHEUS.ttf`) only for titles and headings on parchment: QuestTitleFont 18, QuestFont_Large 15, Fancy22Font 22.
- Arial Narrow (`Fonts\\ARIALN.TTF`) for numbers on icons and for chat.
- On dark frames text has a 1px black shadow (offset 1, -1); on parchment it has none.
- These pages show close free faces in their place (Marcellus, Metamorphous, Archivo Narrow); the real ones are the game's and are not copied here.

## Colour by meaning

- Quest levels: `difficulty-impossible`, `difficulty-verydifficult`, `difficulty-difficult`, `difficulty-standard`, `difficulty-trivial`, against the player's level.
- Items: the quality colours, `quality-poor` to `quality-artifact`, on the item's name only.
- People: the class colours, `class-warrior` to `class-druid`, on names.
- Gains and losses: `green-font` and `red-font` on dark frames; on parchment, darker ink tones.

## Frames and spacing

- Tooltips: UI-Tooltip-Background tinted `tooltip-ground` in UI-Tooltip-Border, `tooltip-edge` 16, `tooltip-inset` 5.
- Dialogs: UI-DialogBox-Background in UI-DialogBox-Border, `dialog-edge` 32, `dialog-inset` 11/12, a UI-DialogBox-Header plate for the title.
- Corners are square (`radius-none`); any rounding comes from the border textures.
- Buttons are 22px high (`button-height`), checkboxes 32 (`checkbox-size`), item slots 37 (`item-slot`), reward icons 39 (`icon-reward`).

## Showing numbers

The game shows a number with a label in three ways, and OneMoreQuest should use these, never its own boxes:

1. **The dark reward strip** (the quest page's Rewards): icons with their numbers on dark wood, inside the parchment.
2. **The reward name frame** (RewardItem): an icon beside its name in UI-QuestItemNameFrame.
3. **A fact line**: label left in `normal-font` (dark frames) or ink (parchment), value right, as tooltips' double lines.

## Iconography

- Icons are the game's `Interface\\Icons\\*`, 64x64, square, cropped 0.08 in from each side when shown without a slot.
- Map and NPC marks are the game's atlases (`questnormal`, `questturnin`, `trivialquests`, `questdaily`, `dungeon`, `raid`), never redrawn or recoloured.
- No emoji, no line-icon sets.

## Voice

- Labels are short and plain, in sentence case, as the game writes them: "Show low-level quests", "Turn in to Rane Yorick", "Abandon quest?".
- Numbers are exact and unit-led the game's way: "6/10 Theramore Medal", "850 experience", "2 h 51 m".
""")

# ---- asset groups ------------------------------------------------------------------------------------------
NOTES = {
 "Frames": "Grounds and borders of the game's windows: the dialog box (ground, border, header, gold border), the tooltip (ground, border), the quest page's parchment (questbg) and the chat ground. Edge textures hold eight pieces side by side (left, right, top, bottom, then the corners); the top and bottom are stored turned on their side.",
 "Buttons": "Controls: the red panel button in its four states, the checkbox and its tick, the close button, scroll bar arrows and knob, the slider thumb, the character tabs and the input border.",
 "Items": "Item slots and the quest reward name frame (with its highlight), the empty slot and a paper-doll slot picture.",
 "Bars": "UI-StatusBar: the fill of every status bar, tinted by what it measures.",
 "Money": "The gold, silver and copper coins written after money amounts.",
 "Icons": "Game icons used by OneMoreQuest's reward strips and tiles: coin, experience, scroll, tracking (kills), pocket watch (time), tarot card (luck).",
 "Map marks": "The game's quest and instance marks, cropped from its atlases: questnormal, trivialquests, questdaily, questturnin, dungeon, raid.",
}
groups, order = {}, []
for path, bid in BLOBS.items():
    group, name = path.split("/", 1)
    if group not in groups:
        groups[group] = {"name": group, "tile": "s" if group in ("Money", "Map marks", "Buttons") else "m", "order": [], "files": {}}
        order.append(group)
    size = os.path.getsize(os.path.join(RAW, path))
    groups[group]["order"].append(name)
    groups[group]["files"][name] = {"name": name, "blob": bid, "size": size, "type": "image/png"}
for group in order:
    write(P("assets", group, "README.md"), "# " + group + "\n\n" + NOTES[group] + " All are the game's own files from the WoW Forever client (1.60.1), as PNG; in an addon load them by their game path.\n")
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
index = {"v": 3, "layout": "files", "createdOnFiles": {"v": 1, "at": now}, "title": "WoW Forever UI", "namespace": "WowForeverUI",
         "libraries": [], "sections": {}, "groups": order, "assetGroups": groups, "blobs": {}, "docs": {"readme": "project/README.md", "sections": []},
         "lastChange": {"by": "Claude", "at": now, "via": "Claude Code", "note": "The game's frames, fonts, colours and textures, from the WoW Forever client"}}
write(P("design-system.json"), json.dumps(index, indent=1, ensure_ascii=False))
files = []
for base, _, names in os.walk(os.path.join(ROOT, "project")):
    for n in names:
        files.append(os.path.relpath(os.path.join(base, n), ROOT))
print(json.dumps(sorted(f for f in files if not f.endswith("design-system.json"))))
