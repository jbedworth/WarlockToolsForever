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
| Relations | Dyre's Toolkit (`dyres-toolkit`), Dyre's Shields Up (`dyres-shields-up`), Dyre's Buff Reminders (`dyres-buff-reminders`), and Dyre's Debuff Tracker (`dyres-debuff-tracker`, project 1777574), Required Dependency (1.3.0: the shield display, cooldown chimes, Nightfall sound, and Demon Armor reminder moved to the first two; 1.11.0: the DoT tracker, DoT damage prediction, the smart curse, and the Control bar moved to Dyre's Debuff Tracker; Dyre's Sounds is no longer needed); Weapon Skills Forever (`weapon-skills-forever`), Optional Dependency. Each CI upload sends them (`RELATIONS` in scripts/publish_curseforge.py); set them on the project too if the form asks. |

## Summary

Quality-of-life tools for Warlocks in World of Warcraft: Forever: Soul Shard management, Soulstone and Healthstone buttons, and customizable announcements with flavor. Comes with Dyre's Debuff Tracker for your DoTs, Fears, and Banishes.

## Description

Paste this with the description editor in Markdown mode. Pasted into the rich
text editor, the headings, bullets, and bold show as raw, escaped markdown.

Per-file changelogs need no manual text: each CI upload uses the version's
`CHANGELOG.md` section, through `release-notes.md`.

```markdown
**Warlock Tools Forever (WTF)** is the toolkit a Warlock actually wants: keep your bags free of shard clutter, hand out Healthstones in one click, and let your group know what you are doing. Every tool has its own switch. Turn on what you use, ignore the rest.

### Soul Shards, handled
- Set a shard limit (it matches your soul bags by default). **Extra shards from Drain Soul and Shadowburn are deleted for you.**
- Shards you bring in yourself, from the bank, mail, or trade, are never touched.
- An on-screen counter turns **red when you run low** and green at your limit.

### Stones in one click
- A Soulstone and Healthstone bar: **left-click uses your best stone, right-click makes one.**
- Target a friend and left-click: WTF **trades them a Healthstone they can use**, and makes one first if needed.
- **! Healthstone** and **! Soulstone** macros for your action bars, kept up to date for you.
- Reminders when your Soulstone runs out, or when you carry no Healthstone.

### Stays out of your way
- Small frames you place yourself: `/wtf unlock` shows a grid, frames snap together, `/wtf lock` when you're done.
- While frames are locked, hold **Ctrl** and drag to move one frame (not in combat).
- No popups, no forced layouts. Everything has an off switch.

### Also included
- **Announcements with flavor:** summons, Soulstones, and Healthstone trades tell your group or whisper the target. Every message can be edited or turned off.

### Comes with Dyre's Debuff Tracker, Dyre's Shields Up, and Dyre's Buff Reminders
The CurseForge app installs them with WTF:
- **Dyre's Debuff Tracker:** WTF's DoT tracker (target, focus, and every other mob you DoT), DoT colors and nameplate DoT dots, predictive DoT damage with DIES, the smart curse, and the Fear and Banish bar with the **! Fear**, **! Banish**, and **! Seduction** macros. These moved there in WTF 1.11.0, where they are kept up to date, and it takes your WTF settings for them once.
- **Dyre's Shields Up:** the shield display, a crescent that drains as your Shadow Ward, Sacrifice, or any absorb takes damage.
- **Dyre's Buff Reminders:** cooldown chimes for Death Coil, Howl of Terror, Shadow Ward, your Soulstone, and more; the Nightfall sound when Shadow Trance procs (with Dyre's Toolkit 2.11 or later, with proc arcs); and a Demon Armor reminder you can click to cast.

The shield display, chimes, and reminders lived in WTF until 1.3.0. Your WTF settings for them are copied over the first time each AddOn runs.

### Commands
- `/wtf` opens the settings. `/wtf shards` shows your shards and limit, `/wtf stones` your stones.
- `/wtf unlock`, `/wtf lock`, `/wtf reset` move your frames.
- `/warlocktools` works the same, in case another AddOn uses `/wtf`.

### Compatibility
For World of Warcraft: Forever 1.60.1 (tested on build 70450). If a client update removes an API it needs, WTF turns itself off with one chat message.

WowUp users (2.24.0 or later): install from the repository URL; GitHub releases carry the Forever metadata WowUp needs.

Source, issues, and license (MIT): https://github.com/jbedworth/WarlockToolsForever
```
