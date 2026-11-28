# Agent Guidelines

## Project purpose and scope

Warlock Tools Forever (WTF) is a World of Warcraft: Forever AddOn: a suite of
small, independent quality-of-life modules for Warlocks. Each module has an
enable switch on the main settings page and its own settings subpage. Add a
module only after the author agrees its behavior.

### Moved out in 1.3.0 (author-approved, 2026-10-22)

So that WTF stops duplicating Dyre's other AddOns, and players meet them on
their other classes ("virality"):

- The shield display (Shield.lua, its crescent textures, scripts/build_arc.py)
  is Dyre's Shields Up's (DSU). The cooldown chimes (Chimes.lua), the Nightfall
  sound (Alerts.lua), and the Demon Armor reminder (Reminders.lua) are Dyre's
  Buff Reminders' (DBR). WTF ships none of them, and no sounds, so it no
  longer uses Dyre's Sounds. Do not bring any of them back: changes go to DSU
  or DBR through the coordinator. Proc overlays (Nightfall, Decimation) are
  DSU's too (John, 2026-11-18: "DSU is the right home for our 'spell
  activation overlays'"); WTF has none. John, 2026-11-20: every proc cue
  moves from DSU to DBR (DBR 1.13.0, Toolkit 2.12.0), so WTF's code names
  no proc AddOn. The Procs page (was Alerts) follows the owner of the Toolkit kind
  "proc:nightfall" (1.10.1, John: "Yes, fix it"): `WTF.ProcOwner(key)` is
  `KindOwner(PROC_KIND_PREFIX .. key)` when the Toolkit has both, else nil
  (a feature test, as DBR's `ProcOwner`; an AddOn that steps aside for
  SpellActivationOverlay makes no claim). With no owner, the old row
  "Procs" (AddSettingsLink to DBR; 1.13.0 link labels are the section names: "Chimes", "Procs", "Reminders", DDT cues "Debuff Cues"). With an owner,
  "Nightfall arcs and sound": WTF's own button (`AddSettingsLink` fixes its
  AddOn when the row is made), whose click asks for the owner again and
  calls its `openSettings` from `toolkit.AddOns()` (not in combat), and
  whose tooltip names the owner by the title it joined with
  (`WTF.ProcOwnerTitle`, as DBR's `ProcOwnerTitle`), renamed through
  `OnOwnerChanged`. Each row has a shown predicate that asks the owner each
  time the page draws, because the owner claims at its PLAYER_LOGIN, which
  can come after WTF builds the page. No polling. Without shown
  predicates, only the row for the owner at build time.
- TOC: `## OptionalDeps: DyresToolkit, DyresShieldsUp, DyresBuffReminders,
  DyresDebuffTracker` (never `## Dependencies`, so WTF loads without them;
  the toolkit stays optional while WTF is not on toolkit widgets). CurseForge
  lists `dyres-toolkit`, `dyres-shields-up`, `dyres-buff-reminders`, and
  `dyres-debuff-tracker` as required dependencies (`RELATIONS` in
  scripts/publish_curseforge.py), so the app installs them.
- At login, on a Warlock with WTF available, Core's `WTF.ReportMovedFeatures`
  says once per session for each of DSU, DBR, and DDT that is not loaded: "Install
  <title> from CurseForge for <features>.", or
  "Enable <title> in the AddOn list ..." when `C_AddOns.GetAddOnInfo` shows it
  installed but not loadable (reason not "MISSING"). CurseForge only.
- Settings sections (1.13.0; John, 2026-11-26: WTF "should surface every
  setting in the wrapped addon's settings, and just pass-through the setting
  to the wrapped addon"; 2026-11-27: "Fix the settings delegation in MTF and
  WTF"). WTF is a host: each moved page (DDT_PAGES, MOVED_PAGES: `section`,
  `filter`) calls Toolkit 2.17.0's `AddSettingsSection(page, layout, {addon,
  key, host = "WarlockToolsForever", filter, link})`, with `link` the
  AddSettingsLink options below. The owner's rows read and write the owner's
  live settings ("rows"); with the owner or its section missing, the toolkit
  draws the link ("link"); nil, the greyed note. Keys: DDT `tracker`, `dots`,
  `control`; DSU `shield`; DBR `chimes`, `procs`, `reminders` (no filters,
  John 2026-11-27: "Let's add all the Warlock procs/alerts and reminders");
  the Procs page also draws DDT `cues` (Demonic Brand) after DBR's procs
  (`also`), with its own link and primer, and its master follows Procs on the
  top page. Page titles (John: "let's use the same name consistently
  everywhere"): `SettingsSectionTitle(addon, key)`, the owner's title, else
  WTF's word ("DoT Tracker", "DoTs", "Control", "Shield display", "Chimes", "Procs",
  "Reminders"; were "Cooldown Chimes", "Alerts", "Demon Armor"). WTF's own
  pages keep Soul Shards, Stones, Announce. The Procs page asks for a section only when DBR registered
  `procs` (`SettingsSections`; owners register by ADDON_LOADED, before WTF's
  PLAYER_LOGIN builds the page); otherwise it keeps the proc owner rows
  below, which a plain link cannot do. Without AddSettingsSection (an older
  toolkit), every page stays as below. WTF registers no setting of its own
  for these features.
- Primer box (1.13.0; John, 2026-11-27: when the AddOn is missing, "a message
  box on those panels telling people" what they get if they install it). Each
  moved page has `primer`: for a Warlock, what the AddOn adds there, then
  "Install <title> from CurseForge." Plain words, at most 300 characters (the
  toolkit cuts at 400; the box does not grow; a test checks each). Passed as
  AddSettingsSection's `primer` only when `AddSettingsPrimer` exists (2.17.0;
  `SETTINGS_SECTIONS_VERSION` is still 1, so the function is the test); the
  toolkit shows it only while the owner is not loaded. The Procs page's proc
  owner path draws it itself with `AddSettingsPrimer` while DBR is not loaded
  (not joined and not `C_AddOns.IsAddOnLoaded`), shown only while no AddOn
  owns "proc:nightfall".
- Parts (1.13.0; John, 2026-11-27: "when the top-level is off, the settings
  that are controlling a disabled feature should be disabled too. Also, the
  top-level disable for each section should be on the top-level MTF panel",
  for WTF too). With `SETTINGS_SECTIONS_VERSION` 3 or later (`HasParts`), the
  top page has, after WTF's own switches, each moved section's top switch
  (`part = "master"`, no link or primer, in the sub-pages' order: DoT Tracker,
  DoTs, Control, Shield display, Chimes, Procs, DDT's cues, Reminders; DBR's "procs"
  master is the proc engine's switch, John 2026-11-27: "Add the Procs master
  switch", which turns every proc cue off); the
  toolkit adds nothing for a missing owner or a section with no
  single top switch. Each sub-page asks for `part = "rest"`, with link and
  primer; the owner greys those rows while its switch is off. Before 3, no
  part: each sub-page keeps its whole section. Several owners' top switches
  are named "Enable" on their own pages (DBR procs and chimes, DDT dots and
  control); the names on WTF's top page are the owners'.
- WTF's own rows are greyed only while the switch that controls their feature
  is off. Stones (`stones.enabled`) gates the bar and the reminders: "Show the
  Stones bar", its size, and both reminders get `AddModifyPredicate`; "Keep
  stone macros" does not (the macros work without the bar). Announce
  (`announce.enabled`): the canvas page's checks, edit boxes, and channel
  radios are `SetEnabled(false)` with grey labels, read on each `OnRefresh`
  (the switch is on the top page). Soul Shard management (`shards.enabled`)
  only turns automatic deletion off; the limit, the report, and the counter
  still serve the right-click trim, so no Soul Shards row greys.
- Before 1.13.0, or with an older toolkit: the Shield display, Chimes, Procs,
  and Reminders pages are links, not
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

### Moved to Dyre's Debuff Tracker in 1.11.0 (John, 2026-11-20)

John: "Users of WTF should manage their DoT tracking features in DDT. The WTF
DoT's settings pages should simply redirect users to DDT, where everything is
now maintained and up to date. This includes DoT Colors, tracker panels,
etc." Then: "Yes, full move". Lead (same day): the smart curse moves too (DDT
adds it first; WTF 1.11.0 ships only after that DDT release, 24 h after it),
and the "! Fear", "! Banish", and "! Seduction" macros and the crowd-control
announcements go with the Control bar (the 2026-10-30 decision).

- Gone from WTF: Tracker.lua (the DoT tracker, the smart curse button and
  "! Curse"), Dots.lua (nameplate DoT dots), Predict.lua (DoT damage
  prediction), Control.lua (the Control bar, Focus box, Fear plate timers,
  the control macros and announcements), the smart curse button, their settings,
  the main page's DoT tracker and Control bar switches, the Announce page's
  Fear, Banish, Enslave Demon, and Howl of Terror rows, and `/wtf
  debug_tracker`, `debug_predict`, `debug_control`, and `reset_focus`. WTF
  claims no Toolkit owner kind, so Dyre's Debuff Tracker (priority 5) owns
  them. Do not bring any of them back: changes go to DDT or the Toolkit
  through the coordinator. Before 1.11.0 these were Dyre's Toolkit 2.5.0's
  engines (DotTracker.lua, PlateDots.lua, DotPredict.lua, Control.lua) with
  WTF's glue; their spec is in the Toolkit and DDT.
- Saved data stays exactly as the last login before 1.11.0 left it, for DDT
  to copy once (it never writes it) and for a downgrade: `db.tracker`,
  `db.predict`, `db.control` (`WTF.DDT_TABLES`), the eight crowd-control keys
  in `db.announce` (`WTF.DDT_ANNOUNCE_KEYS`: `fearGroup`, `banishGroup`,
  `enslaveGroup`, `howlGroup` and each `...Text`), and
  `WarlockToolsForeverAccountDB.ticks`. `SanitizeDB` neither repairs nor
  writes them (no lock flags), and never adds them to a new character;
  `announce.enabled` and `announce.channel` stay WTF's, live. Never delete or
  rename these keys without the DDT session's agreement. The full key list
  went to DDT in the shared notes (wtf-1.11.0-ddt-import-keys.md); a test
  checks the tables are the same and unrepaired.
- Profile: `tracker`, `predict`, and `control` are
  `characterKeys`; the eight announce keys are live state that
  `SanitizeProfile` puts back from this character, so a copy or import never
  changes them.
- The DoT Tracker, DoTs, and Control pages keep their names and places
  (after Stones, before Announce); each is one `AddSettingsLink` to
  `DyresDebuffTracker` ("Open Debuff Tracker settings", which opens it through
  the `openSettings` it joined the Toolkit with; greyed while missing, and a
  click then says "Install Dyre's Debuff Tracker from CurseForge for ...").
  Without the helper, one greyed note says where it went. The tooltip says
  "Opens Dyre's Debuff Tracker's settings for <features>." (player words,
  2026-11-27: no WTF versions or move history in what players read; the
  notes say "<name> (in <owner>)" and "Install <owner> from CurseForge for ...").
- Tooltips (John, 2026-11-27: "every one of the tooltips seems to start with a
  good one sentence description, but then has nonsensical follow-on text"):
  one plain sentence that says what the setting does; a second only when a
  player would lose something without it ("Turning this off deletes them.",
  "Shards you move into your bags are never deleted."). No how-to tips,
  commands, combat timing, defaults, or history. A test checks every setting
  tooltip (at most two sentences, 160 characters, no /wtf). The Stones
  buttons' tooltips show only the click hints. Primers may be a short
  paragraph.
- One chat line only (lead, as MTF): DDT says in chat what it copied, so WTF
  says nothing of its own about the move; without DDT, only
  `ReportMovedFeatures`' install (or enable) line. A 1.11.0 test build saved
  `db.ddtNotice` on John's test characters; nothing reads it.
- Bindings.xml stays one release as a shim (lead-approved, 2026-11-20): it
  defines only `CLICK WarlockToolsForeverSmartCurse:LeftButton` (header and
  label "Smart curse (moved to Dyre's Debuff Tracker)" from Core.lua), with
  no button behind it, so the game keeps a player's key until DDT moves it
  to `CLICK DyresDebuffTrackerSmartCurse:LeftButton` (also when both update
  at once; whether the client keeps a key for an undefined command is not
  verified). Never create the button again. docs/RELEASE_PLAN.md says when
  and how to remove it; a test checks the one binding and no button. Its
  `category` is "Dyre's AddOns" (1.13.0; John: ours "should not be there" in
  the AddOns section; Keybindings.lua 189-229: a category makes the
  collapsible section, a header only a blank gap), as Toolkit 2.16.0's tank
  bindings; keys are saved by binding name, so a bound key stays.
- `SHARED_FUNCTIONS` is only `FormatAnnouncement` and `NoteFocusWorks`
  (Announce.lua's fill, and the focusWorks hand-over); without them WTF uses
  its own fill and keeps its own flag, with no chat line.

### Soul Shards (built)

- Shard counter (author-approved, inspired by Pentacle): an unnamed plain
  frame (not secure, so it updates and moves in combat) with the Soul Shard
  icon and the carried count, outlined: green at or above the limit, red at
  or below the Low shard warning setting (0-10, default 2, author's choice),
  white between. "Shard counter size" (`shards.counterScale`, percent 50-150,
  step 5, default 100; John, 2026-11-12, from a player comment) scales it,
  keeping its center (`ScaleKeepingCenter`, which saves the place); a plain
  frame, so also in combat. The scale is set before the saved place.
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
  before it), each gain with the keep count after it, and `inInstance` and
  `instanceKeep`.
- Instances (John, 2026-11-15, after a player in Orgrimmar kept 22 shards over
  a limit of 16, with no gain logged since login: "if the user leaves a
  dungeon, let's check their shard count and trim it to the max set number"):
  on `PLAYER_ENTERING_WORLD` inside an instance (`IsInInstance()`), the keep
  count is saved per character as `shards.instanceKeep` (once; a `/reload` or
  relog inside keeps the saved value), and each drop inside lowers it to the
  count. On `PLAYER_ENTERING_WORLD` outside, the keep count goes down to it and
  it is cleared, so shards gained inside go on the next inputs, down to the
  limit, whatever kept them (a reload inside resets the keep count to the
  count; not confirmed which cause the players hit). Shards brought in stay
  (John's raid case: bank shards for a raid). A shard traded inside is
  trimmed too (no bank or mail inside). With deletion off or stopped, nothing
  is saved and the value is cleared, so turning it on deletes nothing.
  Repaired on load (`WTF.SanitizeInstanceKeep`: a whole number 0-1000, else
  nil).
- Trim on request (1.12.0; John, 2026-11-21: "Yes, build it"; Wrathetic on
  CurseForge asked to free bag space in dungeons): a right-click on the shard
  counter (`OnMouseUp` with "RightButton" on the plain frame; the left button
  still drags) calls `WTF.TrimShards`. With none above the limit, one line and
  nothing else; with deletion stopped (`state.blocked`), one line that says so
  and nothing else. Otherwise the keep count becomes the limit (so `KeepNow()`
  is the limit; also shards brought in, because the player asked), a saved
  `shards.instanceKeep` goes down to the limit (leaving the instance raises
  nothing), and `state.trimming` lets `ProcessDeletions` run with
  `shards.enabled` off. Out of a restriction, one line ("Deleting N Soul
  Shards above your limit of L, one per key press or click.") and the first
  deletion in the click itself (a hardware event; `DeleteOne` and
  `DeletionSlot` with every check); the rest on the next inputs through the
  input hooks, one per input, with the settle wait. While `WTF.MoveRestricted()`
  is true, one line ("Soul Shards above your limit go after combat.") and no
  pickup; the shards go on the first inputs after it. No event-driven delete,
  no polling, no popup. While trimming, a rise raises the keep count by its own
  amount (not to the count), so the trim still ends at the limit and new
  shards stay (deletion off) or follow the usual rule (deletion on, created
  ones go); the trim ends when the count reaches the keep count. Whether a
  right-click on a plain frame allows `DeleteCursorItem` is not confirmed in
  client (TESTING.md); if not, the first shard goes on the next input.
- Trim under Map (1.12.2; John: "Try delete under Map"; Wrathetic, Shadowfang
  Keep, out of combat: every right-click said "go after combat"). Core splits
  `WTF.HardRestricted()` (combat, affecting combat true or secret, Combat,
  Encounter, ChallengeMode, PvPMatch) from `WTF.MapRestricted()` (Map; a
  dungeon may set it for the whole visit). `WTF.MoveRestricted()` is both, as
  before, for the Healthstone trade. `DeletionRestricted`
  is hard, or Map unless a trim runs and Map has not refused this visit, so
  automatic deletion waits under Map as before. A right-click under a hard
  restriction says "go after combat" and picks up nothing. Under Map alone it
  tries with every check; `state.mapResult` remembers "allowed" (the trim goes
  on with inputs under Map) or "refused" (the client refused the pickup or the
  delete: cursor still full, or `ADDON_ACTION_BLOCKED`/`FORBIDDEN` for WTF
  during either). On a refusal the shard goes back, no permanent stop
  (`state.blocked` stays false), one line ("The game does not let AddOns delete
  items in this dungeon. Shards above your limit go when you leave it."), and
  no more tries this visit: later right-clicks say that line, not the combat
  line, and pick up nothing. The trim already set the keep count and a saved
  `instanceKeep` to the limit, and `state.trimming` stays on, so the shards go
  on the first inputs after leaving, also with deletion off (tested; a
  `/reload` inside clears the in-memory trim, and then only a saved
  `instanceKeep`, deletion on, trims on leaving). `state.mapResult` clears on
  every PLAYER_ENTERING_WORLD. `/wtf debug_shards` shows `hard`, `map`, and
  `mapResult`. Whether Map blocks `DeleteCursorItem` is not confirmed in client.

### Stones (built)

- A movable bar (`WarlockToolsForeverStones`, gold border, brown background;
  "Stones bar size", `stones.scale`, percent 50-150, step 5, default 100, John,
  2026-11-12: scaled keeping its center, out of combat only, as its secure
  buttons make it protected; a change in combat waits for
  `PLAYER_REGEN_ENABLED`; the scale is set before the saved place)
  with two `SecureActionButtonTemplate` buttons, `WarlockToolsForeverSoulstone`
  (a Dyre's Toolkit widget with Toolkit 2.18.0, see below)
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
  within a friendly target's level. Soulstones are not downranked: a Warlock
  can carry only one Soulstone in total, of any rank (John, 2026-11-27: "you
  can't carry more than one of any rank. they don't work like healthstones").
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
- Never a whisper to yourself (1.13.0; John, 2026-11-27: a Soulstone on
  himself, "Locus Stormshadow", was whispered to him and shown as sent and
  received). Announce.lua's SendChat drops every WHISPER whose target
  `IsSelfName` says is you: "First", "First-Last", or "First Last" (spaces
  and hyphens ignored), first name equal to UnitName("player")'s; with a last
  name, it must match UnitName's second value or UnitFullName's (which can be
  the realm), unless neither gives one. Secret names are never you. The cast
  target check (`IsSelf`) uses the same function.
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

### Dyre's Toolkit Profile (built, unreleased; John, 2026-11-17)

John: "start working on the global "all Dyre addons settings" syncing with
DT's profile, so there is one place to go to persist your profile." The
Toolkit owns the profile (docs/PROFILES.md in DyresToolkit, 2.10.0): one per
character, no switching, copy from another character or the Defaults,
export and import as text; WTF keeps its live settings in
WarlockToolsForeverDB, with no per-AddOn Profile section.

- Core registers once at PLAYER_LOGIN, after `UseToolkit` and before the
  modules build their frames (`RegisterProfilePart`, `WTF.profileRegistered`),
  only when the toolkit has `RegisterProfilePart`; the minimum toolkit stays.
  `current` is `WTF.db`; `sanitize` is `WTF.SanitizeProfile` (any table to a
  full, repaired one through `WTF.SanitizeDB`; never errors).
- In the profile: every setting in `shards`, `stones`, `announce` (but the
  crowd-control keys), and `grid`.
- `characterKeys` (top-level, never copied, exported, or imported):
  `locked` (a copy of the toolkit's account-wide lock, set at login);
  `shield`, `chimes`, `alerts`, `reminders` (old WTF data that Dyre's Shields
  Up and Dyre's Buff Reminders copy once per character); `tracker`,
  `predict`, `control` (the same for Dyre's Debuff Tracker, 1.11.0). WTF
  saves no macro names (they are fixed).
  WarlockToolsForeverAccountDB (focusWorks, learned ticks) is account-wide,
  so it is not registered.
- Live state nested in settings tables: the engine skips only top-level keys,
  so `SanitizeProfile` puts this character's live values back on every copy,
  import, and Defaults: `shards.instanceKeep`, `stones.soulstone`, and the
  eight crowd-control announce keys. They still appear in this character's
  saved copy and an export line, but never take effect elsewhere.
- `refresh` is `WTF.ApplyProfile` (no reload): the shard counter's scale,
  then place (`ApplyShardsProfile`); the Stones bar's scale, then place, out
  of combat (`ApplyStonesProfile`; in combat, at `PLAYER_REGEN_ENABLED`), and
  its macros; the grid. A copy is refused in combat by the toolkit.

### Stones bar as a Toolkit widget (1.14.0; John, 2026-11-27; lead-approved B)

A CurseForge player on MTF asked for vertical bars; John made horizontal and
vertical button bars a Toolkit feature (Toolkit 2.18.0, `BAR_LAYOUT_VERSION`
1), and the family plan (2026-10-20: "all the widget layout, snapping,
modifier key move rules, etc., centralized in Dyre's Tools") makes every
Dyre's frame a Toolkit widget.

- With the feature (`CreateWidget`, `AddBarLayoutSetting`, and
  `BAR_LAYOUT_VERSION` >= 1), `InitializeStones` makes the bar a widget:
  `CreateWidget{addon, key = "stones", title = "Stones", frame = bar, store =
  db.stones, width = 90, height = 48, point = DEFAULT_POINT, mouse =
  "always", keys = {position = "position", scale = "scale"}, sizes = {scale =
  50-150 step 5, default 100}}`, then `widget:LayoutButtons({soulstone,
  healthstone}, {size = 36, gap = 6, padding = 6})`. The saved place is the
  same shape the toolkit reads ({point, relativePoint, x, y} from UIParent,
  the center from BOTTOMLEFT after a drag), and the toolkit sets the scale
  before the place, as WTF did: an old save loads in the same place with no
  conversion and no move of saved data (tested against WTF's own path).
- `stones.orientation`: "vertical", else nil (the toolkit's form), repaired
  in SanitizeDB, in the profile part. The Stones page's "Layout" row is
  `AddBarLayoutSetting(page, nil, widget, {modify = StonesOn})`, under "Show
  the Stones bar" as the size is; only on the widget path.
- On the widget path: "Stones bar size" calls `widget:SetSetting("scale")`,
  `/wtf reset` `widget:ResetPosition()`, the profile refresh
  `ReapplyWidgets(addonName)` then the layout again (the saved center first,
  then the size from that center). The toolkit owns the outline, mouse,
  drag, snap, Ctrl and Shift rules, and the combat wait; `RefreshStonesMover`
  does nothing (no WTF outline). WTF has no "Reset size" button; the size's
  default mark gives 100%.
- Without it (no toolkit, or one before 2.18.0): WTF's own frame exactly as
  before (Layout.lua or the toolkit's RegisterMovable, `WTF.CreateMover`),
  no Layout row.
- Tests load the toolkit's real Layout.lua and Widgets.lua (`options.widgets`;
  tests/toolkit holds copies for CI).

### Macro text (author-approved)

- Every macro and click macrotext WTF writes uses `/use`, not `/cast` (every
  letter counts): the pinned SlashCommands.lua `/use` handler tries an item
  (SecureCmdItemParse, C_Item.GetItemInfo(name)), else CastSpellByName, so
  it casts spells. No spell WTF names is an item's name; a new spell whose
  name is also an item's keeps `/cast` on its line. Since 1.11.0 WTF writes
  only "! Healthstone" and "! Soulstone"; the control macros and "! Curse"
  are Dyre's Debuff Tracker's.

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

### Lock and unlock (built)

- One lock for every WTF frame (author-approved, as MTF): `db.locked`,
  default locked, copied to `stones.locked` and `shards.counterLocked` (never
  to the saved `tracker`, kept for Dyre's Debuff Tracker). The main
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

- Runtime files: WarlockToolsForever.toc, Commands.lua, Core.lua, Layout.lua, Shards.lua, Stones.lua, Announce.lua, Probe.lua, Options.lua, loaded in
  that order. Core also owns the hardware-input hooks
  (every key press and world click) that item deletion and trade placement
  wait for.
  Commands parses `/wtf`; Core owns saved settings and their defaults, the
  login banner (hidden, with its ready line, when Dyre's Toolkit 2.14.0's
  `ShowWelcome()` returns false; John, 2026-11-23: "A: one Toolkit switch";
  errors and problems always show; no WTF switch), class and install checks,
  slash conflict reporting, and startup, and the moved-feature lines; Layout owns snapping; Shards, Stones,
  and Announce own their modules; Probe owns
  `/wtf debug_restrictions`; Options owns the settings pages.
- tests/run.lua loads Dyre's Toolkit's shared files and engines (TOOLKIT_FILES,
  in its TOC order, sharing one namespace; since 1.11.0 WTF calls only the
  announcement fill, the focus flag, the settings link, and the profile) from
  ../DyresToolkit when that
  folder exists, else (as in
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
  saved variables, and the Stones bar and buttons), prefixed
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
- Package only WarlockToolsForever.toc, Commands.lua, Core.lua, Layout.lua, Shards.lua, Stones.lua, Announce.lua, Probe.lua, Options.lua, Bindings.xml (the 1.11.0 shim), and LICENSE
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
