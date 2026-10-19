# Verification and test plan

This document describes how Warlock Tools Forever is verified: the runtime
contract under test, the pinned client-source evidence behind design decisions,
the automated test method, and the in-client checklist.

## Verification approach

1. **Pinned source review.** Client behavior is read from Blizzard's FrameXML
   and generated API documentation at Gethe/wow-ui-source commit
   `943764493e6b16d63ded3ab304150d1f05e58b57` (`1.60.1.70338`). Source
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
- Shards scans carried bags on `BAG_UPDATE_DELAYED` and compares stack counts
  per slot with the previous scan. Gains inside a creation window queue
  deletions, at most the excess over the limit and at most the gained amount.
  `ITEM_LOCK_CHANGED` and `CURSOR_CHANGED` retry queued deletions.
- Stones requires `C_SpellBook.IsSpellKnown`, `C_Item.GetItemCount`, and
  `C_Item.GetItemInfo`; without them Stones stays off with one message and the
  rest of WTF runs. Secure attributes and bar visibility change only out of
  combat, else at `PLAYER_REGEN_ENABLED`.
- Tracker requires `C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")`
  after loading `Blizzard_AuraContainer`, and `C_Timer.After`; without them the
  tracker stays off with one message; it also needs `RegisterStateDriver`.
  Each row's container gets one
  `AddAuraSlot` per spell; WTF sets only the unit (`SetUnit`, then
  `UpdateAllAuras`) afterwards, and slot spell sets only out of combat.
- Dots need the tracker's spell sets and `C_NamePlate.GetNamePlateForUnit`;
  they attach to plates on `NAME_PLATE_UNIT_ADDED`, detach on
  `NAME_PLATE_UNIT_REMOVED`, and show only between `PLAYER_REGEN_DISABLED` and
  `PLAYER_REGEN_ENABLED` on live hostile units.
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
- In client the tracker and nameplate dots showed Corruption, Immolate, and a
  Bane in combat through engine slots, but not a curse (Curse of the Elements,
  4 minutes left on the nameplate): its debuff matched no listed spell ID. The
  Curse slot now matches Curse-type debuffs instead, as EllesmereUI's
  nameplates match `includeDispelTypes`.
- In client the nameplate dots lit for Curse (after the switch to debuff-type
  matching), Bane, and Corruption. With EllesmereUI plates, a dot height of
  4 covered the name and 40 the debuff icons; 50 cleared both and is the default.
- Ritual of Summoning's `UNIT_SPELLCAST_SENT`, `START`, `CHANNEL_START`, and
  `SUCCEEDED` events carry no target name; the party line went out from the
  friendly-target fallback.
- Every Forever character has a first and a last name ("Meatrod Theog").
  `UnitName` returns the last name as its second value, where other clients
  return the realm. A whisper to the first name alone failed ("No player
  named ... is currently playing"); a whisper to `First-Last` reached the
  player. A Soulstone on yourself was whispered to you, because the cast
  named you `First-Last`; the self check compares with `UnitFullName("player")`.
- The Bars theme rendered in client as designed: per-mob blocks with engine
  bars, spell names, and time left draining like the Cooldown Manager's.
- `/click WarlockToolsForeverHealthstone` did nothing: the client's `/click`
  (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua`) calls
  `button:Click(mouseButton, false)`, a release only, and
  `SecureActionButton_OnClick` acts on the press while `ActionButtonUseKeyDown`
  is on. WTF's secure buttons set `useOnKeyDown` to false, as RestedXP does,
  yet `/click` macros still did nothing, for any AddOn button: on Forever
  `/click` does not press AddOn buttons. WTF writes stone macros with the
  game's own `/use` and `/cast` instead, as Consumable Connoisseur does.
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
- The minimum-absorb gate (shield display v5) works: a frame anchored to a
  StatusBar's fill texture follows a secret value, and its clipping hides the
  crescent while the fill is empty. A Paladin's Seal of Righteousness shield
  no longer flickers the ring (confirmed on a Paladin).

### Open client questions

1. Restrictions in instances and during encounters.
2. Whether the tracker's engine slots show timers in combat with the
   `HARMFUL|PLAYER` filter (EllesmereUI adds `INCLUDE_NAME_PLATE_ONLY` on
   nameplates), whether Forever's Bane auras match by name-derived spell IDs
   (`/wtf debug_tracker`), whether Fear and control show, and whether `UnitIsDead` and
   `UNIT_HEALTH` stay readable for nameplate units in combat.
3. Forever's Soulstone duration (30 minutes in Classic) and Shadow Trance spell
    ID (17941 in Classic).
4. Whether `DeleteCursorItem` from a key press or world click works in combat
   (RestedXP's users report deletion in and out of combat).
5. Whether shards stack.
6. Whether Shadowburn's shard arrives within its 9-second window, and whether
   any other source creates shards (the gain log). Forever's spell list and
   talents (wowhandbook.com, talentsforever.com) name Shadowburn's shard.
7. Whether the `INV_Misc_Gem_Amethyst_02` TOC icon and the `INV_Misc_Orb_04`
   and `INV_Stone_04` fallback stone icons render.
8. Forever's Create Soulstone and Create Healthstone spell IDs, stone item IDs,
   and Healthstone level requirements (`/wtf debug_stones`); the tables hold
   Classic's IDs.
9. Whether Say from a cast event is blocked outdoors, and which actions block
   accepting a summon (flying, trading, combat, death).

## Automated tests

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Core.lua Layout.lua Shards.lua Stones.lua Announce.lua Tracker.lua Dots.lua Control.lua Alerts.lua Shield.lua Chimes.lua Reminders.lua Probe.lua Options.lua tests/run.lua
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
      the shard arrives in combat: it goes on your next key press, or on the
      first key press after combat if the client refuses in combat.
- [ ] Typing in chat, movement keys, and key bindings all still work with WTF
      loaded (the key hook passes every key on).
- [ ] The shard counter shows your count, red at or below the Low shard warning and
      green at your limit, legible on the icon; it
      updates as shards come and go, also in combat. Drag (unlocked), hide, and
      `/wtf reset` it; its place survives `/reload`.
- [ ] Move shards from the bank above the limit: none are deleted. Then Drain
      Soul once: only the new shard is deleted.
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
- [ ] DoT two mobs with Corruption, a Bane, and a Curse: the target's timers
      show in the purple pinned row, the other mob in the list below, with
      icons, countdowns, sweeps, and draining bars; an expired spell shows dim.
- [ ] Tab to the other mob: the pinned row follows and the old target joins
      the list. Set a focus: the red-outlined row appears and the list
      moves below it; clear it and the list moves up.
- [ ] Click a dim slot in the target and focus rows, also in combat: the
      spell is cast on that unit; Bane and Curse slots use the last one cast.
- [ ] A mob that dies leaves the list; the list hides after combat.
- [ ] With "Show DoT dots on nameplates" on, fight two mobs: grey dots turn
      to their colors as you DoT, back to grey as DoTs expire; no bubbles out
      of combat or on friendly plates. Check the height setting with your
      nameplate AddOn, and that `TempPortraitAlphaMask` makes the dots round.
      The height slider shows a gold mark at 50, and no other slider in the
      Settings panel shows one.
- [ ] The DoT Colors page: a new color recolors the tracker's bars and the
      nameplate dots at once; Defaults restores them; nameplate switches add
      and remove dots.
- [ ] Spells you have not learned yet (shown greyed in the spellbook) appear
      in neither theme nor on the nameplate dots.
- [ ] With the default Bars theme: each mob shows its name and a bar line per
      spell you know, with icon, spell name, and time left, draining from
      right to left; missing spells show as dim named lines; clicking a line
      in the pinned rows recasts it. A switch in combat applies after combat.
- [ ] Unlocked: the grid covers the screen under every frame, red lines
      cross at the center, clicks pass through it, it rebuilds after a UI
      scale change, and its switch hides it.
- [ ] Magnetic frames: a frame dropped near another snaps 20 apart, lined
      up by the nearest edge or center; Shift-drag moves a snapped group; not
      in combat.
- [ ] A failed stone click shows in red at the top of the screen as well as
      in chat.
- [ ] Control bar: Fear two mobs and Banish a third: a row each, draining,
      following the mobs as you tab, empty when one breaks, gone when it
      dies. Banish puts the moon on its mob; Fear marks nothing. Each feared
      mob's nameplate shows a draining Fear timer, also after it leaves plate
      range and comes back. "! Fear" Fears the mob whose nameplate you
      hover, else your target. "! Banish", and "! Seduction" (only once your Succubus or Incubus has its
      Seduction Grimoire; check both demons, and `/wtf debug_control` for the
      pet family and seduction=true)
      focus the mob under the mouse and cast on it; Seduction does nothing
      with another pet. A Banish row's click banishes the focus. In a party, each
      cast starts with its group message (Banish with {moon} as an icon). Fear a mob
      before the pull, then click its row in combat after it breaks: it
      recasts on that mob and returns to your target; with the mob gone,
      nothing is cast. `/wtf debug_control` lists the IDs (check Forever's).
- [ ] Demon Armor reminder: pulses while neither armor is on, a click casts
      your armor, hides as combat starts and returns after; no taint.
- [ ] Cooldown chimes: Death Coil chimes half a second before it is ready,
      also in combat; each spell's sound menu is Dyre's Sounds' nested menu
      (Dyre's Picks first, Text to Speech last); a sound saved by 0.2.x
      (for example a Dyre's Picks one) is still selected; Text to Speech says
      "Death Coil ready". The Nightfall sound menu has only file sounds
      (Dyre's Picks, Imp, Hellish imp), and the shield's sound menu the same.
- [ ] Sounds from Dyre's Sounds: with it installed, no "Install Dyre's
      Sounds" line at login; every sound plays (chimes, Nightfall, shield
      break). The installed WarlockToolsForever folder has no Sounds folder.
- [ ] Without Dyre's Sounds (disable it in the AddOn list): one chat line at
      login says to install it, and no second one later; WTF otherwise works;
      chimes, Nightfall, and the shield break play nothing; the chime and
      Nightfall switches show without sound menus. Enable it again: the
      sounds you chose before are still selected.
- [ ] With Dyre's Buff Reminders 0.2.0 or later enabled (and Dyre's
      Cooldown Chimes disabled): WTF plays no chimes (you hear each chime
      once, from DBR); the main page's Cooldown chimes switch and the page
      "Cooldown Chimes (Dyre's Buff Reminders)" say, greyed out, that DBR
      plays them, with `/dbr` in the tooltip; DBR's first run copied WTF's
      chime choices and DBR does not warn that WTF also plays chimes; the
      Nightfall sound still plays from WTF. Disable DBR: WTF's chimes and
      their saved choices are back.
- [ ] With Dyre's Cooldown Chimes still enabled (with or without DBR): the
      settings name Dyre's Cooldown Chimes and `/dcc`, and WTF plays no
      chimes.
- [ ] Shield display: Shadow Ward and Sacrifice fill the crescent, each icon
      in its own spot; with MTF installed too, the display shows on both a
      Warlock and a Mage. A Blessing of Protection from a Paladin, also in
      combat, draws the gold innermost arc and its icon; `/wtf debug_shield`
      confirms the bubble IDs.
- [ ] "Unlock frames to move them" and `/wtf unlock` outline the Stones bar and
      the shard counter and show sample tracker rows; all three drag; unticking
      or `/wtf lock` locks them, and the switch and commands stay in step;
      `/wtf reset` puts them back; their places survive `/reload`.
- [ ] Target a lower-level party member and left-click the Healthstone button:
      with a stone they can use, a trade opens with it in the window; without
      one, it is created, and the next left-click trades it. WTF never accepts.
- [ ] Soulstone a party member: `/wtf stones` names them; 30 minutes later a
      chat line says it ended. With no Soulstone up or no Healthstone, a
      reminder after a fight, at most every 10 minutes; the switches stop them.
- [ ] Turn on the Nightfall sound: choosing a sound plays it; a Nightfall proc
      plays it in combat.
- [ ] No Lua errors or taint warnings in or out of combat.
