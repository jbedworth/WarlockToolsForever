# Changelog

Player-facing changes for each Warlock Tools Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 1.1.0

### Features
- DoT tracker: your target's row, your focus's row, and the list of other mobs are now three panels that move separately. Unlock frames and drag each one by its rows; each snaps to other frames and to the grid. They start where your tracker was, and `/wtf reset` stacks them again.
- DoT tracker: **Show mob health** (off by default) turns the line with each mob's name into its health bar, also in combat, in the panel's color: purple for your target, red for your focus, dark grey for the others. **Health text** adds its number, its percent, or both, such as "31% | 294".
- DoT tracker: sizes for each theme on the DoT Tracker page. Compact: icon size, name width, text size, and the name left, right, above, or below the icons. Bars: bar width, line height, text size, and the name above or below the bars. **Reset size** puts the theme back as it was, and the defaults keep the look you know.
- DoT tracker: **Target panel opacity**, **Focus panel opacity**, and **Other mobs panel opacity** (10% to 100%, 100% by default) make each panel see-through on its own, with its DoT bars.
- Nameplate DoT dots: **Nameplate dot opacity** (10% to 100%, 100% by default) makes the bubble above each nameplate see-through.
- DoT tracker: mob names stay on one line and use all the room they have. A name that does not fit is cut with "..." instead of wrapping out of its row.

### Fixes
- DoT Colors: changing a color could raise a "forbidden object" error (also in 1.0.0). It no longer does.

### Other changes
- DoT tracker: the list of other mobs now stays where you put it when your target or focus row hides, instead of moving up.
- DoT tracker: a new DoT color or panel opacity reaches the DoT bars at once out of combat; changed in combat, the bars follow when combat ends.

## 1.0.0

The first full release for WoW: Forever, no longer marked beta: it was play tested on the Forever beta client 1.60.1, build 70450. CurseForge now offers it as a release, so the app updates it and installs what it needs for every player.

- The CurseForge app installs Dyre's Toolkit and Dyre's Sounds with WTF. Weapon Skills Forever is listed as optional.

## 0.3.4-beta

- With **Dyre's Toolkit** installed, WTF joins one layout mode for all of Dyre's AddOns: `/wtf unlock`, `/dyre unlock`, or the toolkit's minimap button unlock every Dyre's AddOn's frames at once, WTF's frames (the shield ring too) snap to theirs, and the toolkit's grid (with Snap to the grid) shows.
- With Dyre's Toolkit, WTF's settings move under **Options > AddOns > Dyre's AddOns > Warlock Tools Forever**, and the game's AddOn list shows WTF in the Dyre's AddOns group. The CurseForge app installs Dyre's Toolkit with WTF.
- With Dyre's Toolkit, WTF's settings have no unlock or grid switch of their own: use **Unlock frames** on the Dyre's AddOns page, the minimap button, or `/wtf unlock`.
- Without Dyre's Toolkit, WTF works as before and says once in chat to install it from CurseForge.
- Soul Shards: with a full soul bag, extra shards from Drain Soul could stay in your bags: shard deletion stopped after one failed try, and when one kill created two shards, one could be missed. WTF now remembers how many shards you keep (the ones you had and the ones you moved in, but created ones only up to your limit) and deletes every new shard above it, one per key press or click, also one it missed before. A try that picks up nothing, or one the game refuses just after combat, waits for your next key press.
- Soul Shards: moving a shard to another bag slot while Drain Soul channels no longer counts as a new shard, so it is never deleted.
- Control bar: no more "Warlock Tools Forever has been blocked from an action only available to the Blizzard UI", and no more blocked-action errors for SetRaidTarget. The game does not let AddOns set raid markers, so WTF no longer marks a mob itself.
- WTF's macros and clicks use `/use` instead of `/cast` (shorter; it casts spells the same way), and every focus condition checks that you have a focus.
- The "! Fear" macro now Fears your focus first when you have one, then the mob under your mouse, then your target. Hold Shift as you press it to make the mob under your mouse (or your target) your focus first; a plain press keeps your focus.
- The "! Banish" macro and clicking a Banish row now mark the mob with the game's `/tm`, in and out of combat: your Banish marker (the moon by default; None leaves it out). Pressing it again never takes the marker off. Banish from its plain spell button gets no marker. The group message names the marker after a row click only.
- Control bar: when a Banished mob dies in combat, its row now stays on screen, dimmed, until combat ends, so its click area is never invisible.
- DoT tracker: while frames are locked, clicks pass through the tracker rows to the world; the spell slots on your target and focus rows still recast.
- Soul Shards: no more "Warlock Tools Forever tried to call the protected function" errors from shard deletion. The game refuses AddOn item deletion in combat and during boss fights and other restricted content, so WTF waits and deletes the extra shards on your first key press or click after.
- Healthstone trading: while the game restricts AddOns (combat, boss fights, and other restricted content), WTF no longer tries to move the stone, so no blocked-action errors; it puts the stone in at your next key press, or tells you to drag it in.
- DoT tracker: no more "aura slot 'siphon' was not found" errors when you learn a new spell rank without knowing Siphon Life (or another tracked spell).
- `/wtf debug_shards` and `/wtf shards` now say why shard deletion stopped, and `/wtf debug_shards` lists each deletion with the shard count before it.

## 0.3.3-beta

- With **Dyre's Buff Reminders** 0.3.0 or later installed, WTF plays no Nightfall sound of its own, so you do not hear it twice. Dyre's Buff Reminders now plays it with its proc sounds and copies your WTF Nightfall switch and sound the first time they run. WTF's Alerts page is greyed out and points you to `/dbr`; your WTF Nightfall settings stay as they are. With an older Dyre's Buff Reminders, WTF plays the Nightfall sound as before.

## 0.3.2-beta

- With **Dyre's Buff Reminders** 0.2.0 or later installed, WTF plays no cooldown chimes of its own, so you do not hear each chime twice. Dyre's Buff Reminders now plays them and copies your WTF chime choices the first time its chimes run. WTF's chime settings are greyed out and point you to `/dbr`; your WTF chime settings stay as they are. The Nightfall sound stays in WTF.

## 0.3.1-beta

- The Shield and Cooldown Chimes settings pages say when one of Dyre's AddOns runs that feature: the name in the settings list names it, and a heading at the top says so.
- With **Dyre's Shields Up** installed, WTF leaves the shield display to it: WTF draws no ring of its own, and its shield settings are greyed out and point you to `/dsu`. Your WTF shield settings stay as they are.

## 0.3.0-beta

- With **Dyre's Buff Reminders** installed, WTF hides its own Demon Armor reminder, so you never see two icons. Your setting in WTF stays as it is.
- Sounds now come from Dyre's Sounds, a small AddOn that holds the sounds for all of Dyre's AddOns, so your computer keeps one copy of them. The CurseForge app installs it with WTF; otherwise get it from CurseForge or github.com/jbedworth/DyresSounds.
- Without Dyre's Sounds, WTF plays no sounds (cooldown chimes, the Nightfall sound, and the sound when a shield ends) and says once in chat what to install. Everything else works as before.
- The sounds you chose are kept, also while Dyre's Sounds is missing.
- With Dyre's Cooldown Chimes installed, WTF plays no cooldown chimes of its own, so you do not hear each chime twice. Dyre's Cooldown Chimes takes over your WTF chime choices the first time it runs. The Nightfall sound stays in WTF.
- The shield display's sound menu now has the same groups as the other sound menus.

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
