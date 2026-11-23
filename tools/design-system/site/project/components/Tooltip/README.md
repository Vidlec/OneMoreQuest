# Tooltip
The game's tooltip (GameTooltip, `TooltipDefaultLayout`): a near-black blue ground in a thin grey edge with soft corners.

- Nine-slice `Tooltip-NineSlice-CornerTopLeft`, `-CornerTopRight`, `-CornerBottomLeft`, `-CornerBottomRight` (7px), tiles `_Tooltip-NineSlice-EdgeTop/Bottom` and `!Tooltip-NineSlice-EdgeLeft/Right`, the centre `Tooltip-NineSlice-Center` tinted `tooltip-ground`.
- First line in GameFontNormalLarge coloured by meaning (`normal-font` for a quest, an item's quality colour, a class colour); then GameFontNormal lines: `highlight-font` facts, `green-font` met, `red-font` unmet, `lightyellow-font` flavour. AddDoubleLine for label and value.
