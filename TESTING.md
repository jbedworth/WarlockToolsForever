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
2. Whether `DeleteCursorItem` from a key press or world click works in combat
   (RestedXP's users report deletion in and out of combat).
3. Whether the player's own `UNIT_SPELLCAST_*` spell IDs are secret in combat.
   If they are, no creation window opens and nothing is deleted.
4. Whether shards stack, the soul bag family bit (4), and Drain Soul's spell
   IDs on Forever (`/wtf debug_shards`).
5. Whether any source other than Drain Soul creates shards (the gain log).
6. Whether the `INV_Misc_Gem_Amethyst_02` TOC icon and the `INV_Misc_Orb_04`
   and `INV_Stone_04` fallback stone icons render.
7. Forever's Create Soulstone and Create Healthstone spell IDs, stone item IDs,
   and Healthstone level requirements (`/wtf debug_stones`); the tables hold
   Classic's IDs.
8. Whether `UNIT_SPELLCAST_SENT` names the target for Ritual of Summoning and a
   Soulstone use, whether Say from a success event is blocked outdoors, and
   which actions block accepting a summon (flying, trading, combat, death).

## Automated tests

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Core.lua Shards.lua Stones.lua Announce.lua Probe.lua Options.lua tests/run.lua
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
- [ ] `/click WarlockToolsForeverHealthstone` in a macro uses a Healthstone,
      also in combat; `/click WarlockToolsForeverSoulstone RightButton` creates one.
- [ ] Drag, lock, and `/wtf reset` the bar; its place survives `/reload`.
- [ ] Ritual of Summoning on a party member: one party line and one whisper
      with the zone. A Soulstone on a party member: the party line and the
      author's whisper. On yourself: nothing.
- [ ] The Announce page edits, Enter and Escape, switches, the Say choice, and
      Defaults work and survive `/reload`.
- [ ] No Lua errors or taint warnings in or out of combat.
