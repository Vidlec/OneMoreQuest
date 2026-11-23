# StatList
The character window's lists: a section title on a carved plate, then label-and-value lines.

- Title plate `UI-Character-Info-Title-c60` (201x32), its text centred in GameFontHighlight (`highlight-font`): General, Primary Attributes, Weapons.
- Lines: label left in GameFontNormal (`normal-font`), value right in `highlight-font` (or `green-font` when raised), each line ruled by `UI-Character-Info-ScrollLine-c60`; `UI-Character-Info-ScrollLine-Long-c60` for full-width rows.
- Collapsible groups (the Skills window) put `common-button-list-minus` / `common-button-list-plus` at the right of the header; the campaign-style `campaign_headericon_open` / `_closed` where a header is a button.
