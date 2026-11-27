# Window
Forever's window (PortraitFrameTemplate): a heavy bronze-and-iron frame, a round portrait at its top left, the title in gold, a red close button.

- The frame is a nine-slice of Forever's own art: `UI-Frame-PortraitMetal-CornerTopLeft-c60` (with the portrait ring), `UI-Frame-Metal-CornerTopRight-c60`, `-CornerBottomLeft-c60`, `-CornerBottomRight-c60`, tiled `_UI-Frame-Metal-EdgeTop/Bottom-c60` and `!UI-Frame-Metal-EdgeLeft/Right-c60`. Corners sit 13 left, 16 above, and (Forever's override) 8 below the window.
- Ground: `Interface\FrameGeneral\UI-Background-Rock`, tiled; `_UI-Frame-TopTileStreaks` along the top under the title.
- Title: GameFontNormal (`normal-font`), centred in the top 24px. Close: `RedButton-Exit-c60` at the top right.
- Portrait: a 60px round icon (SetPortraitToTexture) under the ring.
- In an addon: inherit `PortraitFrameTemplate` (or `ButtonFrameTemplate` for one with an inset), never redraw the frame.
