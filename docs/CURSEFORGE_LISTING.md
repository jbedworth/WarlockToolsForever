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
| Relations | Dyre's Sounds (`dyres-sounds`), Required Dependency. Each CI upload sends it (`RELATIONS` in scripts/publish_curseforge.py); set it on the project too if the form asks. |

## Summary

Quality-of-life tools for Warlocks in World of Warcraft: Forever: Soul Shard management, Soulstone and Healthstone buttons, a multi-mob DoT tracker, a Fear and Banish bar, cooldown chimes, and customizable announcements with flavor.

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
- Two looks: **Bars** that drain like the Cooldown Manager's, or **Compact** icons. Every color is yours to change.
- Optional **DoT dots above enemy nameplates**: grey means missing.

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
- A countdown bar for **every mob you Fear or Banish**, plus a Fear timer under each feared nameplate, so you know which one breaks next.
- Banish marks its mob with the moon, so your group leaves it alone.
- **! Fear**, **! Banish**, and **! Seduction** macros: aim with your mouse, no retargeting.

### Stays out of your way
- Small frames you place yourself: `/wtf unlock` shows a grid, frames snap together, `/wtf lock` when you're done.
- No popups, no forced layouts. Everything has an off switch.

### Also included
- **Cooldown chimes** just before Death Coil, Howl of Terror, Shadow Ward, your Soulstone, and Fel Domination are ready, with a sound (or text-to-speech) for each.
- **Nightfall sound** when Shadow Trance procs.
- **Shield display:** a crescent that drains as your Shadow Ward, Sacrifice, or any absorb takes damage.
- **Demon Armor reminder** you can click to cast.
- **Announcements with flavor:** summons, Soulstones, and Healthstone trades tell your group or whisper the target. Every message can be edited or turned off.

### Sounds: Dyre's Sounds (required)
WTF's sounds come from **Dyre's Sounds**, which holds the sounds for all of Dyre's AddOns, so your computer keeps one copy. The CurseForge app installs it with WTF. Without it, WTF works but plays no sounds, and says so once in chat. With **Dyre's Cooldown Chimes** installed, WTF leaves the cooldown chimes to it, so you never hear one twice.

### Commands
- `/wtf` opens the settings. `/wtf shards` shows your shards and limit.
- `/wtf unlock`, `/wtf lock`, `/wtf reset` move your frames.
- `/warlocktools` works the same, in case another AddOn uses `/wtf`.

### Compatibility
Beta: tested on the Forever beta client 1.60.1, build 70338. If a client update removes an API it needs, WTF turns itself off with one chat message.

WowUp users (2.24.0 or later): install from the repository URL; GitHub releases carry the Forever metadata WowUp needs.

Source, issues, and license (MIT): https://github.com/jbedworth/WarlockToolsForever
```
