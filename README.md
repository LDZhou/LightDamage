# Light Damage — WoW Forever edition

Light Damage is a damage meter addon for World of Warcraft. It keeps current combat, total data, and combat history in one configurable window.

This branch is built only for **WoW Forever** (interface 16001, Blizzard game type "camelot"). Forever runs the 12.x engine with vanilla content. Blizzard's own Forever UI excludes the Mythic+ interface (`Blizzard_ChallengesUI`) and the arena/rated PvP interface (`Blizzard_PVPUI`). This edition removes everything that depended on them:

- Mythic+ run tracking, keystone levels and timers, and the Mythic+ run-wide session handling.
- The Mythic+ and Arena scene workspaces.
- Mythic+ rating in player tooltips and in the roster scan.

Every Blizzard API, event and enum the addon references is checked against Forever's generated API documentation (`tools/forever_api_check.js`).

## Install

Unzip into `World of Warcraft\_forever_\Interface\AddOns`, so the folder reads `LightDamage`. The addon ships `LightDamage_Camelot.toc`, the TOC that WoW Forever loads; retail and Classic clients ignore it. Each game keeps its own `Interface\AddOns` and saved settings, so this build and the retail Light Damage never touch each other. On CurseForge it is the file marked for WoW Forever (game version 1.60.1).

## Features

- **Overview and single-stat views:** The Overview combines multiple statistics in one window. Each statistic is also available as a focused single-panel view.
- **Custom Overview layouts:** Use one of three presets or create a grid from 1×1 to 5×5. Each cell can show Current or Total data. Cells can be merged or split, and row and column proportions can be adjusted.
- **Separate scene workspaces:** Raids, dungeons, battlegrounds, and outdoor content can each use a different layout and remember their own window position and overall size.
- **Instance overall segments:** Overall segments can be created after leaving the enabled instance types, with separate settings for each type.
- **Player name format:** Forever characters have a first name and a surname. Meter rows can show the full name, the first name, the surname, an abbreviation ("F. Last") or a fixed number of characters. The format applies to players only. In combat other players' names are protected and show in full; your own row always uses the format.
- **Number format:** Numbers follow EllesmereUI's meter rules. Nothing below 10,000 is abbreviated, then 12.3K / 1.23M / 1.23B (or 1.23万 / 1.23亿). Digits are truncated, plain numbers have no decimals, and a per-second rate below 1 reads 1. Live and archived fights use the same rules.
- **Appearance and behavior settings:** Configure fonts, bars, backgrounds, opacity, number and label formats, window locking, fading, and collapsing.
- **Tools page:**
  - *Final Fantasy XIV-style target arrow* above your target's nameplate, coloured by who the target is.
  - *Nameplate buff reminder* on friendly players: the group buffs they have, with a time-left swipe, and a glowing icon for each buff they lack that you can cast. A "only my class" switch and a per-buff list. It works on Blizzard's nameplates and on nameplate addons.
- **Languages:** English, Simplified Chinese, Traditional Chinese, Russian, and Korean. A language whose script the client's font cannot draw switches to Blizzard's font for it.

## Dependencies

None to install. LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 ship inside `Libs/` (LibSharedMedia only adds other addons' fonts and textures to the settings lists). The nameplate buff reminder uses the client's own `Blizzard_AuraContainer`.

## Performance

The render and lifecycle paths are tuned for long raid and battleground fights:

- **Bar rows:**
  - A row re-applies fonts, textures, rank text and value colours only when its style changes or it moves to another slot.
  - Class colour, public names and public icons are re-applied only when they change. Protected (secret) names and icons are still written every tick, so a different player taking a row is never shown stale.
- **Off-screen rows:** Rows outside a cell's scroll viewport are not re-rendered every tick. Scrolling repaints immediately.
- **Combat events:**
  - In combat the lifecycle snapshot is saved at the combat edge and at logout, not on every session event.
  - The live-session event only marks data dirty for the running render ticker.
- **Instance exits:** Archiving at an instance boundary is spread across frames, about 6 ms per watchdog tick, instead of hitching once.
- **Death recaps:** Each published recap is read once and cached.
- **Memory:** After login only the active language is kept, resolved straight into the string table.

## Slash commands

- `/ld` — Open or close the settings window.
- `/ld show` — Show or hide the main window.
- `/ld reset` — Clear all combat data.
- `/ld lock` — Lock or unlock the main window.
- `/ld lang <auto|enUS|zhCN|zhTW|ruRU|koKR>` — Switch language (reloads the UI).
- `/ld np` — Report the nameplate buff reminder's state, step by step for your target's plate.
- `/ld help` — List the available commands.
