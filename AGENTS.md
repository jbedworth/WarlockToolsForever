# Agent Guidelines

## Project purpose and scope

Warlock Tools Forever (WTF) is a World of Warcraft: Forever AddOn: a suite of
small, independent quality-of-life modules for Warlocks. Each module has an
enable switch on the main settings page and its own settings subpage. Add a
module only after the author agrees its behavior.

### Aura slots on Forever and Classic (built 1.3.2; John: "how can we get those up and working on pre-forever?")

- Since 1.4.1 (John: "Just have WTF use the shared Toolkit files and fix the
  overlap") the aura slots, the plate memory and unit lookups, focusWorks,
  and the DoT prediction's frame adapters and drawing are Dyre's Toolkit
  2.4.0's (Auras.lua, Units.lua, HealthBars.lua), moved from WTF unchanged;
  this file's rules for them are their spec, kept in the Toolkit's tests.
  Core's `UseShared` checks each function it needs (`SHARED_FUNCTIONS`) on
  `RequireContract(1)`'s table and puts them under WTF's old names
  (`WTF.CreateAuraContainer`, `WTF.LearnPlate`, ...). The TOC keeps the
  Toolkit optional (family rule; CurseForge requires it): without those
  functions the DoT tracker, the nameplate dots, the Control bar, and the
  prediction stay off, with one line at login; Shards, Stones, and Announce
  work. Tracker and Control call `FindUnit` and `LockCast` with their own
  orders (Tracker: plates, memory, target, focus, and target, focus,
  mouseover, plates with `stopAtName` and `allowDead`; Control: the default,
  and focus, mouseover, target, plates with `memory` and `secretHostile`);
  Control's `control.lastLook` is LockCast's `look`. Tracker keeps its own
  ReadName (a secret or missing name is ""). Every fixture loads the three
  files: from ../DyresToolkit when it is there, else from tests/toolkit (see
  Project structure).
- The DoT tracker, the nameplate dots, the Control bar, the Focus box, and
  the Fear plate timers get their aura slots from `WTF.CreateAuraContainer`
  (the Toolkit's Auras.lua, once WTF's AuraEngine.lua). On Forever it is Blizzard's engine
  (`CustomAuraContainerTemplate`, Blizzard_AuraContainer), unchanged. Where
  the template is missing (Classic Era, Anniversary), it is a plain-Lua
  container with the same methods (`AddAuraSlot` with `candidateFilters` and
  `initializeFrame`, `SetUnit`, `UpdateAllAuras`,
  `SetAuraSlotCandidateFilters`): the same rows, colors, sizes, and places.
  It reads your auras on the bound unit with
  `C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL|PLAYER")` (readable in
  combat there, nothing secret), matches each slot's filters (spell IDs, or a
  dispel type minus excluded IDs), and fills the regions the initializer
  handed it: icon, cooldown sweep, a StatusBar draining from the aura's
  `duration` and `expirationTime`, the spell name, and "N s" / "N m". One
  frame follows `UNIT_AURA`, target, focus, and plate events for the bound
  units; one OnUpdate (every 0.1 s) redraws only while a timed slot shows,
  and is cleared when none does.
- `WTF.AuraEngineKind()`: "engine", "lua", or nil. The "stays off" lines
  (tracker, Control bar) appear only with neither.
- Not built: a combat log (CLEU) source. Rows bind to unit tokens, as on
  Forever, so a mob with no unit (no plate, not your target or focus) shows
  no timers on Classic either. CLEU could add those timers on Classic only
  (Forever refuses CLEU).
- On Classic the Bane slot holds Curse of Agony and Curse of Doom (by their
  IDs) and the Curse slot your other curses; per-client slots are later work.

### Moved out in 1.3.0 (author-approved, 2026-10-22)

So that WTF stops duplicating Dyre's other AddOns, and players meet them on
their other classes ("virality"):

- The shield display (Shield.lua, its crescent textures, scripts/build_arc.py)
  is Dyre's Shields Up's (DSU). The cooldown chimes (Chimes.lua), the Nightfall
  sound (Alerts.lua), and the Demon Armor reminder (Reminders.lua) are Dyre's
  Buff Reminders' (DBR). WTF ships none of them, and no sounds, so it no
  longer uses Dyre's Sounds. Do not bring any of them back: changes go to DSU
  or DBR through the coordinator.
- TOC: `## OptionalDeps: DyresToolkit, DyresShieldsUp, DyresBuffReminders`
  (never `## Dependencies`, so WTF loads without them; the toolkit stays
  optional while WTF is not on toolkit widgets). CurseForge lists
  `dyres-toolkit`, `dyres-shields-up`, and `dyres-buff-reminders` as required
  dependencies (`RELATIONS` in scripts/publish_curseforge.py), so the app
  installs them.
- At login, on a Warlock with WTF available, Core's `WTF.ReportMovedFeatures`
  says once per session for each of DSU and DBR that is not loaded: "Install
  <title> from CurseForge for <features>: it moved there from WTF.", or
  "Enable <title> in the AddOn list ..." when `C_AddOns.GetAddOnInfo` shows it
  installed but not loadable (reason not "MISSING"). CurseForge only.
- The Shield, Cooldown Chimes, Alerts, and Demon Armor pages are links, not
  mirrors (author): each is one `DyresToolkit.AddSettingsLink` button (toolkit
  2.3.0; greyed while that AddOn has not joined the toolkit, and a click then
  says what to install; never in combat) that opens DSU's or DBR's settings.
  Without the helper, the page is one greyed note saying where the feature
  went. The main page has no shield, chime, or reminder switches.
- WTF's saved `db.shield`, `db.chimes`, `db.alerts`, and `db.reminders` stay
  exactly as saved for one release (no repair, no lock flag), so DSU and DBR
  can copy them once on their first run on the character (DBR already copies
  chimes, Nightfall, and the reminder: `enabled`, `spells.armor`,
  `last.armor`), and a downgrade still finds them; a test checks it. Remove
  them in a later release.
- DBR's Demon Armor icon is a secure button that casts the armor you cast
  last, else Demon Armor, else Demon Skin (`prefer = {706, 687}`), on you, as
  WTF's did; the icon's place and size are not copied (DBR's author rule:
  "start fresh").

### Soul Shards (built)

- Shard counter (author-approved, inspired by Pentacle): an unnamed plain
  frame (not secure, so it updates and moves in combat) with the Soul Shard
  icon and the carried count, outlined: green at or above the limit, red at
  or below the Low shard warning setting (0-10, default 2, author's choice),
  white between.
  Updates on `BAG_UPDATE_DELAYED` and limit changes; on by default, with a
  show switch; it moves with the one lock below; its place is saved per
  character and reset by `/wtf reset`. It keeps UIParent's strata, MEDIUM
  (the Stones bar too): HIGH covered the Settings panel on Classic Era (John:
  "it now renders on top of dialogs"). Its gold outline takes its frame's
  strata (`WTF.CreateMover`). At the old default (CENTER -260,-160) it sat
  under Shadowed Unit Frames' player frame (also MEDIUM) and could not be
  grabbed, so the default place moved instead. Its default
  place is a fraction of UIParent, 55% across and 42% up (John: "near the
  center of the screen, about 50-60% across"), so it holds at any resolution
  and UI scale, clear of the player and target frames of the default UI and
  unit frame AddOns.
  `/wtf debug_shards` reports its setting, shown/visible, point, place,
  scale, alpha, text, icon, strata, level, and region count.
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
  (author-approved). Only a rise in the carried count is a creation: a shard
  that moves to another slot (the player's move, or the client putting one
  back after a refused deletion) is no new shard.
- The keep count (author-approved, after in-client misses: a full soul bag
  and two shards from one kill left one undeleted): the shards WTF must keep.
  It starts as the count at login; a rise outside a creation window (or while
  deletion is off or stopped) raises it to the new count; a rise inside one
  raises it only up to the limit; a drop lowers it to the new count. While the
  carried count is above both the limit and the keep count, each key press or
  click deletes one shard (an unlocked one outside the soul bags first, else
  in them), so a created shard missed at once still goes later, and lowering
  the limit deletes nothing. After a deletion the next waits until a bag scan
  shows the count dropped, or 2 s (`SETTLE_TIMEOUT`), so a stale count never
  deletes below the limit.
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
  WTF during the delete), put the shard back. Never pick up or delete while
  deletion is restricted (`DeletionRestricted`, checked at each call: before
  the pickup and again before `DeleteCursorItem`): `InCombatLockdown()`,
  `UnitAffectingCombat("player")` true or secret, or an active Combat,
  Encounter, ChallengeMode, PvPMatch, or Map AddOn restriction. Found in
  client: `DeleteCursorItem` from a key press raised "[ADDON_ACTION_BLOCKED]
  ... 'UNKNOWN()'" (BugGrabber, 6x, in a dungeon with DBM). The keep count
  leaves such a shard for the first input after. A refusal anyway, while a
  restriction began meanwhile, waits silently; one otherwise reports once and
  stops deleting until `/reload` (this could still happen only under a
  client rule WTF cannot read). A pickup that takes nothing (empty cursor: nothing to put back)
  waits for the next input, and after 3 such tries that slot is skipped (its
  shard stays; another may go). `/wtf debug_shards` shows the count, limit,
  and keep count, the stop reason, the last attempt (result, count, keep
  count, combat, restriction), each deletion (slot, count and keep count
  before it), and each gain with the keep count after it.

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
  `/use [btn:2] <create>` and `/stopmacro [btn:2]`, then the `/use` lines.
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
  press or click. While item moves are restricted (`WTF.MoveRestricted` in
  Core, the shard guard's states, checked before the pickup and again before
  `ClickTradeButton`) WTF picks up and clicks nothing: it tries at the next
  key press, and if that is restricted too, or later than 10 s after the
  click, it says once to drag the stone in yourself (author-approved).
  `/wtf debug_stones` shows `moveRestricted` and `lastRestricted`. WTF never
  accepts a trade.
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
  shows twice. Tabbing or a new focus changes what the pinned rows show.
- Sections (author-approved, player request; always, no switch): the target
  row, the focus row, and the list are three frames
  (`WarlockToolsForeverTracker`, `WarlockToolsForeverTrackerFocus`,
  `WarlockToolsForeverTrackerList`), each its own `RegisterMovable` with its
  own save (`tracker.sections.target/focus/list`), so each drags, snaps
  across Dyre's AddOns and to the grid, and Shift-drags with frames snapped
  to it. A section not yet dragged hangs from an invisible stack frame placed
  where the one tracker frame was (`tracker.position`, kept from older
  versions, else the default) at the old offsets (target 0, focus one row
  plus the outline gap, list two), so nothing moves for current players. A
  dragged section stays where it is put. A list not yet dragged (author-
  approved, player feedback: an empty focus panel left a row-sized gap)
  hangs below the lowest stacked pinned row the game shows, as before 1.1.0:
  a pinned row that was dragged away does not count, a hidden target row
  keeps its space when the focus row shows (the secure focus row cannot move
  in combat), and while frames are unlocked it sits below both. The list is
  a plain frame, so it moves also in combat, and only when its place
  changes. The list frame is one row tall (it snaps by its first row); its
  other rows hang below it. `/wtf reset` clears every section and the stack
  place. The target and focus sections hold secure rows, so they move only
  out of combat (a drop in combat waits); `/wtf debug_tracker` says which are
  moved or stacked. The default spacing is not the snapping gap, so the
  stacked sections do not Shift-drag as one group until dropped snapped.
- Panel opacity (author-approved: its own setting per panel, not one for the
  rows): "Target panel opacity", "Focus panel opacity", and "Other mobs panel
  opacity" (`tracker.panelOpacity.target/focus/list`, 10-100 percent, default
  100, today's look) on the DoT Tracker page. Each sets its section frame's
  alpha, so the whole panel fades, rows and all; SetAlpha is no protected
  action (bar AddOns fade secure bars with it in combat), so it applies at
  once, also in combat, and the engine's buttons are never touched for it.
  Found in client: the engine-driven DoT duration bars did not fade with the
  panel (the pinned Lua has no alpha code; the C side drives the bars). So
  each bar WTF builds ignores its parent's opacity (`SetIgnoreParentAlpha`)
  and carries its panel's opacity in its fill color and its spell-name and
  time texts, which gives exactly the panel's opacity whatever the engine
  does. Only while it is built (`PrepareBar`, inside `initializeFrame`,
  before `SetDurationBar`/`SetSpellName`/`SetDurationText`): what WTF hands
  the engine is the engine's afterwards, and touching it raised "calling
  'SetStatusBarColor' on bad self (Attempt to access forbidden object from
  code tainted by an AddOn)" (found in client, 13x, from the opacity
  slider). So a panel opacity change fades the panel frame at once (also in
  combat) and rebuilds the rows for the bars (out of combat; in combat, when
  it ends). Separate from the nameplate dot opacity.
- Each row has slots, by default in this order (author-approved): Curse (Weakness,
  Recklessness, Elements, Shadow, Tongues, Exhaustion; one at a time), Bane
  (Agony, Doom, Havoc), Corruption, Immolate, Siphon Life, and Fear and
  control (Fear, Howl of Terror, Death Coil, Banish), from Forever's spell
  list and talents. The DoTs page (author-approved, player request) changes
  it for the rows and the nameplate dots. Single-target channels
  (Drain Life, Drain Soul, Drain Mana, Wrack) are not tracked
  (author-approved). A list row appears when the player's cast of a
  tracked spell succeeds on a hostile mob (cast events, target name, and
  `UnitGUID` are readable in combat). The mob is found when the cast starts
  (`UNIT_SPELLCAST_SENT`: the first unit with that name, target first) and
  its GUID kept with that cast, then used at `UNIT_SPELLCAST_SUCCEEDED`; a
  success drops only its own pending cast (player report: with same-named
  mobs, a tab before Immolate landed gave the new target's GUID). A cast by
  name on a same-named mob that is not the target (a mouseover macro) can
  still pick the target. A row leaves when the mob dies (`UnitIsDead`
  on its unit), when combat ends, or, out of combat, after 10 s with no unit
  showing it; in combat a row with no unit stays until combat ends (player
  feedback: nameplates off and on, or out of plate range, lost rows), and it
  binds again by GUID when a unit shows the mob. A
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
  nameplate token, else target or focus, else "none". A plate is matched by
  its GUID, or, when that is secret (player report: a dotted target you
  tabbed away from stayed dim beside its own plate), by a remembered
  token-to-GUID map (`tracker.plates`), learned from `UnitIsUnit` with the
  target or focus (whose GUIDs are readable) on target, focus, and plate
  changes and at each new row; a token is forgotten when its plate goes or is
  reused. `/wtf debug_tracker` reports the plates (shown, readable GUID,
  known, the target's plate) and each row's unit and hold. Known limit
  (author-accepted, in README): when plate GUIDs are secret, a mob never
  targeted or focused (a mouseover DoT) has no known plate, so its row stays
  unbound (dim, no health) until you target or focus it, or combat ends.
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
- Sizes per theme (author-approved, player request; no free offsets):
  `tracker.sizes.compact` (icon size 16-40, default 22; name width 60-200,
  default 110; text size 50-200%, default 100; name Left, Right, Above, or
  Below, default Left) and `tracker.sizes.bars` (bar width 150-500, default
  290; line height 12-28, default 16, the icon 2 less; text size; name Above
  or Below, default Above), specs in Core's `TRACKER_SIZE_SPECS`. Names and
  health texts are one line (`SetWordWrap(false)`, `SetMaxLines(1)`), cut
  with "..." only when they do not fit (found in client: long Compact names
  wrapped onto 2-3 lines and spilled out of the row). Beside the icons the
  name has its whole column, from the row's inner edge to the first icon
  less 4; above or below them, the row's whole width; the health text takes
  the end of that room, so the name is cut first. Name width stays (author's
  ask: decide and say why): it is the width of the name's column beside the
  icons, the only room a Compact name beside them has, so it is the clear way
  to give long names more room; the tooltip says so. A name never changes a
  row's size. Defaults are
  the old constants, so the look is unchanged. Text size scales each font
  from its own size. Only the chosen theme's settings show
  (`AddShownPredicate`, pinned Blizzard_Settings.lua:96; the list checks it
  again on each setting change, Blizzard_SettingsPanel.lua:788-809). "Reset
  size" (`CreateSettingsButtonInitializer`, pinned
  Blizzard_SettingControls.lua:1014) restores the chosen theme's defaults. A
  change rebuilds the rows (engine slots are placed only in
  `initializeFrame`), out of combat; stacked sections follow the new row
  size.
- Mob health (author-approved, player request): "Show mob health"
  (`tracker.health`, default off) makes the line with the mob's name the
  health bar (author-approved), filled in the panel's color (see Panel
  colors), at 80% so the text reads. It spans the name line, at least as wide
  as the DoTs: its own line across the row in Bars and for a Compact name
  above or below the icons; for a Compact name beside them (player request),
  only the name's column, from inside the border to the icons less 2. Rows keep their size. A child frame draws over its
  parent's regions, so the name, health text, and dim icons go on a layer
  frame one level above the bar, and the engine's container one above that;
  and
  "Health text" (`tracker.healthText`: None default, Number, Percent, Number
  and Percent) puts text after the name, in room taken from the name's width.
  Enemy health is secret in combat: WTF never reads, compares, or formats it
  as a string. The bar takes `UnitHealthMax`/`UnitHealth` through
  `SetMinMaxValues`/`SetValue` (secret-accepting, as Dyre's Shields Up shows
  its absorb); the number is `AbbreviateNumbers(UnitHealth
  (unit))`; the percent is `UnitHealthPercent(unit, true,
  CurveConstants.ScaleTo100)` formatted with `string.format("%d%%", ...)`,
  the API path EllesmereUI's unit frames use on this client
  (`EllesmereUIUnitFrames/EUI_UnitFrames_Text.lua:421-424`; learned there,
  written here). Number and percent are separate font strings, so no secret
  string is formatted. Updated on `UNIT_HEALTH`/`UNIT_MAXHEALTH`, when a
  row's unit changes, and on target or focus change; hidden while a row has
  no unit. Without `UnitHealthPercent` the percent text stays empty. A change
  rebuilds the rows, out of combat.
- "Known" means learned: the spellbook also lists spells learned later
  (`SpellBookItemType.FutureSpell`), which count as unknown for the tracker's
  slots, the pinned recasts, and the nameplate dots.
- Rows have an engine slot only for the spell families you know
  (`tracker.shown`); a spellbook change updates the filters of those slots
  only, and a newly learned family's slot comes with the rebuild that
  follows. Asking for a slot a row lacks raises "aura slot 'siphon' was not
  found with this key." (found in client, 69x, for a Warlock without Siphon
  Life; the mock now raises it too).
- Pinned slots are `SecureActionButtonTemplate` buttons over the engine slots:
  `/use [@target,harm,nodead] <name>` (or `[@focus,exists,harm,nodead]`), by name so the highest
  rank is used. Bane and Curse slots recast the last Bane or Curse cast (saved
  per character). Their attributes change only out of combat. The pinned rows
  live in their sections' frames, and the game shows and hides the rows with
  `RegisterStateDriver(row, "visibility", "[@target,harm,nodead] show; hide")`
  (focus: `[@focus,exists,harm,nodead]`); the list
  (`WarlockToolsForeverTrackerList`) is an ordinary frame.
- Locked, tracker rows let clicks through (the pinned rows' own mouse, a
  secure frame's, changes only out of combat); their slot buttons always take
  clicks. Unlocked, the rows take the mouse to drag. With Dyre's Toolkit, while
  Ctrl is held out of combat (`MODIFIER_STATE_CHANGED`), the locked rows take
  the mouse too, so a Ctrl-drag goes to the toolkit's `BeginDrag` and moves
  that panel freely (the family's locked Ctrl-drag; player report: no part of
  a locked panel took the mouse). Not changed during a drag, so its drop
  arrives; turned off at `PLAYER_REGEN_DISABLED`, which comes before the
  lockdown.
- A mob seen dead on any unit (`UNIT_HEALTH`, or `NAME_PLATE_UNIT_REMOVED`
  as its plate goes) loses its row, and its GUID is kept until combat ends,
  so a late cast does not list it again. A target or focus that leaves with
  no unit showing its mob (a dead mob's plate goes) is held off the list
  until a unit shows it again (player report: a dying target showed for a
  moment as an Other row).
- List rows only display: a secure button cannot change its unit in combat,
  and the restricted environment has no `UnitGUID` or `UnitName`, so secure
  code cannot tell which nameplate belongs to a row. Nameplate AddOns only
  decorate Blizzard's plates, whose click the engine handles. Never promise
  clicking a list row to target or cast.

### Nameplate DoT dots (built, part of the tracker)

- Nameplate dot opacity (author-approved, player request: "Opacity for dot
  icons" means the nameplate dots, not the tracker rows): "Nameplate dot
  opacity", `tracker.plateDotsOpacity`, 10-100 percent, default 100 (today's
  look), under the dots switch on the DoT Tracker page. It sets each bubble's
  alpha (WTF's own frame: background, grey dots, and colored dots), at once,
  also in combat, and on each bubble as it attaches. The tracker rows keep
  full opacity.

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

### DoT damage prediction (built 1.4.0, phase 1: Classic Era; John: "go")

Predict.lua. Research and John's rulings: the shared notes'
wtf-dot-damage-prediction-research.md. Phase 2 (Forever, an estimate from
your casts and `UNIT_COMBAT`, no DIES) is not built; it waits for John.

- Gated on APIs (the same gate as Dyre's Crit Mayhem): the combat log is used
  when `C_CombatLog.IsCombatLogRestricted` is absent or false and
  `C_CombatLog.GetCurrentEventInfo` (or the deprecated
  `CombatLogGetCurrentEventInfo`) exists. Otherwise (Forever) Predict.lua
  makes no frame and registers no event, and the three settings are greyed
  (modify predicate) with "WoW: Forever support comes later".
- By mob GUID, from `COMBAT_LOG_EVENT_UNFILTERED` with source you:
  `SPELL_AURA_APPLIED`/`REFRESH` start a DoT (a refresh starts its ticks
  over and keeps a learned tick of the same rank), `SPELL_PERIODIC_DAMAGE`
  (Siphon Life: `SPELL_PERIODIC_LEECH`) ticks, `SPELL_PERIODIC_MISSED` (a
  resisted, absorbed, or immune tick) is a tick seen with nothing to learn,
  `SPELL_AURA_REMOVED` ends it. Aura events count only with aura type
  "DEBUFF" (field 15);
  `UNIT_DIED`, `UNIT_DESTROYED`, or `PARTY_KILL` with that dest ends the mob.
  A `C_Timer` drops each DoT 0.5 s after its last tick, for an end out of
  combat log range. Others' DoTs never count.
- The rank: the combat log's spell ID, or, with a 0 ID, the spell name and
  the rank of your last `UNIT_SPELLCAST_SUCCEEDED` of that family.
- Damage to come: the sum of the ticks left (those not seen, or due by time
  when some were missed). Each DoT keeps an average tick: the mean of its
  ticks this cast (John, from the Does It Die comparison, 2026-10-29); before
  its first tick, the saved tick of that rank, else the rank's base (Classic
  tooltip values, RANKS) plus `GetSpellBonusDamage(school)` times duration /
  15 (at most 1; Immolate's over-time part 0.65, Siphon Life 0.5), less
  3.75% per level for ranks below level 20. The base values and
  coefficients are a first guess only (medium confidence); the learned tick
  is exact.
- Curse of Agony: its ramp (0.5, 1, 1.5, four ticks each) applies to the
  rank's base per tick only; the rest of the average (spell power) is even
  over the ticks. A tick of amount a at weight w stands for the average
  a - base x w + base. Found in game on TBC by Does It Die's port; not yet
  confirmed on Era.
- Saved ticks (author-approved, 2026-10-29): account-wide, in
  `WarlockToolsForeverAccountDB.ticks[rank spell ID] = {tick, power}`: the
  average to one decimal and the spell power the DoT was cast at, written at
  each tick. A new cast of that rank starts from base + (tick - base) x
  power now / saved power (no rescale when the saved power is 0 or the tick
  is not above the base). Repaired on load (Core's LoadTicks); ranks not in
  RANKS are dropped at login, so at most 25 entries.
- Drawing: Blizzard's target frame bar (`TargetFrame.healthbar`, else
  `TargetFrameHealthBar`), each DoT tracker row's health bar (John, 1.4.0:
  when both "Show mob health" and "Show Predictive DoT Damage" are on, with
  no switch of its own and mob health never turned on for it; `UpdateHealth` calls `WTF.DrawRowPrediction` with
  the row's GUID and the health it shows, at the bar's own frame level, under
  the row's text layer), and each hostile, not forbidden nameplate's
  `UnitFrame.HealthBarsContainer.healthBar` (Era's Blizzard_NamePlates.xml;
  else `UnitFrame.healthBar`). The block is WTF's own StatusBar, a child of
  the bar, from the bar's left edge to its fill texture's right edge, filled
  from the right (`SetReverseFill`) with `min(damage, health)` out of the
  health left: it ends at the health and is never wider than it. DIES when
  the damage is at least the health (John, after his Era test: the first
  "DIES" text was hidden under a row's texts, ran into a nameplate's name,
  and was small on the target frame): a badge, a red skull (the game's level
  skull, `UI-TargetingFrame-Skull`, tinted red; not the raid marker's, which
  a mob marked by /tm shows on the same frames) and "DIES" in red with
  `THICKOUTLINE`, at the bar's level + 12 (above a row's text layer and
  slots), at UI scale whatever the bar's own scale (found in client:
  Platynator's scaled-down display made it a few pixels tall), placed by kind
  for every adapter of that kind unless the adapter gives its own (`dies`):
  unit frames just left of the bar, vertically centered (14 pt; found in
  client: centered, it ran into SUF's name; SUF writes its name on the
  bar's left and health on its right, Blizzard and BetterBlizzFrames the
  name above and the health text in the middle, so left of the bar is the
  free side); nameplates just right of the bar (11 pt, clear of the name
  above and Plater's raid marker on the left); Platynator 22 px right of the
  bar, past its target arrows, vertically centered, in strata LOW above its
  BACKGROUND display (found in client: above the bar it ran under the
  centered name); tracker rows (10 pt) in place of the health number,
  which hides while DIES shows (with "both", the percent drops its "|";
  found in client: at the bar's end it covered "| 137"), just left of the
  percent with the percent only, else at the bar's right end. Nothing is drawn on target-of-target or other unit frames. A secret or missing health, a mob you cannot attack, or no damage
  hides the block. The target frame's block is made at login.
- Tracker rows are per GUID (John: "a row with no unit token still has the
  GUID's prediction"): where the prediction runs, a list row keeps the last
  readable health of its mob (`row.knownHealth`, dropped when the row gets
  another mob) and shows it, with the block, while it has no unit. On
  Forever (prediction off) such a row hides its health, as before. `Bind`
  to the same unit still updates the health, so a reused row never keeps
  the old mob's.
- Redrawn on its combat log events (also the tracker rows, through
  `WTF.RefreshTrackerPrediction(guid)`), `UNIT_HEALTH`, `UNIT_MAXHEALTH`,
  `PLAYER_TARGET_CHANGED`, and `NAME_PLATE_UNIT_ADDED`/`REMOVED`, and when a
  tracker row is bound or rebuilt; no polling.
- Settings (`db.predict`, repaired on load; on by default): `enabled` "Show
  Predictive DoT Damage" (John, 1.4.0), `plates` "Also on nameplates",
  `dies` "Show DIES", in their own section at the end of the DoT Tracker
  page. A test build's `tracker` switch is dropped on load.
- The block's look (John, 1.4.0: "make them look the same everywhere"; his
  Era screenshot showed no block on a purple tracker row): one `Style` for
  every overlay (every adapter and the tracker rows). The overlay's own
  StatusBar fill is clear and only measures the span; a texture over it is
  the block, and four 1 px textures its outline. `fill`: Stripes (default;
  the Toolkit's Textures\Stripes, white stripes at full alpha over 40% gaps, tiled with
  REPEAT, tinted by the color, no animation), Solid (WHITE8X8), or Bar
  texture (the bar's own fill: its atlas, else its file). `color`: Purple
  (default), Red, Orange, White, Green (Core's PREDICT_COLORS). `opacity`
  20-100%, default 70. `outline`: None or Solid (default), the color 40%
  lighter, 30% more solid. On a bar whose own fill color is within 0.15
  (sum of red, green, blue) of the block's, the block is 50% lighter.
  Restyled only when a setting or the bar's color or art changes.
- Damage source (John, 2026-10-31; Toolkit 2.4.0's public HealthBars API,
  ../DyresToolkit/docs/HEALTHBARS_API.md): Predict.lua registers WTF with
  `HealthBars.RegisterSource` at priority 10 (Dyre's Debuff Tracker will be
  20 and win) when `DyresToolkit.HealthBars` and each function it calls
  exist; else (an older Toolkit) WTF draws as in 1.4.0. `damage` answers a
  unit token or GUID (nil for a mob with no DoT of WTF's); `refresh` redraws
  that unit's target frame, plate, and rows, or all for nil; no `willDie`
  (the Toolkit compares with readable health). The target frame and plates
  draw only while `IsActiveSource` is true, and WTF then leaves those bars
  alone (not even a hide: the block is one per bar). Tracker rows are WTF's
  own bars and always draw: the active source's `GetPredictedDamage` while
  another source is active, redrawn on its `PREDICTION_CHANGED`. WTF calls
  `NotifyChanged(addon, nil, guid)` in DrawGUID, on its combat log events
  and DoT expiry only. "Show Predictive DoT Damage" follows with
  `SetSourceEnabled` (at login too); turned off, WTF hides its blocks first,
  then steps aside and asks `Refresh(nil)` so the next source draws.
  Registered only where the prediction runs (the combat log; Era).
- Frame adapters (John, 1.4.0: ThreatPlates, Plater, then EllesmereUI; SUF
  next; since 1.4.1 the Toolkit's `FindPlateBar`/`FindUnitBar`, `UseBar`,
  `PrepareBar`, `DrawPrediction`, `HidePrediction`, and `MoveDies`; WTF
  passes the look from `db.predict` and decides when to draw; the Toolkit
  also keeps DIES clear of Threat Plates' target-of-target text and Plater's
  cast target and raid marker): once `PLATE_ADAPTERS` and `UNIT_ADAPTERS`, one entry per
  AddOn, each returning the StatusBar for a plate or for "target"/"focus",
  else nil; the first match wins, Blizzard's bar last. Each path is read
  field by field (`Field`, `StatusBar`), so a missing or changed AddOn gives
  nil, never an error. Paths read from the AddOns' source on Era:
  - Threat Plates 13.3.3: `plate.TPFrame` while `.Active` (Nameplate.lua
    `ShowBlizzardNameplate`), bar `.visual.Healthbar` (or `.healthbar`).
  - Plater: `plate.unitFrame.healthBar` with the `Plater` global (Plater.lua;
    DetailsFramework `CreateHealthBar`), also with "use UIParent".
  - Shadowed Unit Frames v4.3.9: `ShadowUF.Units.unitFrames[unit].healthBar`
    (modules/units.lua, modules/health.lua).
  - EllesmereUI (not installed anywhere; from Does It Die only, unverified):
    `EllesmereNameplates_NS.plates[unit]` while its `.nameplate` is this
    plate, bar `.health`; `EllesmereUIUnitFrames_Target`/`_Focus`, `.Health`.
  - Platynator 527 (John, 1.4.0; read in its source on Era; its TOC lists
    11509 and 16001): with the `Platynator` global, the shown display frame
    among the plate's own children (`.widgets`, `Install`, `SetUnit`) whose
    `.unit` is the plate's unit; its widget with `details.kind == "health"`
    holds the bar at `.statusBar`. Its manager installs one display per
    plate and style in its own `NAME_PLATE_UNIT_ADDED` handler
    (`SetParent(nameplate)`, `SetUnit`) and uninstalls with `SetUnit(nil)`
    and `Hide` (Display/Initialize.lua, Display/Nameplate.lua,
    Display/Widgets.lua). Its CallbackRegistry is private, so there is no
    event to hook; the plate's children are read at each draw.
  - BetterBlizzFrames v2.1.8 (Era source, classics/): restyles Blizzard's
    frames; it moves, resizes, and re-textures `TargetFrameHealthBar` but
    keeps it, so Blizzard's entry covers it (the block re-anchors to a new
    fill). It adds no target or focus bar of its own, no reverse fill, and
    no nameplates. Its "smooth bars" option (shared/smoothBars.lua) hides the
    stock fill (alpha 0) and shows an eased StatusBar child,
    `TargetFrameHealthBar.bbfSmoothOverlay`, mirroring values, color, and
    texture: the BetterBlizzFrames entry puts the block on that one.
  The bar is resolved again at each draw, and a block on a bar the unit
  left is hidden (`UseBar`: Threat Plates letting a plate go, recycled
  plates). `NAME_PLATE_UNIT_ADDED` draws at once and once more on the next
  frame (`C_Timer.After(0)`), after the AddOns' own handlers for the event.
  Each draw re-anchors when the fill texture or reverse fill changed (SUF
  can reverse-fill: the block is mirrored) and sets the frame level; a
  vertical bar gets no block. The focus frame is drawn too where a focus
  exists. `/wtf debug_predict` prints "Frames:" with the AddOn per unit.

### Clients without a focus target (built 1.3.3; shared with MTF: one account-wide flag per client)

John, 1.3.3: "@focus and /focus do not work in era". Found in client on Era:
after `/focus` on a hostile target, `UnitExists("focus")` is false and
`SecureCmdOptionParse("[@focus,exists] yes; no")` is "no", with no error.
Both Classic clones ship every focus function, event, and frame, so no API
tells; the rule learns it, identically in MTF (keep the two the same):

- Since 1.4.1, Dyre's Toolkit's `DyresToolkitDB.focusWorks`, one flag for
  every Dyre's AddOn (`FocusWorks`, `LearnFocusWorks`, `OnFocusWorks`,
  `ResetFocusWorks`). At login a true WTF flag is noted there once
  (`NoteFocusWorks`) and WTF's key goes; without the Toolkit WTF's own flag
  stays for a later login. Control's PLAYER_FOCUS_CHANGED asks
  `LearnFocusWorks` before it rebinds (whatever the handler order), and its
  `OnFocusWorks` listener rebuilds the macros and clicks on every learn and
  reset (each waits for combat to end). `/wtf reset_focus` resets it for
  every Dyre's AddOn and says so (`FOCUS_RESET_TEXT`). Before 1.4.1:
- `WarlockToolsForeverAccountDB.focusWorks`, account-wide (TOC
  `## SavedVariables`, beside the per-character `WarlockToolsForeverDB`), so
  one value per client install, shared by every character, as MTF's
  `MageToolsForeverAccountDB.focusWorks`. Nil at first. It becomes true the first time `PLAYER_FOCUS_CHANGED` comes with
  `UnitExists("focus")` true, readable and not secret. It never goes back to
  false on its own; `/wtf reset_focus` clears it. Repair keeps only `true`.
  A 1.3.3 test build kept it per character in `db.control.focusWorks`; a true
  one is carried into the account value once at load, and the key goes.
- Until it is true: the macros keep their `/focus` line (on Forever it sets
  the focus that teaches WTF; on Era it does nothing) and add the mob under
  the mouse, then your target, after `[@focus,exists,harm,nodead]`: "! Fear"
  appends `[@mouseover,harm,nodead][harm,nodead]` to its cast (Shift still
  fears the mob under the mouse, else your target, without the focus);
  "! Banish"'s `/tm` and `/use` and "! Seduction"'s `/use` (with its pet
  condition in each clause) get the same order. Banish rows start from the
  cast as Fear rows do (not focus-only), rows take no clicks, and the Focus
  box is hidden (also unlocked).
- Once it is true, out of combat (macros and secure attributes wait for
  `PLAYER_REGEN_ENABLED`), the Forever forms, the Focus box, and Banish row
  clicks come back. `/wtf debug_control` prints `focusWorks=`.

### Control bar and control announcements (built)

- After MTF's Polymorph bar, for many mobs (author-approved): up to five
  rows, one per mob you Fear or Banish, each an AuraContainer slot
  (`HARMFUL|PLAYER`, Fear and Banish IDs plus spellbook IDs of those names)
  with the mob's name above a bar line. Rows come from your cast events. The
  mob is locked as the cast starts (`UNIT_SPELLCAST_SENT` names it): the first
  live hostile unit with that name in the order WTF's own casts aim, focus,
  then mouseover, then target, then a nameplate; its GUID is used when the
  cast lands, never a new lookup by name (player report, the DoT tracker's
  bug class: a tab or mouse move mid-cast, same-named mobs). Known limit: a
  plain spell-button cast at your target, while your focus or the mob under
  the mouse has the same name, counts on that one. Rows bind to the mob
  through your focus, then target, then its nameplate by GUID, else Core's
  plate memory (`WTF.KnownPlate`, shared with the tracker, for secret plate
  GUIDs); never mouseover. A recast on the same mob keeps its row. A secret
  "can attack" or "dead" answer counts as a live hostile mob, a unit with a
  secret GUID is skipped unless Core's plate memory knows its plate, and a
  spell ID missing from the sets counts by its name (client-only cases, kept
  after a 1.3.1 report). `/wtf debug_control` reports `lastSent` (spell,
  target name, the unit locked, and each unit looked at: attack, dead,
  readable GUID) and `lastLanded` (the row and its unit, or why none). A row goes when the mob dies, after the longest such spell plus 5 s
  (Fear 20, Banish 30), or never when the cast fails.
- A raid marker per spell (Control page; Banish moon by default;
  author-approved: single-target control only, one marker slot in a group, so
  Fear never marks and has no marker setting). An earlier default diamond
  moves to the moon once (`markersVersion`).
- WTF never calls SetRaidTarget (author-approved, found in client): MTF's
  call, with the same out-of-combat guard WTF had, raised
  "[ADDON_ACTION_FORBIDDEN] AddOn 'MageToolsForever' tried to call the
  protected function 'SetRaidTarget()'" (BugGrabber, 4x, from Mark() in
  OnCastSucceeded; the taint log agrees), so AddOn code may not call it even
  out of combat. The exact rule is unknown (TankHelper's direct call on an
  unmarked target from a C_Timer callback works); do not try to work around
  it. In combat it also showed the "blocked from an action only available to
  the Blizzard UI" popup (pinned RaidMarkersDocumentation: HasRestrictions).
- Markers come only from the game's `/tm` (author-approved, as MTF): a
  macro's `/tm` runs untainted from the key press (pinned SlashCommands.lua),
  so it works in and out of combat. "! Banish" is exactly MTF's "! Polymorph"
  with Banish (John, 1.3.1): `#showtooltip Banish`, `/focus
  [@mouseover,harm,nodead][nocombat,harm,nodead]`, `/tm
  [@focus,harm,nodead,exists] !N` (`WTF.MarkLine`; N is the Banish marker
  setting, and None leaves the line out), `/use [@focus,exists,harm,nodead]
  Banish`. "!" keeps a second press from toggling it off. A marker change
  rebuilds the macros out of combat. The row click, "! Fear", and
  "! Seduction" have no `/tm`; Banish from the plain spell button gets no
  marker. %M names the marker ("{moon}") for a Banish at your focus (the mob
  "! Banish" marks), else nothing. A
  player's own `/tm` macro without "!" toggles the marker WTF's macro set, so
  the README says to set the marker to None when using one.
- Banish follows the focus only (John, 1.3.1, as MTF's Polymorph bar): a
  Banish counts only when the cast's name is your focus's and the focus is a
  live hostile mob with a readable GUID, locked as the cast starts
  (`LockFocusGUID`). Its row binds to "focus" and goes when your focus becomes
  another mob or none, or dies (a focus with a secret GUID stays). A Banish at
  a mob that is not your focus shows no row.
- Click to recast, Banish only: each row has a fixed secure click slot under
  it (`WarlockToolsForeverControlClick1`..5) with only `/use
  [@focus,exists,harm,nodead] Banish` (`WTF.RecastMacro`): no marker, no
  targeting by name; with no focus it does nothing. Set only out of combat: at cast start for a pull, else
  when combat ends. A slot shows only while it has a click (or while
  unlocked, to drag by). A secure slot cannot hide in combat, so a row whose
  mob died or whose cast failed in combat stays on screen, dimmed, while its
  slot still shows: no click area is ever invisible (MTF had one).
- The Focus box (John, 1.3.1: "put a special box on the top if/when the
  focus target is feared"): `WarlockToolsForeverControlFocus`, a fixed secure
  button above the rows (BOTTOMLEFT on the anchor's TOPLEFT), whose only
  click is `/use [@focus,exists,harm,nodead] Fear`: it always aims at the
  focus, so it can never fear another mob, also when the focus changes in
  combat, and with no focus it does nothing. Its display is a child frame
  (focus panel color, "Focus: <name>", a dim Fear line) with an AuraContainer
  bound to "focus" (Fear IDs only). Shown by a state driver `[@focus,exists,
  harm,nodead] show; hide` ("show" while unlocked, "hide" when the bar is off
  or no Fear is known), set out of combat. AddOn code cannot read auras in
  combat and a secure frame's visibility can follow only unit conditions, so
  it cannot hide while the focus is not feared: it shows while you have a
  live hostile focus, never as an invisible click area. A Fear row whose mob
  is your focus hides (the box shows it) and comes back when the focus
  changes; rows are plain frames, so this follows in combat. Banish keeps its
  own focus row; it could move into this box later.
- Fear rows have no click (author-approved): a secure
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
  "! Fear" once you know Fear, inverted in 1.3.1 (John: "set focus by
  default, shift fears a mob without changing focus"): `/focus
  [nomod:shift,@mouseover,harm,nodead][nomod:shift,harm,nodead]` then `/use
  [mod:shift,@mouseover,harm,nodead][mod:shift,harm,nodead][@focus,exists,
  harm,nodead] Fear` (181 letters): a plain press makes the mob under the
  mouse, else the target, your focus and fears it (with neither, your focus
  as it was); Shift fears the mob under the mouse, else the target, and
  keeps the focus. No /tm, as Fear has no marker setting; "! Banish" once you know Banish and "! Seduction" once your summoned demon
  knows Seduction (a Grimoire teaches it; the pet spellbook, by ID or by name,
  so a Succubus or an Incubus counts; checked on `UNIT_PET` and
  `SPELLS_CHANGED`; the macro stays when the demon is dismissed; per the
  author, a learned Grimoire teaches both the Succubus and the Incubus): `#showtooltip`, `/focus [@mouseover,harm,nodead]
  [nocombat,harm,nodead]`, `/use [@focus,exists,harm,nodead] <spell>` (Seduction
  with `pet:Succubus/Incubus`, so it does nothing without one). "! Banish"
  also has its `/tm` line (see the marker rules above); the others have none.
  Written with Stones' macro writer, out of combat; off deletes them.
- Group messages as the cast starts (Announce page, `WTF.SendGroupAnnouncement`,
  the Announce channel, nothing alone, at most every 3 s per spell): Fear,
  Banish, Enslave Demon, and Howl of Terror (no target).

### Dyre's Toolkit (built; author-approved, 2026-10-19)

- Dyre's Toolkit (`src/DyresToolkit`, owned by the coordinating session; do
  not edit it, send needs there) gives every Dyre's AddOn one layout mode,
  grid, snapping across AddOns, and the "Dyre's AddOns" settings home. The
  TOC lists `DyresToolkit` in `## OptionalDeps` (never `## Dependencies`) and
  `## Group: DyresToolkit`, so WTF nests under it in the AddOn list;
  CurseForge has it as a required dependency (`dyres-toolkit` in
  `RELATIONS`). `RELATIONS` also lists Weapon Skills Forever
  (`weapon-skills-forever`) as an optional dependency, as the author set it on
  the project; WTF does not use it, so the TOC does not name it.
- Core's `WTF.Toolkit()` returns `DyresToolkit.RequireContract(1)` when every
  function WTF uses is there (`RegisterAddOn`, `RegisterSettingsCategory`,
  `RegisterMovable`, `BeginDrag`, `EndDrag`, `ScaleKeepingCenter`,
  `IsLocked`, `Lock`, `Unlock`, `OpenSettings`), else nil and "missing" or
  "old". At login, before any module registers a frame, Core points
  `WTF.RegisterMovable`, `WTF.BeginDrag`, `WTF.EndDrag`, and
  `WTF.ScaleKeepingCenter` at the toolkit's and copies its lock (locked at
  login) into WTF's lock flags. After the settings exist, WTF calls
  `RegisterAddOn` with `setLocked` (`WTF.SetFramesLocked(locked, true)`: the
  same flags and refreshes, no chat line, since the toolkit says one for all)
  and `openSettings` (`WTF.OpenSettings`, through the toolkit's
  `OpenSettings`, which refuses in combat).
- With the toolkit, `/wtf unlock` and `/wtf lock` call the toolkit's
  `Unlock`/`Lock`; WTF's pages have no unlock or grid switch (author-approved:
  the toolkit's page has them for every AddOn; `db.grid` stays), and WTF
  draws no grid; WTF's page is
  `RegisterSettingsCategory("Warlock Tools Forever")` with every WTF page
  under it, and no `RegisterAddOnCategory`. If it returns nil, WTF makes its
  own top-level page.
- Without it (or with an older one), WTF works as before: Layout.lua, WTF's
  grid, its top-level page, and its own lock messages, and it says once at
  login to install (or update) Dyre's Toolkit, naming only CurseForge.

### Macro text (author-approved)

- Every macro and click macrotext WTF writes uses `/use`, not `/cast` (every
  letter counts): the pinned SlashCommands.lua `/use` handler tries an item
  (SecureCmdItemParse, C_Item.GetItemInfo(name)), else CastSpellByName, so
  it casts spells. No spell WTF names is an item's name; a new spell whose
  name is also an item's keeps `/cast` on its line. Every `@focus` condition
  has `exists` (author: focus conditions need it), as in
  `[@focus,exists,harm,nodead]`; the `/tm` lines use `[@focus,harm,nodead,exists]`.

### Magnetic frames (built)

- Layout.lua (author-approved, MTF's snapping improved; used only without
  Dyre's Toolkit, whose layout has the same rules): every movable WTF
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

### Slider labels (author-approved, family-wide)

- A percent slider's value shows its % sign (Options' `SliderOptions(...,
  true)` or a `"%d%%"` label formatter), so its label has no "(%)": "Bar
  size". A test fails on any WTF setting label with "(%)".

### Slot colors (author-approved)

- One color per slot (`WTF.DOT_SLOTS` in Core: Curse purple, Bane red,
  Corruption white, Immolate orange, Siphon Life green, Fear and control
  yellow; author-approved),
  shared by the tracker's bars and the nameplate dots so the colors become a
  quick visual code. Saved per character as `AARRGGBB` hex strings, the
  format of the Settings color swatch, and editable on the DoTs page with a
  nameplate switch per slot. The tracker's bars take their color only
  as they are built (see the panel opacity rule: the engine owns them
  afterwards), so a new color rebuilds the tracker's rows, out of combat; the
  nameplate dots are WTF's own textures and change at once. When defaults change, a
  one-time step (`colorsVersion`) moves slots still on an old default to the
  new one and keeps colors the user picked.
- DoT Tracker page sections (author): "General" first (theme, nameplate
  dots, mob health, sizes, and Reset size: what every panel shares), then
  "Target", "Focus", and "Others", each with that panel's own settings (its
  color, then its opacity), from Core's `TRACKER_PANELS`. Headings are
  `CreateSettingsListSectionHeaderInitializer`. Per-panel health and sizes
  are not built (author: not yet, unless trivial; it is not: every layout
  function reads one shared size set).
- Panel colors (author-approved, player request): a swatch in each panel's
  section, `tracker.panelColors.target/focus/list` (`AARRGGBB`, Core's
  `TRACKER_PANEL_COLORS`; the alpha is not used, as the panel opacity does
  that). Defaults are the colors before 1.2.0: the warlock class color
  (`ff8787ed`), the focus red (`ffe61a1a`), the others' dark grey
  (`ff545454`). Each colors its panel's row border, the pinned rows'
  outline, and the health fill; for the other mobs it replaces their brown
  row border (author's call). All are WTF's own backdrops and StatusBar, not
  engine objects, so a change applies at once, also in combat.
- DoT order (author-approved, player request: configurable, the rotation
  order as the default): `tracker.order`, every slot key once (repaired on
  load: unknown and doubled keys dropped, missing ones added in the default
  order). Blizzard's Settings list has no control to reorder a list, so the
  "DoTs" page (author: one page for the DoTs, replacing DoT Colors and DoT
  Order) is a canvas page: one row per slot, in the order, with its icon,
  name, an "On nameplates" check (`tracker.onPlates`, default on for every
  slot since 1.2.0; disabled, with a tooltip saying why, while "Show DoT
  dots on nameplates" is off or no DoT is known), and a color swatch that
  opens `ColorPickerFrame:SetupColorPickerAndShow` as the Settings swatch
  does (Blizzard_SettingControls.lua, SettingsColorSwatchMixin; Cancel
  restores). Rows reorder by drag and drop, as DQT's hit list (Box.lua): a
  gold line at the drop place from an `OnUpdate` set only during the drag, a
  drop outside the page cancels, a drop next to the row changes nothing.
  "Reset order" restores the order; the page's Defaults restores the order,
  the colors, and the nameplate switches. Engine slots
  are placed only while rows are built, so a change rebuilds the rows (out
  of combat; in combat, when it ends) and the nameplate dots. "Order
  applied" is not offered: when a DoT was applied is secret, and slots
  cannot move in combat.

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

- Runtime files: WarlockToolsForever.toc, Commands.lua, Core.lua, Layout.lua, Shards.lua, Stones.lua, Announce.lua, Tracker.lua, Dots.lua, Predict.lua, Control.lua, Probe.lua, Options.lua, loaded in
  that order. Core also owns the hardware-input hooks
  (every key press and world click) that item deletion and trade placement
  wait for.
  Commands parses `/wtf`; Core owns saved settings and their defaults, the
  login banner, class and install checks, slash conflict reporting, and
  startup, and the moved-feature lines; Layout owns snapping; Shards, Stones,
  Announce, Tracker, Dots, Predict, and Control own their modules; Probe owns
  `/wtf debug_restrictions`; Options owns the settings pages.
- tests/run.lua loads Dyre's Toolkit 2.4.0's Auras.lua, Units.lua, and
  HealthBars.lua from ../DyresToolkit when that folder exists, else (as in
  CI, or with `WTF_TOOLKIT_COPY=1`) from the copy in tests/toolkit, and
  prints which. No test requires the copy to match the Toolkit (John: a
  byte-identical test is the wrong test for a shared resource); refresh the
  copy when the Toolkit's interface changes.
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
- The TOC has `## Group: DyresToolkit`, so the in-game AddOn list nests WTF
  under Dyre's Toolkit with the rest of the family. It keeps
  `## Category: Warlock`, which groups WTF only when the toolkit is missing;
  keep it identical to the CurseForge main category, since the list groups by
  exact text.
- WTF ships no runtime assets and no sound files since 1.4.1 (the DoT
  prediction block's stripes went to Dyre's Toolkit 2.4.0 with its drawing;
  the shield textures to Dyre's Shields Up in 1.3.0); add none without
  agreement.
- Git origin: git@github.com:jbedworth/WarlockToolsForever.git. Inspect Git
  state before acting and preserve user work. Text is LF under .gitattributes.

## Client and API verification

- Target: Forever beta 1.60.1, build 70450, Interface 16001, Lua 5.1 (the
  client WTF is tested on). Pin source review to Gethe/wow-ui-source commit
  `943764493e6b16d63ded3ab304150d1f05e58b57`, which is the 70338 source.
  Treat target-client documentation and FrameXML as authoritative; Retail and Classic examples are references only.
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
- Every CHANGELOG version section (author's format for all of Dyre's AddOns'
  change and version notes, from 1.1.0 on) has descriptive, player-facing
  bullets under `### Features`, `### Fixes`, and `### Other changes`, in that
  order, leaving out an empty one. The builder's section ends only at the
  next `## `, so the `###` headings stay in the release notes.
- Package only WarlockToolsForever.toc, Commands.lua, Core.lua, Layout.lua, Shards.lua, Stones.lua, Announce.lua, Tracker.lua, Dots.lua, Predict.lua, Control.lua, Probe.lua, Options.lua, and LICENSE
  (no textures, no sound files) under the top-level
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
