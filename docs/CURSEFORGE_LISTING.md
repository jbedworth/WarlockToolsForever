# CurseForge listing

Copy-ready text for the CurseForge project form. Keep it aligned with README.md
and the tested client; do not advertise clients or versions that have not been
tested.

## Project fields

| Field | Value |
| --- | --- |
| Name | Warlock Tools Forever |
| Class | Addons |
| Main category | Warlock. Keep it identical to the TOC `## Category`, which groups the AddOn in the in-game AddOn list. |
| Additional categories | Bags & Inventory (CurseForge allows up to 4; unrelated ones can send the project back for changes). |
| Author shown | Dyre, set through the CurseForge account's username |
| License | MIT License |
| Logo | artwork/warlock-tools-forever-logo.png (1024 x 1024) |
| Source | https://github.com/jbedworth/WarlockToolsForever |
| Issues | https://github.com/jbedworth/WarlockToolsForever/issues |
| Donation | Ko-fi, https://ko-fi.com/dyre_janelle (the project's Donation field) |
| Relations | Dyre's Toolkit (`dyres-toolkit`), Dyre's Shields Up (`dyres-shields-up`), and Dyre's Buff Reminders (`dyres-buff-reminders`), Required Dependency (1.3.0: the shield display, cooldown chimes, Nightfall sound, and Demon Armor reminder moved there; Dyre's Sounds is no longer needed); Weapon Skills Forever (`weapon-skills-forever`), Optional Dependency. Each CI upload sends them (`RELATIONS` in scripts/publish_curseforge.py); set them on the project too if the form asks. |

## Summary

Quality-of-life tools for Warlocks in World of Warcraft: Forever: Soul Shard management, Soulstone and Healthstone buttons, a multi-mob DoT tracker, a Fear and Banish bar, and customizable announcements with flavor.

## Description

Paste this with the description editor in Markdown mode. Pasted into the rich
text editor, the headings, bullets, and bold show as raw, escaped markdown.

Per-file changelogs need no manual text: each CI upload uses the version's
`CHANGELOG.md` section, through `release-notes.md`.

```markdown
**Warlock Tools Forever (WTF)** is the toolkit a Warlock actually wants: track every DoT on every mob, keep your bags free of shard clutter, and hand out Healthstones in one click. Every tool has its own switch. Turn on what you use, ignore the rest.

### Track DoTs across the whole pull
- **Your target, your focus, and up to eight more mobs**, all at once. Each row shows your Curse, Bane, Corruption, Immolate, Siphon Life, and Fear or Banish, with a live countdown.
- **Missing DoTs stay visible** as dim icons, so you see what to recast at a glance.
- **Click a slot** on your target or focus row to recast that spell.
- Two looks: **Bars** that drain like the Cooldown Manager's, or **Compact** icons.
- Optional **DoT dots above enemy nameplates**: grey means missing. Choose which DoTs get a dot.
- **Move the target, focus, and other-mobs panels separately**: each snaps to your other Dyre's frames and to the grid.
- **Mob health on each row**: the name line becomes a health bar in the panel's color, with the number, the percent, or both.
- **Sizes for each look**: icon size, name width, text size, and name position; bar width and line height for Bars.
- **Opacity for each panel**, and for the nameplate DoT dots.
- **The DoTs page**: drag your DoTs into the order you cast them, on the rows and on the nameplate dots, and pick each DoT's color.
- **Panel colors**: the target, focus, and other-mobs panels each have their own section, with their color (outline and health bar) and opacity.
- In combat the game can hide which nameplate belongs to which mob. A mob you DoT without ever targeting or focusing it (for example with a mouseover macro) can show without its timers until you target or focus it.

### Soul Shards, handled
- Set a shard limit (it matches your soul bags by default). **Extra shards from Drain Soul and Shadowburn are deleted for you.**
- Shards you bring in yourself, from the bank, mail, or trade, are never touched.
- An on-screen counter turns **red when you run low** and green at your limit.

### Stones in one click
- A Soulstone and Healthstone bar: **left-click uses your best stone, right-click makes one.**
- Target a friend and left-click: WTF **trades them a Healthstone they can use**, and makes one first if needed.
- **! Healthstone** and **! Soulstone** macros for your action bars, kept up to date for you.
- Reminders when your Soulstone runs out, or when you carry no Healthstone.

### Fear and Banish control
- A countdown bar for **every mob you Fear** and for your **banished focus**, plus a Fear timer under each feared nameplate, so you know which one breaks next.
- **! Fear**, **! Banish**, and **! Seduction** macros for your action bars: aim with your mouse, no retargeting.

### Fear and your focus
- **! Fear** makes the mob under your mouse (else your target) your focus and fears it. **Shift-press** it to fear another mob and keep your focus.
- The **Focus box** above the Fear bars shows your focus's Fear. **Click it to fear your focus again**; with no focus it does nothing.
- Every other mob you fear gets its own row, and a Fear timer under its nameplate.
- **! Banish** works the same way: it makes the mob your focus, marks it with the moon so your group leaves it alone, and banishes it. Click its row to banish your focus again.

### Stays out of your way
- Small frames you place yourself: `/wtf unlock` shows a grid, frames snap together, `/wtf lock` when you're done.
- While frames are locked, hold **Ctrl** and drag to move one frame, a DoT tracker panel too (not in combat).
- No popups, no forced layouts. Everything has an off switch.

### Also included
- **Announcements with flavor:** summons, Soulstones, and Healthstone trades tell your group or whisper the target. Every message can be edited or turned off.

### Comes with Dyre's Shields Up and Dyre's Buff Reminders
The CurseForge app installs both with WTF, and they work on every class:
- **Dyre's Shields Up:** the shield display, a crescent that drains as your Shadow Ward, Sacrifice, or any absorb takes damage.
- **Dyre's Buff Reminders:** cooldown chimes for Death Coil, Howl of Terror, Shadow Ward, your Soulstone, and more; the Nightfall sound when Shadow Trance procs; and a Demon Armor reminder you can click to cast.

These lived in WTF until 1.3.0. Your WTF settings for them are copied over the first time each AddOn runs.

### Commands
- `/wtf` opens the settings. `/wtf shards` shows your shards and limit, `/wtf stones` your stones.
- `/wtf unlock`, `/wtf lock`, `/wtf reset` move your frames.
- `/warlocktools` works the same, in case another AddOn uses `/wtf`.

### Compatibility
For World of Warcraft: Forever 1.60.1 (tested on build 70450). If a client update removes an API it needs, WTF turns itself off with one chat message.

WowUp users (2.24.0 or later): install from the repository URL; GitHub releases carry the Forever metadata WowUp needs.

Source, issues, and license (MIT): https://github.com/jbedworth/WarlockToolsForever
```
