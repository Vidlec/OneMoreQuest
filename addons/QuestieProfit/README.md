# Questie Profit

Adds the expected profit of a quest to Questie on WoW: Forever (interface 16001).

Profit = quest money + best reward item + expected loot of the mobs the quest makes you kill.

## Install

Copy this folder to `Interface/AddOns/QuestieProfit` of the Forever client.

| Addon | Needed | Used for |
|---|---|---|
| Questie (12.9 or newer, with QuestieDB) | yes | quest objectives, quest-item drop rates |
| Tnny's Mob Loot | optional | drop chances per mob; without it mob loot counts as 0 |
| Auctionator | optional | auction prices; without it vendor prices are used |

## Use

- Hover a Questie icon on the map or minimap: the tooltip gets a "Profit" block; estimated amounts are marked with `~`.
- `/qprofit` opens a window with every quest in the quest log, highest estimated profit first.
- `/qprofit vendor` or `/qprofit auction` picks the price source.
- `/qprofit tooltip` shows or hides the tooltip block.

## How it is calculated

- Reward money and reward items come from the game. Of the items to choose from, only the most valuable is counted.
- Kill objective: the remaining kill count.
- Collect objective: remaining items divided by the drop chance of the mob that drops it most often.
- Loot per kill: sum of drop chance times item value. Forever data (Everloot) is used once a mob has 20 recorded kills, else the Classic estimate.
- Auction prices are taken after the 5% cut and never below the vendor price. Bind-on-pickup items use the vendor price.

## Limits

- Coins dropped by mobs are not included; no data source has them.
- Loot is only estimated when the game reports objective counts, which it reliably does for quests in the quest log.

## Licence and data

GPL-3.0. The addon bundles no loot data. Drop rates are read at runtime from Tnny's Mob Loot
(Everloot contributors, CC BY-SA 4.0; CMaNGOS classic-db, GPL-3.0).
