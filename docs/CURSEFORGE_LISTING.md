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

Soul Shard cleanup, one-click stones, a DoT tracker, a Fear and Banish bar, procs, and reminders for Warlocks. For WoW: Forever and Classic Era.

## Description

Paste this with the description editor in Markdown mode. Pasted into the rich
text editor, the headings, bullets, and bold show as raw, escaped markdown.

Per-file changelogs need no manual text: each CI upload uses the version's
`CHANGELOG.md` section, through `release-notes.md`.

```markdown
I play a Warlock, and I got tired of juggling a pile of separate AddOns and a bag full of Soul Shards just to do the basics well. **Warlock Tools Forever (WTF)** is my answer. It's one AddOn with one settings page, and it covers everything I use, from shard cleanup to DoT tracking to a warning when your Voidwalker is about to pull aggro off the tank.

WTF does some of this itself, and my other Dyre's AddOns do the rest. The CurseForge app installs them with WTF, and you control all of it from WTF's settings. Each part has its own on and off switch on WTF's main page, so you turn on what you use and leave the rest off.

### Soul Shards
- WTF deletes the extra shards that Drain Soul and Shadowburn create. Your limit matches your soul bags, or you can set your own.
- Shards you bring in yourself from the bank, mail, or a trade are never deleted. In a dungeon or raid, WTF cleans up the extras you got inside as you leave.
- The **shard counter** shows how many shards you have. It turns red when you're running low and green when you're at your limit.
- Right-click the counter to delete every shard above your limit.

### Stones
- The **Stones bar** has Soulstone, Healthstone, Spellstone, and Firestone buttons. Left-click uses your best stone, and right-click makes one. You can lay it out as a row or a column.
- On Forever, Spellstones and Firestones go on your weapon. Their buttons glow when you carry one and your weapon has neither on (needs Dyre's Toolkit).
- Target a friend and left-click the Healthstone button, and WTF trades them the best Healthstone they can use. If you don't have one for them, it makes one first.
- WTF keeps two macros up to date for your action bars, **! Healthstone** and **! Soulstone**.
- WTF remembers who has your Soulstone and tells you when it ends. It also reminds you when no Soulstone is up or you're out of Healthstones.

### Announcements
- When you summon someone, Soulstone them, or trade them a Healthstone, WTF tells your group or whispers that player. You can edit every message or turn it off.
- WTF emotes when you make a Healthstone or a Soulstone.

### DoTs and crowd control, with Dyre's Debuff Tracker installed
- The **DoT tracker** shows your DoTs on your target, your focus, and every other mob you've DoTed. It covers your curse, Corruption, Immolate, Siphon Life, and your Bane, in the colors and order you pick.
- **Nameplate dots** show you at a glance which mobs still need a DoT.
- A block on the mob's health bar shows the damage your DoTs still have to deal. **DIES** shows up when that damage will finish the mob, so you can stop casting and move on.
- The **smart curse** picks Tongues, Elements, or Weakness for the mob in front of you. It comes with a "! Curse" macro and a key binding.
- The **Fear and Banish bar** shows a timer for each mob you control, with optional timers under their nameplates.
- The **! Fear**, **! Banish**, and **! Seduction** macros cast on the mob under your mouse, or on your target if there isn't one.
- Your group can get a message when you Fear, Banish, Enslave Demon, or cast Howl of Terror.
- A red **Demonic Brand** pentagram shows over the mob your Searing Pain branded, so you know your demon's next attack on it gets the bonus.

### Procs, reminders, and chimes, with Dyre's Buff Reminders installed
- **Nightfall** and **Decimation** show arcs on your screen when they proc, with an optional sound, so you don't miss an instant Shadow Bolt or Soul Fire.
- The **Demon Armor** reminder shows when your armor is off. Click it to cast your armor.
- The **demon reminder** shows when you don't have a demon out. Click it to summon your last demon.
- In a group where you aren't the tank, a message warns you while your Voidwalker's Torment or Suffering is on autocast.
- **Cooldown chimes** play a sound just before Death Coil, Howl of Terror, Shadow Ward, and other spells are ready again.
- Counters show your Infernal Stones and Demonic Figurines.

### Shields, with Dyre's Shields Up installed
- The **shield display** is a crescent beside your character. It drains as your Shadow Ward, your Voidwalker's Sacrifice, or any other absorb takes damage.

### Frames and settings
- Type `/wtf unlock` or `/dyre unlock` to move your frames. A grid shows up, and frames snap to each other and to my other AddOns' frames. Type `/wtf lock` when you're done.
- While your frames are locked, hold Ctrl and drag a frame to move just that one.
- WTF never opens a popup or forces a layout on you, and every part has an off switch.
- Your settings and frame places are part of your Dyre's Toolkit profile. You can copy them to another character, or export them as one line of text.

### Commands
- `/wtf` opens the settings.
- `/wtf shards` shows your shards and your limit.
- `/wtf stones` shows who has your Soulstone and which stones you carry.
- `/wtf unlock`, `/wtf lock`, and `/wtf reset` move your frames or put them back.
- `/warlocktools` does the same as `/wtf`, in case another AddOn already uses `/wtf`.

### What gets installed
The CurseForge app installs Dyre's Toolkit, Dyre's Debuff Tracker, Dyre's Buff Reminders, and Dyre's Shields Up with WTF. If one of them is missing, WTF still works, tells you once at login what to install, and its settings page says what that AddOn would add. Weapon Skills Forever works well with WTF, but you don't need it.

### Compatibility
WTF is made for World of Warcraft: Forever 1.60.1, tested on build 70888. It also runs on Classic Era, where Forever-only parts such as Demonic Brand don't show. If a game update removes something WTF needs, WTF turns itself off and tells you in one chat line.

WowUp 2.24.0 or later can install WTF from the repository URL, because the GitHub releases carry the data WowUp needs.

Let me know what you think! Questions, ideas, or bugs go in the comments.

Dyre's AddOns are free. If you enjoy them, you can support them on Ko-fi: https://ko-fi.com/dyre_janelle

Source and issues (MIT): https://github.com/jbedworth/WarlockToolsForever
```
