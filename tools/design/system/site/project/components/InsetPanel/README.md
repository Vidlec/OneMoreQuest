# InsetPanel
A sunken panel inside a window (InsetFrameTemplate): darker marble ground with a thin carved edge.

- Ground `Interface\FrameGeneral\UI-Background-Marble`; edge pieces `UI-Frame-InnerTopLeft`, `-InnerTopRight`, `-InnerBotLeftCorner`, `-InnerBotRight` (6px) and tiles `_UI-Frame-InnerTopTile`, `_UI-Frame-InnerBotTile`, `!UI-Frame-InnerLeftTile`, `!UI-Frame-InnerRightTile` (3px).
- Groups content inside a window: a list, a details pane, a profession's area. Headings in GameFontNormal (`normal-font`), values in `highlight-font`.
- In an addon: inherit `InsetFrameTemplate`.
