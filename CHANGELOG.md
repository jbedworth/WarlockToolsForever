# Changelog

Player-facing changes for each Warlock Tools Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 0.2.2-beta

- Shield display: the outer crescent is centered with the inner ones again; since the last update it was drawn lower and taller than them.

## 0.2.1-beta

- Shield display: tiny shields no longer flicker the crescent. Absorbs under 25 points or 5% of your health, whichever is larger, are not drawn (a Paladin's Seal of Righteousness gives one of 10-20 points).
- The sound when a shield ends now plays (the old sound did not play on Forever). Choose it from nine sounds under its switch; choosing one plays it.
- Cooldown chimes: Dyre's Picks, nine new sounds, lead each chime's sound menu.
- Nightfall sound: Dyre's Picks lead its menu too. Raid warning, Ready check, and Alarm clock are gone, since they did not play on Forever; if you chose one, the Imp spell chirp plays instead.
- With Dyre's Shields Up (formerly Shields Up Forever) also installed, you still see one display.

## 0.2.0-beta

- Control bar: a bar for each mob you Fear or Banish, with its name and time left. A Banished mob gets the moon marker when the cast lands (never toggled off), and clicking its row banishes your focus again. Fear timers show under each feared mob's nameplate. Optional group messages for Fear, Banish, Enslave Demon, and Howl of Terror.
- New macros: "! Fear" (the mob under your mouse, else your target), "! Banish", and "! Seduction" (once your Succubus or Incubus knows it), which focus the mob under your mouse and cast on your focus.
- Cooldown chimes: a sound just before Death Coil, Howl of Terror, Shadow Ward, your Soulstone, Fel Domination, and other spells you pick are ready again, also in combat, with a sound of your choice for each or a voice that says its name.
- Shield display: a crescent beside your character that fills with your Shadow Ward, your Voidwalker's Sacrifice, or any absorb on you, like Power Word: Shield, also in combat. A Paladin's Blessing of Protection shows as a gold inner crescent that drains with its time left. With Mage Tools Forever or Shields Up Forever also installed, you still see one display.
- Demon Armor reminder: a pulsing icon while you have neither Demon Armor nor Demon Skin; click it to cast your armor.
- The Nightfall sound is picked from menus grouped like the Cooldown Manager's.
- Every frame is magnetic: drop one near another and it snaps beside it, lined up. Shift-drag moves a snapped group.
- Warnings also show in red at the top of the screen.

## 0.1.1-beta

- One lock for every frame: `/wtf unlock` outlines the Stones bar and the shard counter and shows sample DoT tracker rows, so you can drag them all; `/wtf lock` locks them again. The main settings page has the same switch, "Unlock frames to move them", and the separate lock and sample-row switches are gone.
- While frames are unlocked, a faint grid covers the screen with its center lines in red, so you can line frames up. Turn it off with "Show a grid while unlocked" on the main settings page.

## 0.1.0-beta

- First public beta for WoW: Forever.
- Soul Shard management: shards that Drain Soul or Shadowburn creates above your limit are deleted with no prompt, on your next key press or click (the game allows item deletion only then). Shards you move into your bags yourself are never deleted.
- Shard counter: a movable Soul Shard icon with your shard count, red when low (a setting, 2 by default) and green at your limit.
- The limit matches your soul bags' size, including a soul bag in the reagent bag slot, or 6 without a soul bag; you can set your own in Options > AddOns > Warlock Tools Forever > Soul Shards.
- Stones: a movable bar with Soulstone and Healthstone buttons. Left-click uses your best stone (a Soulstone on your friendly target, or yourself); right-click creates your best rank, and the Healthstone button creates the best rank your friendly player target can use.
- Announce: when your Ritual of Summoning starts, or a Soulstone use on another player succeeds, tell your raid or party and whisper the target. Each message has its own switch and editable text.
- DoT tracker: timers for Corruption, Immolate, Siphon Life, your Bane, your Curse, and Fear and control (Fear, Howl of Terror, Death Coil, Banish), with a color per slot that you can change. A pinned target row (purple outline) and focus row (red outline) on top, where clicking a slot recasts that spell, and a list of up to eight other mobs you DoTed below. Expired spells stay as dim icons. Two themes: Compact (icons) and Bars (a draining bar per spell, like the Cooldown Manager).
- Optional DoT dots on nameplates: in combat, a colored dot per DoT you know above each hostile nameplate, grey while missing.
- Middle-click on the Healthstone button always uses your best Healthstone on yourself.
- Stone macros: WTF keeps "! Healthstone" and "! Soulstone" in your character macros for your action bars; left-click uses your best stone, right-click creates one, also in combat.
- Creating a Healthstone when you already carry that rank makes the next lower rank instead.
- Healthstone trading: with a friendly player targeted, the Healthstone button trades them one they can use, or creates one first. When the trade window opens, WTF whispers them (its own switch and text on the Announce page).
- The default announcement texts credit Warlock Tools Forever (WTF).
- Creating a Healthstone or a Soulstone emotes, at most once a minute per stone, with its own switch and text. Texts you have edited are kept as they are.
- Stone status: a chat note when your Soulstone ends, and reminders when none is up or you carry no Healthstone; `/wtf stones` shows the status.
- Optional Nightfall sound when Shadow Trance procs, with a choice of sounds.
- `/wtf shards` shows your shard count and limit. `/wtf options` opens the settings.
- Settings are saved per character.
