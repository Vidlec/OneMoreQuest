# Money
Money as the game writes it: gold, silver and copper, each number followed by its coin (`Interface\MoneyFrame\UI-GoldIcon`, `UI-SilverIcon`, `UI-CopperIcon`).

- In text, GetMoneyString / GetCoinTextureString give "12|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t …": the coin at text height, 2px after its number.
- Leave out empty higher units (no "0 gold"); keep copper only where it matters (small sums, exact totals).
- A loss is the same coins after a minus sign, the text in `red-font` (dark frames) or `dim-red-font` (parchment).
