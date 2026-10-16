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

## Summary

Quality-of-life tools for Warlocks in World of Warcraft: Forever: Soul Shard management, Soulstone and Healthstone buttons, summon announcements, and a multi-mob DoT tracker.

## Description

Paste this with the description editor in Markdown mode. Pasted into the rich
text editor, the headings, bullets, and bold show as raw, escaped markdown.

Per-file changelogs need no manual text: each CI upload uses the version's
`CHANGELOG.md` section, through `release-notes.md`.

```markdown
**Warlock Tools Forever** is a growing set of quality-of-life tools for Warlocks. Each tool has its own switch and settings page.

### Soul Shards
- Limit the number of Soul Shards that occupy your bags!
- By default, the limit matches your soul bags' size (or 6 without a soul bag). Or you can set your own.
- Shards that Drain Soul or Shadowburn creates above your limit are deleted.
- Shards you move into your bags yourself, from the bank, mail, or trade, are never deleted. Only the shards created by spells go.
- Carried bags only; your bank is never touched.
- A movable shard counter shows your Soul Shards on screen: red when you run low (you pick the number), green at your limit.

### Stones
- A movable bar with a Soulstone and a Healthstone button. Left-click uses your best stone; right-click creates your best rank.
- With a friend targeted, a left-click on the Healthstone button trades them one they can use (or creates it first). A right-click on the Healthstone button creates the best rank they can use (without the trade).
- Middle-click the Healthstone button to always use your best Healthstone on yourself, whatever you have targeted.
- For your action bars: WTF keeps **! Healthstone** and **! Soulstone** macros in your character macros. Left-click uses your best stone, right-click creates one.
- Reminders when your Soulstone ends, when none is up, or when you carry no Healthstone.

### Alerts
- Optional Nightfall sound when Shadow Trance procs, with a choice of sounds.

### Announce
- When your Ritual of Summoning starts or a Soulstone use succeeds, we tell your raid or party and whisper the target.
- When the trade window opens for a Healthstone you give with the button, whisper the player.
- Creating a Healthstone or a Soulstone optionally emotes a little flavor for everyone nearby (at most once a minute).
- Every message has its own on/off switch and editable text. The defaults credit Warlock Tools Forever (WTF); change them to anything you like.

### DoT tracker
- Timers for Corruption, Immolate, Siphon Life, your Bane (Agony, Doom, Havoc), your Curse, and Fear and control, each in its own color (configurable).
- Pinned rows for your target (purple outline) and focus (red outline): click a slot to recast that spell.
- Two themes: Compact icons, or Bars that drain like the Cooldown Manager's, with each spell's name and time left.
- A list of up to eight other mobs you DoTed. Expired spells stay as dim icons, so you see what to recast.
- Optional colored DoT dots above hostile nameplates: grey means missing, at a glance.

### Commands
- `/wtf` or `/wtf options` opens the settings (Options > AddOns).
- `/wtf shards` shows your shard count and limit.
- `/warlocktools` works the same, in case another AddOn uses `/wtf`.

### Compatibility
Beta: tested on the Forever beta client 1.60.1, build 70338. WTF keeps working on later beta builds; if a client update removes an API it needs, it disables itself with one chat message.

WowUp users (2.24.0 or later): install from the repository URL; GitHub releases carry the Forever metadata WowUp needs.

Source, issues, and license (MIT): https://github.com/jbedworth/WarlockToolsForever
```
