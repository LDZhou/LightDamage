# Light Damage — WoW Forever edition

A damage meter for WoW Forever. Current fight, totals and history in one window.

Built for WoW Forever only (interface 16001). Mythic+ and arena features are removed, since Forever has neither.

## Install

Unzip into `World of Warcraft\_forever_\Interface\AddOns`. Retail and Classic clients ignore this build, so it never clashes with retail Light Damage. On CurseForge, pick the WoW Forever file.

## Features

- **Overview and single-stat views.** Several stats in one window, or one stat at a time.
- **Custom layouts.** Three presets, or your own grid up to 5×5. Merge and split cells, resize rows and columns.
- **Per-scene windows.** Raids, dungeons, battlegrounds and outdoors each keep their own layout, position and size.
- **Full runs.** A summary segment when you leave an instance.
- **Name format.** Full name, first name, surname, "F. Last" or a set number of characters.
- **Number format.** Nothing under 10,000 is shortened; then 12.3K / 1.23M (or 1.23万 / 1.23亿).
- **Appearance.** Fonts, bars, backgrounds, opacity, fading and collapsing.
- **Other Tools.** All off until you turn them on:
  - Final Fantasy XIV-style target arrow.
  - Item levels on the character panel.
  - Nameplate buff reminder: buffs on friendly players, and a glow when one you can cast is missing.
- **Languages.** English, Simplified Chinese, Traditional Chinese, Russian and Korean.

No other addons needed.

## Commands

- `/ld` — settings
- `/ld show` — show or hide the window
- `/ld reset` — clear all data
- `/ld lock` — lock or unlock the window
- `/ld lang <auto|enUS|zhCN|zhTW|ruRU|koKR>` — switch language
- `/ld np` — check the nameplate buff reminder
- `/ld help` — list commands
