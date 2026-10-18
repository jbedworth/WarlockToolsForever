# Agent Guidelines

## Project purpose and scope

Warlock Tools Forever (WTF) is a World of Warcraft: Forever AddOn: a suite of
small, independent quality-of-life modules for Warlocks. Each module has an
enable switch on the main settings page and its own settings subpage. Add a
module only after the author agrees its behavior.

### Soul Shards (built)

- Shard counter (author-approved, inspired by Pentacle): an unnamed plain
  frame (not secure, so it updates and moves in combat) with the Soul Shard
  icon and the carried count, outlined: green at or above the limit, red at
  or below the Low shard warning setting (0-10, default 2, author's choice),
  white between.
  Updates on `BAG_UPDATE_DELAYED` and limit changes; on by default, with a
  show switch; it moves with the one lock below; its place is saved per
  character and reset by `/wtf reset`.
- Deletes Soul Shards (item 6265) that a shard source creates above the carried
  limit, with no prompt or popup. The client allows `DeleteCursorItem` only
  during a hardware event (verified: from event handlers it raised
  `ADDON_ACTION_BLOCKED` in and out of combat). Deletions are queued from bag
  events and run from input hooks, as RestedXP's junk deletion does: a
  keyboard frame with `SetPropagateKeyboardInput(true)`, enabled only after
  `GetPropagateKeyboardInput()` confirms it so keys are never swallowed, and
  `WorldFrame:HookScript("OnMouseDown")`. Never attempt deletion from events.
- Shard sources are matched by spell name so every rank counts, each with its
  own creation window: Drain Soul (3 s after the channel ends) and Forever's
  Shadowburn talent (9 s: a shard if the target dies within 8 s of the hit).
  Add others when `/wtf debug_shards` gain logs show them.
- A shard is "created" when it arrives during a source channel or within
  `CREATION_WINDOW` (3 s) after the source spell ends. Shards that arrive
  otherwise (bank, mail, trade) are never deleted, even above the limit
  (author-approved). Delete at most as many shards as were just created, from
  the slots that just gained them.
- The limit: total slots of equipped soul bags (bag family bit 4), in any
  carried bag slot including the reagent slot (verified: a 14-slot soul bag
  sat in bag 5), or 6 without one; or a manual limit (1-60). Turning the match
  off keeps the current limit.
- Carried bags only: the backpack to `NUM_TOTAL_EQUIPPED_BAG_SLOTS` (falling
  back to `NUM_BAG_SLOTS`), which includes the reagent bag; never the bank. On
  Forever, Soul Shards are reagents: they go to the reagent bag until it is
  full, then to other bags.
- Deletion steps: wait for an empty cursor and an unlocked item; pick up exactly
  one shard (split stacks); confirm the cursor holds a Soul Shard; then
  `DeleteCursorItem`. If anything is unexpected, put the item back. If the
  client refuses (cursor still full, or `ADDON_ACTION_BLOCKED`/`FORBIDDEN` for
  WTF during the delete), put the shard back. A refusal in combat holds the
  queue until input after combat, silently; one out of combat reports once
  and stops deleting until `/reload`. Queued deletions wait for input with no
  timeout and are dropped once the count is within the limit.

### Stones (built)

- A movable bar (`WarlockToolsForeverStones`, gold border, brown background)
  with two `SecureActionButtonTemplate` buttons, `WarlockToolsForeverSoulstone`
  and `WarlockToolsForeverHealthstone`. Left-click uses the best stone carried (Soulstone:
  `/use [@target,help,nodead][@player] item:ID`; Healthstone: `/use item:ID`).
  Right-click casts the highest known create rank; for a Healthstone with a
  friendly player target other than you, the highest known rank whose item
  level requirement (`C_Item.GetItemInfo` minLevel) the target meets.
- Ranks are a table of Classic spell and item IDs, confirmed for Forever by
  Consumable Connoisseur's in-client data (Forever removed Improved
  Healthstone and its stone copies); `/wtf debug_stones` shows them in client.
- On Forever, `/click` macros do not press AddOn buttons at all (verified in
  client), and AddOn code cannot use items. So never document `/click`.
  WTF's secure buttons still set `useOnKeyDown` to false (act on release).
- Stone macros (author-approved, as Consumable Connoisseur does): WTF keeps
  "! Healthstone" and "! Soulstone" in the character macro tab
  (`CreateMacro(..., true)`, question-mark icon 134400 so `#showtooltip` shows
  the stone), rewritten out of combat only when the body changes:
  `/cast [btn:2] <create>` and `/stopmacro [btn:2]`, then the `/use` lines.
  Healthstone: the downranked create rank by exact name
  (`Create Healthstone(Rank N)` from `C_Spell.GetSpellSubtext`; Forever's
  stones are one spell with numeric ranks) and `/use item:` for every rank,
  best first. Soulstone: bare `Create Soulstone` (best rank) and
  `/use [@target,help,nodead][@player] item:` for the best carried. Creation
  leaves the last 2 character slots free and says so once. The slot limit comes
  from `Constants.MacroConsts.MAX_CHARACTER_MACROS`: the `MAX_CHARACTER_MACROS`
  global exists only after Blizzard's Macro window loads, and requiring it
  silently turned the macros off in client. Missing macro APIs are reported
  once. "Keep stone macros"
  (default on) turned off deletes them.
- Spellstone and Firestone buttons and reminders are agreed future scope.
  Until built, the Stones page shows four greyed-out "(Coming soon)"
  switches (author-approved) that are never on and save nothing.
- Healthstone middle-click (author-approved): `type3` item action for the best
  Healthstone carried, whatever the target.
- Healthstones are unique per rank, so the create rank skips ranks already
  carried for the next lower one (author-approved, as Connoisseur does), still
  within a friendly target's level. Soulstones are not downranked: every rank
  shares one cooldown.
- Secure attributes and the bar's visibility change only out of combat;
  changes in combat wait for `PLAYER_REGEN_ENABLED`. The bar drags out of
  combat unless locked; `/wtf reset` restores its place.
- PostClick explains a click that did nothing (no stone, no rank, a Soulstone
  in combat) with one line, deduplicated across press and release.
- Healthstone trading (author-approved): with a friendly player targeted,
  left-click trades the best Healthstone that player can use (no secure
  action; PostClick calls `InitiateTrade("target")` on release), or casts the
  best rank they can use when you carry none. On `TRADE_SHOW` within 10 s,
  WTF picks up the stone and calls `ClickTradeButton` on a free slot; if the
  client refuses, it puts the stone back and tries once more at the next key
  press or click. WTF never accepts a trade.
- Stone status (author-approved): your Soulstone Resurrection cast (by name of
  spell 20707) is saved per character with its target and end time (30 min,
  Classic's duration), announced in chat when it ends. Reminders when no
  Soulstone is up (and you know a rank) or you carry no Healthstone (and know
  a rank): on `PLAYER_ENTERING_WORLD` in an instance, `GROUP_JOINED`, and
  `PLAYER_REGEN_ENABLED`, at most once per 10 minutes each; each has a switch.

### Announce (built)

- Ritual of Summoning (by name of spell 698) is announced when it starts
  (`UNIT_SPELLCAST_START` or `UNIT_SPELLCAST_CHANNEL_START`, success as a
  fallback), once per ritual (author-approved). In client nothing went out
  when WTF waited for a named target at success; the target is the name from
  `UNIT_SPELLCAST_SENT`, else your friendly player target. Soulstone
  Resurrection (by name of spell 20707, any rank) is announced on
  `UNIT_SPELLCAST_SUCCEEDED` for a cast whose `UNIT_SPELLCAST_SENT` named
  another player. Self, failed or interrupted Soulstone, and secret-target
  casts announce nothing.
- Five messages with their own switches and texts (`%T` the target's full
  "First Last" name, whispers to "First-Last"; `%Z` zone):
  summon group line ("The ritual hungers! Click the portal to drag >> %T <<
  through the Twisting Nether"), summon whisper (only
  verified advice; the accept-blocking rules are unverified), Soulstone group
  line, Soulstone whisper (the author's text), and Healthstone gift whisper.
  Every default text credits WTF: " - via Warlock Tools Forever (WTF)", or
  the author's own credited lines for the summon whisper (a light jab at the
  target's sloth-like pace, then: accept the summon, tell me if it doesn't
  appear), the Soulstone whisper ("I've trapped a
  sliver of your soul in a stone. ... die in a good spot. Courtesy of
  Warlock Tools Forever (WTF)") and the gift whisper ("Here, have a Healthstone. Some poor
  creature's essence gives you more health! Courtesy of Warlock Tools
  Forever (WTF)" (author-approved, defaults only: edited texts say only what the player
  wrote). Saved texts equal to the earlier, uncredited defaults are upgraded
  to the new defaults at login. Group means raid, else
  party, else nothing; Say is optional. SAY outdoors needs a hardware event and
  the success event is not one, so a blocked Say is reported once.
- The Healthstone gift whisper goes when the trade window opens
  (`TRADE_SHOW` within 10 s of the button's trade), to the friendly target
  named at the click, once, before WTF places the stone (author's choice:
  not on completion, which in client sent nothing).
- Stone creation emotes (author-approved): `UNIT_SPELLCAST_SUCCEEDED` of
  Create Healthstone or Create Soulstone (by name, any rank) queues an
  EMOTE, at most once per stone type every 60 s. In client an emote sent from
  the success event was blocked (ADDON_ACTION_BLOCKED), so it waits for the
  next key press or world click (`WTF.RunOnNextInput`), as shard deletion
  does, and is dropped after 30 s without one. A blocked chat type is
  reported once. No Spellstone or Firestone emotes until those exist.
- Texts are trimmed, single-line, at most 255 bytes, else the default. The
  Announce settings subpage is a canvas page with edit boxes.
- If Forever adds meeting stones, announce that one is up (agreed, not built).

- Agreed next (not yet built): Spellstone and Firestone buttons, once the
  author's characters reach the levels that teach them; Forever has both.

### DoT tracker (built)

- Layout (author-approved): a pinned **target** row (warlock-purple class
  color outline) on top, a pinned **focus** row (the same outline in red) below
  it, each shown only while that unit is a live hostile; then a list of up to
  8 other mobs you DoTed. The list leaves out your target and focus, so no mob
  shows twice, and it moves up when a pinned row hides. Tabbing or a new focus
  changes what the pinned rows show.
- Each row has slots, in this order (author-approved): Curse (Weakness,
  Recklessness, Elements, Shadow, Tongues, Exhaustion; one at a time), Bane
  (Agony, Doom, Havoc), Corruption, Immolate, Siphon Life, and Fear and
  control (Fear, Howl of Terror, Death Coil, Banish), from Forever's spell
  list and talents. Nameplate dots and the DoT Colors page use the same order. Single-target channels
  (Drain Life, Drain Soul, Drain Mana, Wrack) are not tracked
  (author-approved). A list row appears when the player's cast of a
  tracked spell succeeds on a hostile mob (cast events, target name, and
  `UnitGUID` are readable in combat) and leaves when the mob dies (`UnitIsDead`
  on its unit), after 10 s with no unit showing it, or when combat ends. A
  ninth mob replaces the oldest list row. Sample rows (author-approved, for
  positioning) show out of combat while frames are unlocked.
- On Forever the combat log is restricted at all times and every aura API
  refuses AddOn code in combat. So each row holds a Blizzard AuraContainer
  (`CreateFrame("AuraContainer", nil, row, "CustomAuraContainerTemplate")`
  after loading `Blizzard_AuraContainer`), as EllesmereUI and ThreatPlates
  do. Each spell is one `AddAuraSlot` with filter `HARMFUL|PLAYER` and
  `candidateFilters.includeSpellIDs` (Classic rank IDs plus every spellbook
  spell of the same name; Banes by name). The Curse slot instead uses
  `includeDispelTypes = {Curse = true}` with the Bane slot's IDs in
  `excludeSpellIDs`: in client a curse's debuff matched neither the Classic
  nor the spellbook IDs, while Corruption, Immolate, and Bane did. The engine reads the row's unit and
  draws the icon, cooldown sweep, countdown, and a draining bar into regions
  WTF creates in `initializeFrame`, the only time WTF may touch the engine's
  button. WTF never reads timers or whether an aura is present. A dimmed,
  desaturated icon behind each slot shows a missing or expired spell. Pinned
  rows are bound to `target` and `focus` for good; list rows to the mob's
  nameplate token, else target or focus, else "none".
- Themes (author-approved), on the DoT Tracker page and saved per character,
  **Bars** by default: **Compact**, a row with the name and an icon per spell
  family the player knows; **Bars**, a block per mob with the name above one
  line per spell family the player knows (an icon,
  then a bar with `SetSpellName` and `SetDurationText`, draining with
  `StatusBarTimerDirection.RemainingTime` like the Cooldown Manager), a dim
  line with the family's name behind each, so missing spells show
  (author-approved over shrinking blocks). Slot regions are placed at fixed
  positions in `initializeFrame`, so a theme change or a newly learned spell
  rebuilds every row, out of combat, keeping tracked mobs.
- "Known" means learned: the spellbook also lists spells learned later
  (`SpellBookItemType.FutureSpell`), which count as unknown for the tracker's
  slots, the pinned recasts, and the nameplate dots.
- Pinned slots are `SecureActionButtonTemplate` buttons over the engine slots:
  `/cast [@target,harm,nodead] <name>` (or `@focus`), by name so the highest
  rank is used. Bane and Curse slots recast the last Bane or Curse cast (saved
  per character). Their attributes change only out of combat. The pinned rows
  live in a secure anchor (`WarlockToolsForeverTracker`) whose rows the game
  shows and hides with `RegisterStateDriver(row, "visibility",
  "[@target,harm,nodead] show; hide")`; the list
  (`WarlockToolsForeverTrackerList`) is an ordinary frame anchored below it.
- List rows only display: a secure button cannot change its unit in combat,
  and the restricted environment has no `UnitGUID` or `UnitName`, so secure
  code cannot tell which nameplate belongs to a row. Nameplate AddOns only
  decorate Blizzard's plates, whose click the engine handles. Never promise
  clicking a list row to target or cast.

### Nameplate DoT dots (built, part of the tracker)

- Author-approved, off by default, and usable only when the player knows at
  least one tracked DoT: in combat, a small bubble above each live hostile
  nameplate with one dot per known DoT chosen for nameplates (by default
  Curse, Bane, Corruption, Immolate, and Siphon Life; not Fear and control). A
  grey dot shows the DoT
  is missing; the colored dot, an engine AuraContainer slot bound to the
  plate's unit, covers it while the DoT is up.
- Bubbles attach on `NAME_PLATE_UNIT_ADDED` through
  `C_NamePlate.GetNamePlateForUnit` (skipping forbidden plates), parented to
  the plate and anchored above it at a configurable height (0-120, default 50, which clears the name and EllesmereUI's debuff icons;
  the slider has a gold mark at the default, author-approved),
  as TankHelper's threat display does. They are pooled and rebuilt when the
  known DoTs change.

### Alerts (built)

- Nightfall sound (author-approved, off by default; picked from nested menus
  like the chimes', grouped Dyre's Picks, Imp, and Hellish imp by the labels'
  "Group: Name"): `C_UnitAuras.AddAuraSound`
  on the player's Shadow Trance (spell 17941) with the chosen sound, as BigWigs
  registers its aura sounds: imp laughs and chirps by file ID (`soundFileID`;
  default the Imp spell chirp, the author's pick), found in Leatrix Sounds'
  file list for this client, or Dyre's Picks, WTF's own files in Sounds/ by
  path (`soundFileName`). The interface sounds by game path are gone: the
  client plays no game sound by path (found in client). The game plays it, also in combat. Registration waits out an
  Encounter restriction (`ADDON_RESTRICTION_STATE_CHANGED`). Choosing a sound
  previews it with `PlaySoundFile`. `UnitAuraSoundInfo` (pinned
  UnitConstantsDocumentation) takes only `soundFileName` or `soundFileID`,
  not sound kits, so the Cooldown Manager's catalog cannot be Nightfall sounds.

### Cooldown chimes (built, ported from MTF)

- A sound just before a chosen spell's cooldown ends, also in combat, timed
  from your own cast (the combat log is closed and cooldowns are secret in
  combat): the length last read out of combat (saved per character, 1.5 s to
  1 h), else Classic's, minus the lead (0-3 s, default 0.5). Spells, on by
  default: Death Coil, Howl of Terror, Shadow Ward, Soulstone Resurrection
  (the Soulstone's use), Fel Domination; off: Shadowburn, Conflagrate,
  Amplify Curse, Bane of Doom (Classic's Curse of Doom, 603), Inferno.
- Each spell's sound comes from MTF's catalog (Interface SOUNDKIT names, the
  Cooldown Manager's 93 alert kits by ID, the nine Dyre's Picks sounds (first in the menu) shipped in
  Sounds/ with the shield display and played with `PlaySoundFile`
  (author-approved), and Text to Speech), in the same
  nested menu: Options.lua wraps the pooled settings dropdown control's
  `SetupDropdownMenu` only for an initializer carrying `wtfSoundMenu` and
  hands every other dropdown on (MTF wraps the same pooled controls with its
  own flag, so both chain). Default Interface: Talent ready.

### Shield display (built, MTF's shared component)

- Shield.lua is MTF's component, copied byte for byte with its textures and
  scripts/build_arc.py (tests require the committed TGAs to match the build).
  It already knows Shadow Ward and the Voidwalker's Sacrifice, and shields
  others cast, like Power Word: Shield. With MTF and WTF both installed, one
  display shows, from the newest copy (`ShieldForeverRegistry`); keep the
  copies identical and bump its VERSION in both when it changes. WTF hands it
  `WTF.db.shield`, its report function, and the unlock hint; a main-page
  switch and a Shield page (absorb number, break sound, size) as in MTF. It
  drags itself and does not snap.
- Version 3 (author-approved): copies take part only once their AddOn
  initializes them, so login order never decides; each class's own shields
  get a spot each, then the shared ones; bubbles (Divine Shield, Divine
  Protection: Paladin; Blessing of Protection: anyone) are timed, drawing a
  gold innermost crescent that drains with their time left (Classic IDs;
  check on Forever; Power Word: Shield's Classic IDs are confirmed there).
  In combat the display stays shown, since buffs others cast cannot be read:
  the outer crescent is invisible with no absorb, and the engine shows each
  icon and timed crescent only while its buff is up.
- Version 4: each crescent texture spans its own height (scripts/build_arc.py
  stretches it; Shield.lua's `*_SPAN` constants match, checked by a Python
  test), and every crescent texture and bar is drawn at that height. A
  StatusBar fills its whole height, so across the full square a timed bar
  emptied a segment or more before its buff ended (found in client; the
  fix confirmed on a Mage).
- Version 5 (with MTF and WTF; found in client): absorbs
  under the larger of 25 points and 5% of max health (25 when max health is
  secret) never show; a Paladin's Seal of Righteousness proc, 10-20 points,
  flickered the ring. The absorb cannot be compared, so a hidden gate
  StatusBar, one point wide and ending at the minimum, takes it as its value,
  and a clipping frame anchored to the gate's fill holds the crescent and the
  number (confirmed on a Paladin). Fixed constants, no setting.
- Version 6 (with MTF and WTF; found in client): the break sound is one of
  the AddOn's own files in Sounds/, byte-identical in all three, chosen in a
  dropdown under the sound switch (author-approved: a default you can change,
  Fading slow disappear). The client plays no game sound by path
  (RaidWarning.ogg stayed silent), while an AddOn's file plays, also through
  `C_UnitAuras.AddAuraSound` when a buff runs out. Turning the sound on, or
  choosing one, plays it once. The sounds are licensed to Vertiso Corporation
  from Envato (Elements and AudioJungle; the author keeps the license files,
  not in Git); they are not under the MIT License.

### Demon Armor reminder (built)

- Author-approved: only Demon Armor (Demon Skin counts too; the other buffs
  are situational). One secure icon, shown out of combat while neither is on
  you, with a pulsing gold border; a click casts the armor last cast (saved
  per character), else Demon Armor, else Demon Skin. It sits in a holder
  hidden for combat by `RegisterStateDriver(holder, "visibility",
  "[combat] hide; show")`, reads buffs only out of combat, snaps, and resizes
  with the mouse wheel while unlocked (50-200%, keeping its center).

### Control bar and control announcements (built)

- After MTF's Polymorph bar, for many mobs (author-approved): up to five
  rows, one per mob you Fear or Banish, each an AuraContainer slot
  (`HARMFUL|PLAYER`, Fear and Banish IDs plus spellbook IDs of those names)
  with the mob's name above a bar line. Rows come from your cast events (SENT
  names the target, matched to a unit for its GUID) and bind to the mob
  through your focus, then target, then its nameplate (never mouseover; a
  cast through mouseover, as "! Fear" does, still counts and marks); a
  recast on the same mob keeps its row. A row goes when the mob dies, after the longest such spell plus 5 s
  (Fear 20, Banish 30), or never when the cast fails.
- A raid marker per spell when the cast succeeds (Control page; Banish
  moon by default; author-approved: single-target control only, one marker
  slot in a group, so Fear never marks and has no marker setting). %M puts
  its chat code in the message ("{moon}"). An earlier default diamond moves
  to the moon once (`markersVersion`). SetRaidTarget toggles: a unit that already has the marker loses it (the
  pinned /tm source; its "!" prefix skips an equal marker). GetRaidTargetIndex
  is secret to AddOn code in combat, so the mark is skipped when the index is
  readable and equal, or, unreadable, when this AddOn marked that mob (by GUID)
  already. The mark goes on your target or focus when it is the mob, as
  TankHelper marks `TARGET`. A player's own `/tm` macro would clash in combat
  (the AddOn cannot see that mark), so the README says to turn the AddOn's
  marking off when using one.
- Click to recast, Banish only (author-approved: single-target control
  follows the focus): each row has a fixed secure click slot under it
  (`WarlockToolsForeverControlClick1`..5) with `/cast [@focus,harm,nodead]
  Banish`, `/stopmacro [@focus,exists]`, then by name: `/cleartarget`,
  `/targetexact <mob>`, `/cast [@target,harm,nodead] Banish`,
  `/targetlasttarget`; set only out of combat: at cast start for a pull, else
  when combat ends. A slot shows only while it has a click (or while
  unlocked, to drag by). Fear rows have no click (author-approved): a secure
  macro can aim only at a unit token or a name, never at a GUID (the
  restricted environment has no UnitGUID), tokens move in combat, and juggled
  mobs share names. Rows find their mob through focus, target, then its
  nameplate; a death counts through any unit showing it (by GUID).
- Fear timers on nameplates (author-approved, `control.plateTimers`, on by
  default): a thin bar under each nameplate, an AuraContainer slot (Fear IDs,
  `HARMFUL|PLAYER`) bound to the plate's unit on `NAME_PLATE_UNIT_ADDED` and
  released on `NAME_PLATE_UNIT_REMOVED` (plates are pooled; a mob back in
  range may get another plate and token, and the engine shows its real time
  left). Clicking the plate targets the mob.
- Macros (author-approved, after the author's own, `control.macros`):
  "! Fear" once you know Fear, the author's juggling macro: `/cast
  [@mouseover,harm,nodead][harm,nodead] Fear` (no focus: a focus holds one
  mob; hover a feared mob's nameplate as its timer ends); "! Banish" once you know Banish and "! Seduction" once your summoned demon
  knows Seduction (a Grimoire teaches it; the pet spellbook, by ID or by name,
  so a Succubus or an Incubus counts; checked on `UNIT_PET` and
  `SPELLS_CHANGED`; the macro stays when the demon is dismissed; per the
  author, a learned Grimoire teaches both the Succubus and the Incubus): `#showtooltip`, `/focus [@mouseover,harm,nodead]
  [nocombat,harm,nodead]`, `/cast [@focus,harm,nodead] <spell>` (Seduction
  with `pet:Succubus/Incubus`, so it does nothing without one). They do not
  `/tm`: WTF marks on landing, and a second mark would toggle it off (the
  pinned /tm source: SetRaidTarget toggles; "!" skips an equal marker).
  Written with Stones' macro writer, out of combat; off deletes them.
- Group messages as the cast starts (Announce page, `WTF.SendGroupAnnouncement`,
  the Announce channel, nothing alone, at most every 3 s per spell): Fear,
  Banish, Enslave Demon, and Howl of Terror (no target).

### Magnetic frames (built)

- Layout.lua (author-approved, MTF's snapping improved): every movable WTF
  frame registers a save function; while unlocked, a frame dropped within 24
  units of a spot beside another shown frame snaps there, 20 apart, lined up
  by tops, centers, or bottoms (lefts, centers, or rights when stacked),
  whichever is nearest. Frames that far apart and overlapping are snapped;
  Shift-drag moves the group (others anchored to the dragged frame for the
  drag), which snaps as one. Positions save as centers from UIParent's
  bottom left. Only out of combat; a drop after combat began waits, and the
  group snaps and saves on `PLAYER_REGEN_ENABLED`.

### Warnings

- `WTF.Warn`: a failed click or stopped automation is said in chat and in red
  through `UIErrorsFrame` (stone clicks, trade placement, macro slots, shard
  deletion stopping). `/wtf reset` in combat reports once.

### Slot colors (author-approved)

- One color per slot (`WTF.DOT_SLOTS` in Core: Curse purple, Bane red,
  Corruption white, Immolate orange, Siphon Life green, Fear and control
  yellow; author-approved),
  shared by the tracker's bars and the nameplate dots so the colors become a
  quick visual code. Saved per character as `AARRGGBB` hex strings, the
  format of the Settings color swatch, and editable on the DoT Colors page
  with a nameplate switch per slot. The bars and dots are WTF's own regions,
  so new colors apply at once, also in combat. When defaults change, a
  one-time step (`colorsVersion`) moves slots still on an old default to the
  new one and keeps colors the user picked.

Keep each module narrow. Do not add automation that plays for the user,
general frameworks, or speculative modules without agreement.

### Lock and unlock (built)

- One lock for every WTF frame (author-approved, as MTF): `db.locked`,
  default locked, copied to `stones.locked`, `tracker.locked`, and
  `shards.counterLocked`; `tracker.placeholders` follows it (sample rows
  while unlocked, since the tracker drags only while it shows). The main
  page's "Unlock frames to move them" and `/wtf unlock` and `/wtf lock` set
  it (dragging reads `db.locked`, Layout.lua); there are no per-frame lock or
  placeholder switches. The Stones bar and
  the shard counter show a gold outline and a "Drag to move · /wtf lock when
  done" hint while unlocked (`WTF.CreateMover`). Every new movable frame joins
  this lock.
- While unlocked, an alignment grid (author-approved, as MTF's; main-page
  switch "Show a grid while unlocked", on by default, `db.grid`): a
  mouse-transparent BACKGROUND-strata frame over UIParent with faint white
  lines every 32 units from the center out and the two center lines in red,
  2 thick. Built on first unlock and rebuilt on `DISPLAY_SIZE_CHANGED` and
  `UI_SCALE_CHANGED`.

## Project structure

- Runtime files: WarlockToolsForever.toc, Commands.lua, Core.lua, Layout.lua, Shards.lua, Stones.lua, Announce.lua, Tracker.lua, Dots.lua, Control.lua, Alerts.lua, Shield.lua, Chimes.lua, Reminders.lua, Probe.lua, Options.lua, loaded in
  that order, plus Textures/ShieldArc.tga, Textures/ShieldArcInner.tga, and
  Textures/ShieldArcInnermost.tga. Core also owns the hardware-input hooks
  (every key press and world click) that item deletion and trade placement
  wait for.
  Commands parses `/wtf`; Core owns saved settings and their defaults, the
  login banner, class and install checks, slash conflict reporting, and
  startup; Layout owns snapping; Shards, Stones, Announce, Tracker, Dots, Control, Alerts, Shield,
  Chimes, and Reminders own their modules; Probe owns
  `/wtf debug_restrictions`; Options owns the settings pages.
- tests/run.lua holds the Lua 5.1 mock suite. tests/test_*.py cover the release
  helpers in scripts/. .github/workflows/ holds CI, opt-in publishing, and the
  approval gate check.
- README.md is the user-facing overview, TESTING.md the verification method,
  source evidence, and in-client checklist, docs/RELEASE_PLAN.md the release
  process, docs/CURSEFORGE_LISTING.md the CurseForge form text, and CHANGELOG.md
  the per-release change list. artwork/ holds the original logo (SVG source and
  PNG renders) for project pages; it never enters the runtime package.
- Documentation describes purpose, design, rules, and methodology. Do not add
  dated status reports or test-result logs to the docs; CHANGELOG.md is the
  release record.
- The project uses the MIT License. The public author name is `Dyre` (TOC
  `## Author`, login banner, listings); LICENSE keeps the legal name, John
  Bedworth, and the release builder requires that exact notice.
- The TOC uses `## Category: Warlock`; keep it identical to the CurseForge main
  category, because the in-game AddOn list groups by exact text.
- WTF ships no texture files. Use built-in client textures only; add no runtime
  assets without agreement.
- Git origin: git@github.com:jbedworth/WarlockToolsForever.git. Inspect Git
  state before acting and preserve user work. Text is LF under .gitattributes.

## Client and API verification

- Target: Forever beta 1.60.1, build 70338, Interface 16001, Lua 5.1. Pin source
  review to Gethe/wow-ui-source commit
  `943764493e6b16d63ded3ab304150d1f05e58b57`. Treat target-client documentation
  and FrameXML as authoritative; Retail and Classic examples are references only.
- Do not gate the runtime on client version, build, or Interface. Gate only on
  required APIs and the Warlock class.
- The target client has Midnight's secret values and AddOn restrictions
  (`C_RestrictedActions`, restricted `COMBAT_LOG_EVENT_UNFILTERED`, and
  `SecretWhen...` flags on unit, aura, and spellcast APIs). Never compare,
  concatenate, index, or print a value that may be secret: check `WTF.IsSecret`
  first and print with `WTF.Describe`. Treat a secret value as unknown and fail
  safe (Shards: no creation window).
- Never register `COMBAT_LOG_EVENT_UNFILTERED`: the client refuses it and
  raises `ADDON_ACTION_BLOCKED` for WTF. Blocked-action events name WTF for any
  blocked call, so react to them only around the call that caused them.
- `DeleteCursorItem`, `GetCursorInfo`, and `ClearCursor` are legacy globals not
  in the generated API documentation; whether deletion works in combat must be
  verified in client.
- WoW APIs can return no values rather than nil; store results in locals before
  passing them to `tostring`, and make mocks return no values in those cases.
  The client may not show Lua error popups, so diagnostics report errors in chat.
- Prefer `/wtf debug_*` commands over long `/run` scripts, which exceed the
  chat input limit. Diagnostics may run while WTF is unavailable, read only,
  and may wrap their own body in one `pcall` that prints the failure in chat.

## Clean coding

- Lua 5.1 syntax and libraries only; no `bit` library (use arithmetic). Four-space
  indentation. Prefer local variables and functions; share state through the
  AddOn namespace. Expose globals only when WoW requires them (slash commands,
  saved variables, the Stones bar and buttons, and the tracker
  anchor, list, and pinned cast buttons), prefixed
  `WarlockToolsForever` or `WTF`.
- Centralize meaningful constants; avoid unexplained magic numbers.
- Comment sparingly: non-obvious intent, API constraints, or tradeoffs.
- Event-driven work only; no polling or idle `OnUpdate` handlers.

## Safety and error reporting

- Validate commands and inputs before changing settings or items. Treat bad
  commands, missing APIs, other classes, and blocked actions as expected
  failures with concise feedback prefixed `WTF:`.
- Never prompt or open popups in combat. Never swallow errors with blanket
  `pcall` handlers or replace the error handler.
- On an unsupported client, another class, or a mixed install, disable the
  AddOn and report the reason once at login.
- Repair saved settings on load so a damaged or older table cannot break WTF.
- Startup is driven by Core at `PLAYER_LOGIN` calling each module's
  initializer; never rely on event handler order between files.
- Item deletion is irreversible: delete only what the rules above allow, verify
  the cursor before deleting, and stop at the first unexpected result.

## Testing and documentation

- Run `.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua`
  and the bundled `luac5.1.exe -p` for syntax. Run
  `.tools/python-3.13.7/python.exe -m unittest discover -s tests -p 'test_*.py'`
  and actionlint on workflow changes. Report actual results; never invent them.
- Add focused tests alongside behavior changes. Mocks model secret values as
  values that raise errors on comparison, concatenation, indexing, or printing.
  Mocks cannot prove protected-action rules, secret-value behavior, layout, or
  taint; those need the in-client checks in TESTING.md.
- Keep README usage and compatibility claims aligned with the implementation.

## Releases and collaboration

- Read docs/RELEASE_PLAN.md before packaging or changing release automation.
- Do not create commits, tags, uploads, or releases unless asked.
- Every release needs a `## <version>` section in CHANGELOG.md with player-facing
  changes; the builder puts it at the top of release-notes.md (GitHub release
  notes and CurseForge changelog) and fails without it.
- Package only WarlockToolsForever.toc, Commands.lua, Core.lua, Layout.lua, Shards.lua, Stones.lua, Announce.lua, Tracker.lua, Dots.lua, Control.lua, Alerts.lua, Shield.lua, Chimes.lua, Reminders.lua, Probe.lua, Options.lua, LICENSE,
  Textures/ShieldArc.tga, Textures/ShieldArcInner.tga, Textures/ShieldArcInnermost.tga, and the break sounds in Sounds/
  under the top-level
  `WarlockToolsForever/` folder, named
  `WarlockToolsForever-<version>-forever.zip`, with the builder's
  BigWigs-format `release.json` (flavor `forever`) attached for WowUp.
- Publishing requires repository variables `ENABLE_GITHUB_RELEASES='true'` and,
  for CurseForge, `ENABLE_CURSEFORGE_UPLOADS='true'`, plus
  `CURSEFORGE_PROJECT_ID`, `CURSEFORGE_GAME_VERSION_ID`, and the `release`
  environment secret `CF_API_TOKEN`. Both publish jobs use the author-created
  environment `release` with a required reviewer; the workflow's environment
  name must match it exactly. Verify the gate with `gate-check.yml` before
  enabling publishing. Store tokens only in GitHub secrets.
- Action pins are full commit SHAs; review any pin change against the GitHub API.
- Commit messages, when requested: imperative, capitalized subject, at most
  about 50 characters, no ending punctuation; short wrapped body when useful.
