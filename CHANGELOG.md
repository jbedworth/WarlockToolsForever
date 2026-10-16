# Changelog

Player-facing changes for each Warlock Tools Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 0.1.0-beta

- First public beta for WoW: Forever.
- Soul Shard management: shards that Drain Soul or Shadowburn creates above your limit are deleted with no prompt, on your next key press or click (the game allows item deletion only then). Shards you move into your bags yourself are never deleted.
- The limit matches your soul bags' size, including a soul bag in the reagent bag slot, or 6 without a soul bag; you can set your own in Options > AddOns > Warlock Tools Forever > Soul Shards.
- Stones: a movable bar with Soulstone and Healthstone buttons. Left-click uses your best stone (a Soulstone on your friendly target, or yourself); right-click creates your best rank, and the Healthstone button creates the best rank your friendly player target can use.
- Announce: when your Ritual of Summoning starts, or a Soulstone use on another player succeeds, tell your raid or party and whisper the target. Each message has its own switch and editable text.
- DoT tracker: timers for Corruption, Immolate, Siphon Life, your Bane, your Curse, and Fear and control (Fear, Howl of Terror, Death Coil, Banish), with a color per slot that you can change. A pinned target row (purple outline) and focus row (red outline) on top, where clicking a slot recasts that spell, and a list of up to eight other mobs you DoTed below. Expired spells stay as dim icons. Two themes: Compact (icons) and Bars (a draining bar per spell, like the Cooldown Manager).
- Optional DoT dots on nameplates: in combat, a colored dot per DoT you know above each hostile nameplate, grey while missing.
- Middle-click on the Healthstone button always uses your best Healthstone on yourself.
- Stone macros: WTF keeps "! Healthstone" and "! Soulstone" in your character macros for your action bars; left-click uses your best stone, right-click creates one, also in combat.
- Creating a Healthstone when you already carry that rank makes the next lower rank instead.
- Healthstone trading: with a friendly player targeted, the Healthstone button trades them one they can use, or creates one first. When the trade window opens, WTF whispers them (its own switch and text on the Announce page).
- The default announcement texts credit Warlock Tools Forever (WTF). Texts you have edited are kept as they are.
- Stone status: a chat note when your Soulstone ends, and reminders when none is up or you carry no Healthstone; `/wtf stones` shows the status.
- Optional Nightfall sound when Shadow Trance procs, with a choice of sounds.
- `/wtf shards` shows your shard count and limit. `/wtf options` opens the settings.
- Settings are saved per character.
