# Verification and test plan

This document describes how Warlock Tools Forever is verified: the runtime
contract under test, the pinned client-source evidence behind design decisions,
the automated test method, and the in-client checklist.

## Verification approach

1. **Pinned source review.** Client behavior is read from Blizzard's FrameXML
   and generated API documentation at Gethe/wow-ui-source commit
   `943764493e6b16d63ded3ab304150d1f05e58b57` (`1.60.1.70338`; the client is
   tested on build 70450, with the same Interface 16001). Source
   establishes declared APIs, templates, and code paths, not operational behavior.
2. **Automated mock tests.** `tests/run.lua` exercises commands, saved settings,
   the shard limit and deletion rules, diagnostics, and the settings pages
   against minimal WoW API mocks under Lua 5.1. Python unit tests cover the
   release helpers. Mocks cannot establish protected-action rules, secret-value
   behavior, layout, or taint.
3. **In-client checks.** The checklist below covers everything mocks cannot.
   Client observations that contradict a mock assumption take precedence; fix
   the mock and add a regression test that encodes the observed behavior.

## Runtime contract

- Core requires the Warlock class (`UnitClass` file name `WARLOCK`) and the
  shard APIs: `C_Container.GetContainerNumSlots`, `GetContainerNumFreeSlots`,
  `GetContainerItemInfo`, `PickupContainerItem`, `SplitContainerItem`,
  `GetCursorInfo`, `ClearCursor`, `DeleteCursorItem`, `GetTime`,
  `InCombatLockdown`, `C_Spell.GetSpellName`, and `NUM_BAG_SLOTS`. It does not
  check the client version or build.
- At `PLAYER_LOGIN`, Core checks that every runtime file is from the same
  version, the class, and the APIs; prints one banner; reports another AddOn's
  `/wtf` registration once; then calls `WTF.InitializeShards` and
  `WTF.InitializeOptions` directly, so startup never depends on event order.
- Shards counts carried shards on `BAG_UPDATE_DELAYED` and keeps a keep
  count: the count at login, raised to the count by rises outside a creation
  window, raised only up to the limit by rises inside one, and lowered by
  drops (a shard moved to another slot changes nothing). On a key press or
  world click, while the count is above the limit and the keep count, one
  shard is deleted; the next waits for a bag scan that shows it (2 s at most).
- Stones requires `C_SpellBook.IsSpellKnown`, `C_Item.GetItemCount`, and
  `C_Item.GetItemInfo`; without them Stones stays off with one message and the
  rest of WTF runs. Secure attributes and bar visibility change only out of
  combat, else at `PLAYER_REGEN_ENABLED`.
- Announce pairs `UNIT_SPELLCAST_SENT` (target name, cast GUID) with
  `UNIT_SPELLCAST_SUCCEEDED` and sends with `C_ChatInfo.SendChatMessage`.
- Options registers a vertical-layout category with proxy settings, plus a
  canvas Announce subpage, when the Settings API exists; without it, WTF runs
  and `/wtf` says the page is unavailable.

## Pinned source evidence

- `RestrictedActionsDocumentation.lua` and `RestrictedActionsConstantsDocumentation.lua`
  define `C_RestrictedActions.GetAddOnRestrictionState`, `IsAddOnRestrictionActive`,
  `ADDON_RESTRICTION_STATE_CHANGED`, and `Enum.AddOnRestrictionType` (Combat,
  Encounter, ChallengeMode, PvPMatch, Map, Chat) with states Inactive,
  Activating, and Active.
- `CombatLogDocumentation.lua` marks `COMBAT_LOG_EVENT_UNFILTERED` with
  `HasRestrictions` and declares `C_CombatLog.IsCombatLogRestricted`.
- `UnitAuraDocumentation.lua` marks `C_UnitAuras.GetAuraDataByIndex`
  `SecretWhenUnitAuraRestricted`; `UnitDocumentation.lua` marks `UnitName`,
  `UnitGUID`, `UnitIsUnit`, `UnitChannelInfo`, and the `UNIT_SPELLCAST_*`
  events with `SecretWhen...` flags.
- `ChatInfoDocumentation.lua` marks `SendChatMessage` `HasRestrictions` and
  `RestrictedForMacroChatMessages`.
- `ContainerDocumentation.lua` documents the container functions above,
  `ContainerItemInfo` (`itemID`, `stackCount`, `isLocked`), and the
  `BAG_UPDATE_DELAYED` and `ITEM_LOCK_CHANGED` events.
- `Blizzard_FrameXMLBase/Constants.lua` defines `NUM_BAG_SLOTS`.
- `Blizzard_StaticPopup_Game/GameDialogDefs.lua` calls `DeleteCursorItem()`
  from the delete-item dialogs; the generated documentation does not list it,
  `GetCursorInfo`, or `ClearCursor`.
- `Blizzard_Settings_Shared/Blizzard_Settings.lua` defines
  `RegisterVerticalLayoutCategory`, `RegisterVerticalLayoutSubcategory`,
  `RegisterProxySetting`, `CreateCheckbox`, `CreateSlider`,
  `CreateSliderOptions`, `NotifyUpdate`, `RegisterAddOnCategory`, and
  `OpenToCategory`; `Blizzard_SettingControls.lua` defines
  `SetParentInitializer`; `MinimalSlider.lua` defines
  `MinimalSliderWithSteppersMixin.Label`.
- `Blizzard_FrameXML/SecureTemplates.lua` defines the secure action types
  `spell`, `item`, and `macro` (`macrotext`) and `SecureActionButton_OnClick`,
  which acts once per press and release, on the press only when
  `useOnKeyDown` or the `ActionButtonUseKeyDown` CVar says so.
- `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml` defines
  `InputBoxTemplate`; `CheckButtonTemplates.xml` defines `UIRadioButtonTemplate`.
- `Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua` defines
  `AddAuraSlot`, `SetAuraSlotCandidateFilters`, and `includeSpellIDs` matching,
  which "is only permitted for helpful buffs on assistable units, and harmful
  buffs on non-assistable units". `Blizzard_CustomAuraButton.lua` defines
  `SetIcon`, `SetDurationCooldown`, `SetDurationText`, and `SetDurationBar`
  (`StatusBar:SetTimerDuration` with a `StatusBarTimerDirection`).
  `Blizzard_AuraContainerShared.lua` applies
  `DenyTaintedAccessWhenAurasAreSecret` to AddOn access after `initializeFrame`.
- Installed EllesmereUI (`EllesmereUI_AuraKit.lua`,
  `EUI_Nameplates_AuraContainers.lua`) and ThreatPlates
  (`Widgets/AurasWidgetMidnight.lua`) show the player's debuffs on enemy
  nameplates in combat through these containers, with
  `HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY` filters and `includeSpellIDs` slots.
- Installed TankHelper (`core.lua`) attaches its nameplate threat display on
  `NAME_PLATE_UNIT_ADDED` through `C_NamePlate.GetNamePlateForUnit`, skipping
  plates where `IsForbidden()` is true.
- `SpellBookDocumentation.lua` declares `C_SpellBook.IsSpellKnown`;
  `ItemDocumentation.lua` declares `C_Item.GetItemInfo` (with `itemMinLevel`),
  `GetItemCount`, `GetItemIconByID`, and `GetItemNameByID`;
  `ChatInfoDocumentation.lua` declares `C_ChatInfo.SendChatMessage`.

### Client observations

- Out of combat in the open world, every `Enum.AddOnRestrictionType` state is
  inactive, yet `C_CombatLog.IsCombatLogRestricted()` is true and
  `issecretvalue` exists. Registering `COMBAT_LOG_EVENT_UNFILTERED` fails and
  raises `ADDON_ACTION_BLOCKED` for the AddOn with function `UNKNOWN()`. The
  combat log is therefore never available to WTF; the probe no longer
  registers it, and Shards counts blocked-action events only while a deletion
  is under way.
- Soul Shards are item 6265, a "Reagent" (class 15). They go to the reagent bag
  until it is full, then to other bags. Scanning only bags 0 to `NUM_BAG_SLOTS`
  found none; Shards now scans to `NUM_TOTAL_EQUIPPED_BAG_SLOTS`. The tested
  character had a 14-slot soul bag (family 4) in the reagent slot, bag 5.
- A Drain Soul kill created a shard in combat (`created=true combat=true`);
  `DeleteCursorItem` then raised `ADDON_ACTION_BLOCKED` (`UNKNOWN()`), the
  shard went back to its bag, and deletion stopped. Out of combat, the same
  delete from a bag event was blocked too: `DeleteCursorItem` needs a
  hardware event. RestedXP (`RXPGuides/InventoryManager.lua`) deletes junk,
  including Soul Shards, from hooks on every key press (a keyboard frame that
  propagates input) and world click; EllesmereUI's junk deletion notes the
  same hardware-event rule. Shards now deletes from the same kind of hooks,
  and in client a Drain Soul shard above the limit was deleted on the next
  key press.
- Ritual of Summoning's `UNIT_SPELLCAST_SENT`, `START`, `CHANNEL_START`, and
  `SUCCEEDED` events carry no target name; the party line went out from the
  friendly-target fallback.
- Every Forever character has a first and a last name ("Meatrod Theog").
  `UnitName` returns the last name as its second value, where other clients
  return the realm. A whisper to the first name alone failed ("No player
  named ... is currently playing"); a whisper to `First-Last` reached the
  player. A Soulstone on yourself was whispered to you, because the cast
  named you `First-Last`; the self check compares with `UnitFullName("player")`.
- `/click WarlockToolsForeverHealthstone` did nothing: the client's `/click`
  (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua`) calls
  `button:Click(mouseButton, false)`, a release only, and
  `SecureActionButton_OnClick` acts on the press while `ActionButtonUseKeyDown`
  is on. WTF's secure buttons set `useOnKeyDown` to false, as RestedXP does,
  yet `/click` macros still did nothing, for any AddOn button: on Forever
  `/click` does not press AddOn buttons. WTF writes stone macros with the
  game's own `/use` instead (it casts spells too), as Consumable Connoisseur
  does.
- The Healthstone gift whisper went out as the trade window opened, and the
  Soulstone whisper reached the target.
- An emote sent from Create Soulstone's `UNIT_SPELLCAST_SUCCEEDED` was
  blocked ("The game blocked the emote message"), so emotes wait for the next
  key press or click. `/wtf debug_emote` found an emote from a timer blocked
  through both `C_ChatInfo.SendChatMessage` and the global
  `SendChatMessage`, although RestedXP's solo level-up emote, sent with the
  global from `PLAYER_LEVEL_UP`, goes out. The queued emote went out on the
  next key press (moving) and on a world click.
- A Soulstone applied to a friendly player outside your group, as before
  patch 2.1.0, which added the group requirement on other clients.
- From the Healthstone button's PostClick, `InitiateTrade("target")` opened
  a trade and `ClickTradeButton` from `TRADE_SHOW` placed the stone in the
  window.
- `C_NamePlate.GetNamePlates()` frames have no `namePlateUnitToken` field; the
  probe finds nameplate units by testing `nameplate1` to `nameplate40`.
- In open-world combat, the Combat restriction is active and the others stay
  inactive. A hostile target's `UnitName` and `UnitGUID` stay readable, but
  `C_UnitAuras.GetAuraDataByIndex` raises "Auras cannot be accessed when secret
  while tainted" for AddOn code and taints it. `GetUnitAuraInstanceIDs` and
  `GetUnitAuras` raise the same error, on the target and on nameplate units, so
  AddOn code cannot read any aura in combat.
- In combat, the player's own `UNIT_SPELLCAST_SENT` (target name) and
  `UNIT_SPELLCAST_SUCCEEDED` (spell ID) stay readable: Corruption 6222 and
  Drain Life 699, the Classic spell IDs. Nameplate units and their GUIDs are
  readable too.

### Open client questions

1. Restrictions in instances and during encounters.
2. Forever's Soulstone duration (30 minutes in Classic) and Shadow Trance spell
    ID (17941 in Classic).
3. Whether `DeleteCursorItem` from a key press or world click works in combat
   (RestedXP's users report deletion in and out of combat).
4. Whether shards stack.
5. Whether Shadowburn's shard arrives within its 9-second window, and whether
   any other source creates shards (the gain log). Forever's spell list and
   talents (wowhandbook.com, talentsforever.com) name Shadowburn's shard.
6. Whether the `INV_Misc_Gem_Amethyst_02` TOC icon and the `INV_Misc_Orb_04`
   and `INV_Stone_04` fallback stone icons render.
7. Forever's Create Soulstone and Create Healthstone spell IDs, stone item IDs,
   and Healthstone level requirements (`/wtf debug_stones`); the tables hold
   Classic's IDs.
8. Whether Say from a cast event is blocked outdoors, and which actions block
   accepting a summon (flying, trading, combat, death).

## Automated tests

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Core.lua Layout.lua Shards.lua Stones.lua Announce.lua Probe.lua Options.lua tests/run.lua
.tools/python-3.13.7/python.exe -m unittest discover -s tests -p 'test_*.py'
```

Mocks follow the client's quirks: APIs that return no value return no value in
mocks, and secret values raise errors on comparison, concatenation, indexing,
and printing.

## In-client checklist

- [ ] Login on a Warlock prints `WTF: Warlock Tools Forever <version> by Dyre`
      and the ready hint; another class gets one "for Warlocks" line.
- [ ] `/wtf` opens Options > AddOns > Warlock Tools Forever with the Soul Shard
      switch, and the Soul Shards subpage shows the match, limit, and report
      settings. The limit slider is disabled while matching the soul bag size.
- [ ] `/wtf debug_shards` shows the shard item name, Drain Soul's name, each
      bag's size and family, and the soul bag flag on the soul bag.
- [ ] `/wtf debug_restrictions` out of combat, then in combat with your DoTs on
      a target: record the states, combat log result, and which fields are secret.
- [ ] With a low manual limit (for example 2), finish a single mob with Drain
      Soul: the new shard is deleted, one chat line, no popup. Drain Soul is a
      combat spell, so the shard may arrive just before or just after combat
      ends; `debug_shards` shows when it arrived.
- [ ] Finish one mob with Drain Soul while another mob still attacks you, so
      the shard arrives in combat: nothing is picked up or deleted in
      combat, and it goes on the first key press after combat. In a dungeon
      boss fight (Encounter restriction) the same: no ADDON_ACTION_BLOCKED in
      BugGrabber, and `/wtf debug_shards` shows `restricted=true` and a
      recent `held=` during the fight.
- [ ] Enter a dungeon at your limit (`debug_shards`: `inInstance=true
      instanceKeep=` your count). Get a few shards above your limit inside and
      `/reload` there. Leave: the extra shards go on your next key presses,
      one chat line each, down to your limit, and `instanceKeep=nil`. Then
      bring bank shards above your limit into a dungeon, use one, and leave:
      those stay, less the one used.
- [ ] Typing in chat, movement keys, and key bindings all still work with WTF
      loaded (the key hook passes every key on).
- [ ] Right-click trim (1.12.0), out of combat: move 3 shards in from the bank
      above your limit; the counter's tooltip says "Right-click: delete shards
      above your limit (3)". Right-click the counter: one chat line, and one
      shard goes in the click itself (this checks that a right-click on a
      plain frame lets `DeleteCursorItem` run; if not, no
      ADDON_ACTION_BLOCKED and the first goes on the next key press). The
      other two go on your next key presses or clicks, down to the limit. A
      left-drag still moves the counter. In combat: the click says they go
      after combat and nothing is picked up; after combat, the first key
      presses delete them. Inside a dungeon, and with "Soul Shard
      management" off: the same, and with it off a Drain Soul shard after
      the trim stays. With none above the limit: one line, nothing deleted.
- [ ] The shard counter shows your count, red at or below the Low shard warning and
      green at your limit, legible on the icon; it
      updates as shards come and go, also in combat. Drag (unlocked), hide, and
      `/wtf reset` it; its place survives `/reload`.
- [ ] Move shards from the bank above the limit: none are deleted. Then Drain
      Soul once: only the new shard is deleted.
- [ ] With a full soul bag (so new shards land in an ordinary bag), finish two
      mobs with Drain Soul, also with the second in combat: each new shard is
      deleted from the ordinary bag on a key press (in combat, or on the first
      key press after combat), and `/wtf debug_shards` shows `blocked=false`
      and `lastAttempt=deleted`. If deletion stops, the red warning and
      `debug_shards` (`stopped=`, `lastAttempt=`) name why.
- [ ] With a full soul bag, a long Drain Soul that creates two shards on one
      kill: both are deleted (two "Deleted a Soul Shard" lines, one per key
      press or click), and `/wtf shards` shows your limit. `/wtf debug_shards`
      lists both as "deleted ... count=16 keep=14 limit=14" and "count=15".
- [ ] Carry 16 shards with a 14 limit by moving 2 in from the bank: none are
      deleted (`keep=16`). Use a shard (for example create a Healthstone):
      `keep=15`. Lower the manual limit: nothing is deleted.
- [ ] Move a shard between bags while Drain Soul channels: nothing is deleted
      and `debug_shards` logs no gain for it.
- [ ] Hold an item on the cursor while a shard is created: nothing is deleted
      until the cursor is empty, and the held item is never deleted.
- [ ] `/wtf shards` matches the bag contents; settings survive `/reload` and
      relogging, and are separate on a second Warlock.
- [ ] The Stones bar shows both buttons with counts; tooltips explain both
      clicks. Left-click a Soulstone with a friend targeted, then with no
      target; right-click creates your best rank. In combat a Soulstone click
      prints the combat line once.
- [ ] With a lower-level friend targeted, right-click on the Healthstone button
      creates a rank that friend can use; `/wtf debug_stones` agrees.
- [ ] "! Healthstone" and "! Soulstone" appear in your character macros
      with the stone's icon. On an action bar, left-click uses your best stone
      in combat; right-click creates one (the Healthstone one downranked when
      you carry the rank). They update after a stone is made or used, out of
      combat. Turning "Keep stone macros" off removes them.
- [ ] Middle-click on the Healthstone button uses your best Healthstone, also
      with a friendly player targeted.
- [ ] Drag (unlocked) and `/wtf reset` the bar; its place survives `/reload`.
- [ ] Ritual of Summoning on a party member: one party line and one whisper
      with the zone. A Soulstone on a party member: the party line and the
      author's whisper. On yourself: nothing. Default texts credit
      Warlock Tools Forever (WTF).
- [ ] Create a Healthstone outdoors, then press a key: one emote; a second
      within a minute stays quiet. The same for a Soulstone.
- [ ] The Announce page edits, Enter and Escape, switches, the Say choice, and
      Defaults work and survive `/reload`.
- [ ] Unlocked: the grid covers the screen under every frame, red lines
      cross at the center, clicks pass through it, it rebuilds after a UI
      scale change, and its switch hides it.
- [ ] Magnetic frames: a frame dropped near another snaps 20 apart, lined
      up by the nearest edge or center; Shift-drag moves a snapped group; not
      in combat.
- [ ] A failed stone click shows in red at the top of the screen as well as
      in chat.
- [ ] Moved features (1.3.0), with Dyre's Shields Up and Dyre's Buff
      Reminders enabled: no "moved there from WTF" line at login. The shield
      display shows once, from Dyre's Shields Up, with the scale, number, and
      place you had in WTF (its first run on this character); Cooldown
      chimes, the Nightfall sound, and the Demon Armor icon come from Dyre's
      Buff Reminders with your WTF choices; a Demon Armor icon click casts
      the armor you used last. WTF plays no sound and draws no shield or
      icon of its own.
- [ ] WTF's Shield, Cooldown Chimes, Alerts, and Demon Armor pages each show
      one button; it opens Dyre's Shields Up's or Dyre's Buff Reminders'
      settings out of combat. In combat a click says it opens out of combat.
- [ ] Nightfall owner (1.10.1): with an AddOn that plays Nightfall with proc
      arcs (Dyre's Toolkit 2.11 or later), the Alerts page shows one row,
      "Nightfall arcs and sound"; its tooltip names that AddOn, and its button
      opens that AddOn's page with its Procs rows (out of combat; in combat it
      says it opens out of combat). Disable that AddOn (or use one without
      proc arcs), `/reload`: the row is "Nightfall sound" and opens Dyre's
      Buff Reminders' Proc Sounds.
- [ ] Disable Dyre's Shields Up, then Dyre's Buff Reminders, in the AddOn
      list: at login one line each says to enable it, once per session;
      the Shield (or other) page's button is greyed out, and its tooltip
      says what to install. Delete one from the AddOns folder: the line says
      to install it from CurseForge. WTF's own modules work in every case.
- [ ] `/wtf debug_shield`, `/wtf debug_chimes`, and `/wtf debug_reminders`
      show the usage line (they moved with the features).
- [ ] Dyre's Debuff Tracker (1.11.0), on a Warlock that used the DoT tracker
      (or the Control bar) before: at the first login with 1.11.0, Dyre's
      Debuff Tracker says what it copied, and WTF says nothing about the
      move (one line only). WTF shows no DoT tracker, nameplate dots, block,
      Control bar, or Focus box of its own, and writes no "! Fear",
      "! Banish", "! Seduction", or "! Curse" (Dyre's Debuff Tracker keeps
      them). Key Bindings, Warlock Tools Forever: one row, "Smart curse
      (moved to Dyre's Debuff Tracker)"; a key on it does nothing. With
      WTF 1.10.x and DDT updated at the same time, a key you had on WTF's
      Smart curse is on Dyre's Debuff Tracker's after its first login.
- [ ] WTF's DoT Tracker, DoTs, and Control pages (after Stones) each show one
      button, "Open Debuff Tracker settings", that opens Dyre's Debuff
      Tracker's page (not in combat: it says so). Disable Dyre's Debuff
      Tracker: the button is greyed, its tooltip and a click say to install
      it from CurseForge, and at login one line says to enable it. The
      Announce page has no Fear, Banish, Enslave Demon, or Howl of Terror
      rows. `/wtf debug_tracker`, `/wtf debug_predict`, `/wtf debug_control`,
      and `/wtf reset_focus` show the usage line.
- [ ] Saved data (1.11.0): after a login with 1.11.0, WTF's saved
      `tracker`, `predict`, and `control` tables and the eight crowd-control
      announce keys in the character's SavedVariables\WarlockToolsForever.lua
      are the same as before the update;
      unlocking and locking do not change them.
- [ ] WTF 1.8.0, sizes (Forever, then Era): "Stones bar size" (Stones page)
      and "Shard counter size" (Soul Shards page) at 50% and 150%: each frame
      keeps its center, and its buttons and drag still work. After /reload
      each keeps its size and place. A Stones bar change in combat applies
      when combat ends, with no blocked-action error; the counter changes at
      once.
- [ ] WTF 1.7.1, Healthstone trade (Forever, then Era): with a friend targeted,
      left-click the Healthstone button. The stone goes in, or a key press
      puts it in, or the "drag it in yourself" warning shows; never nothing.
      `/wtf debug_stones` lists a `place <reason>` line for each try and
      `keyHook=true`.
- [ ] Every WTF macro works with `/use`: "! Healthstone" and
      "! Soulstone" (left-click uses, right-click creates the rank).
- [ ] "Unlock frames to move them" and `/wtf unlock` outline the Stones bar and
      the shard counter; both drag; unticking
      or `/wtf lock` locks them, and the switch and commands stay in step;
      `/wtf reset` puts them back; their places survive `/reload`.
- [ ] With Dyre's Toolkit enabled: no "Install Dyre's Toolkit" line at
      login; the AddOn list shows WTF in the Dyre's AddOns group; the
      settings show Dyre's AddOns > Warlock Tools Forever with WTF's pages
      under it, and no WTF unlock or grid switch on any WTF page; `/wtf` opens WTF's page (in combat it
      says it opens after combat). `/wtf unlock`, `/dyre unlock`, the minimap
      button, and the toolkit's Unlock frames switch each unlock every
      Dyre's AddOn's frames
      with one "Dyre:" chat line and no "WTF:" line; one grid shows (the
      toolkit's); a WTF frame dropped near another Dyre's AddOn's frame snaps
      to it; with Snap to the grid on, it snaps to the grid; Shift-drag moves
      a snapped group across AddOns; `/wtf lock` locks them all; places survive `/reload`;
      frames start locked after `/reload`. No taint in combat.
- [ ] Profile (Dyre's Toolkit 2.10.0 or later): on character A, change a few
      WTF settings (shard limit, Stones bar size and place, an announce
      text). On character B, open the Dyre's Toolkit page and
      copy A's profile: B's WTF frames and settings change at once, no reload
      popup, no Lua error; the Stones bar moves; an open
      WTF settings page shows the new values. B's Soulstone timer (`/wtf
      stones`) and `/wtf debug_shards` `instanceKeep` stay B's. Then export
      B's profile, change a setting, import the line: the setting comes back.
      Copy in combat: refused, nothing changes.
- [ ] Without Dyre's Toolkit (disable it): one chat line at login says to
      install it from CurseForge; WTF's own top-level page, unlock, and grid
      work as before; positions saved with the toolkit are kept.
- [ ] Target a lower-level party member and left-click the Healthstone button:
      with a stone they can use, a trade opens with it in the window; without
      one, it is created, and the next left-click trades it. WTF never accepts.
- [ ] In a dungeon during a boss fight (or in combat), the Healthstone trade:
      no ADDON_ACTION_BLOCKED; the stone goes in at the first key press after
      the restriction ends, or WTF says once to drag it in yourself.
- [ ] Soulstone a party member: `/wtf stones` names them; 30 minutes later a
      chat line says it ended. With no Soulstone up or no Healthstone, a
      reminder after a fight, at most every 10 minutes; the switches stop them.
- [ ] No Lua errors or taint warnings in or out of combat.
