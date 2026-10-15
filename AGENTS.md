# Agent Guidelines

## Project purpose and scope

Warlock Tools Forever (WTF) is a World of Warcraft: Forever AddOn: a suite of
small, independent quality-of-life modules for Warlocks. Each module has an
enable switch on the main settings page and its own settings subpage. Add a
module only after the author agrees its behavior.

### Soul Shards (built)

- Deletes Soul Shards (item 6265) that a shard source creates above the carried
  limit, with no prompt or popup. The client allows `DeleteCursorItem` only
  during a hardware event (verified: from event handlers it raised
  `ADDON_ACTION_BLOCKED` in and out of combat). Deletions are queued from bag
  events and run from input hooks, as RestedXP's junk deletion does: a
  keyboard frame with `SetPropagateKeyboardInput(true)`, enabled only after
  `GetPropagateKeyboardInput()` confirms it so keys are never swallowed, and
  `WorldFrame:HookScript("OnMouseDown")`. Never attempt deletion from events.
- Shard sources are matched by spell name so every rank counts. Drain Soul is
  the only known source; add others when `/wtf debug_shards` gain logs show them.
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
  and `WarlockToolsForeverHealthstone`; their global names exist for `/click`
  macros. Left-click uses the best stone carried (Soulstone:
  `/use [@target,help,nodead][@player] item:ID`; Healthstone: `/use item:ID`).
  Right-click casts the highest known create rank; for a Healthstone with a
  friendly player target other than you, the highest known rank whose item
  level requirement (`C_Item.GetItemInfo` minLevel) the target meets.
- Ranks are a table of Classic spell and item IDs, including Improved
  Healthstone items; verify them in client with `/wtf debug_stones`.
- Secure attributes and the bar's visibility change only out of combat;
  changes in combat wait for `PLAYER_REGEN_ENABLED`. The bar drags out of
  combat unless locked; `/wtf reset` restores its place.
- PostClick explains a click that did nothing (no stone, no rank, a Soulstone
  in combat) with one line, deduplicated across press and release.

### Announce (built)

- On `UNIT_SPELLCAST_SUCCEEDED` for a cast whose `UNIT_SPELLCAST_SENT` named
  another player: Ritual of Summoning (by name of spell 698) or Soulstone
  Resurrection (by name of spell 20707, any rank). Failed, interrupted, self,
  and secret-target casts announce nothing.
- Four messages with their own switches and texts (`%T` target, `%Z` zone):
  summon group line ("Summoning >> %T << click please"), summon whisper (only
  verified advice; the accept-blocking rules are unverified), Soulstone group
  line, and Soulstone whisper (the author's text). Group means raid, else
  party, else nothing; Say is optional. SAY outdoors needs a hardware event and
  the success event is not one, so a blocked Say is reported once.
- Texts are trimmed, single-line, at most 255 bytes, else the default. The
  Announce settings subpage is a canvas page with edit boxes.
- If Forever adds meeting stones, announce that one is up (agreed, not built).

### Agreed future module (not yet built)

- **Tracker:** DoTs, Banes (Agony, Doom, Havoc), Curses, and Fear per mob, up
  to about 8 mobs, with expired effects kept as dimmed slots, a target/focus
  highlight, shown only while an effect is active, and a placeholder mode for
  positioning. On Forever the combat log is restricted at all times and every
  aura API refuses AddOn code in combat, so the tracker cannot read auras in
  combat. The player's own cast events (spell ID, target name) and unit GUIDs
  stay readable, so a tracker must work from your own casts and known
  durations, and cannot see resists, dispels, or early removal. Click-to-cast
  works only for fixed units (target, focus) through secure buttons; never
  promise clicking arbitrary mob rows.

Keep each module narrow. Do not add automation that plays for the user,
general frameworks, or speculative modules without agreement.

## Project structure

- Runtime files: WarlockToolsForever.toc, Commands.lua, Core.lua, Shards.lua,
  Stones.lua, Announce.lua, Probe.lua, Options.lua, loaded in that order.
  Commands parses `/wtf`; Core owns saved settings and their defaults, the
  login banner, class and install checks, slash conflict reporting, and
  startup; Shards, Stones, and Announce own their modules; Probe owns
  `/wtf debug_restrictions`; Options owns the settings pages.
- tests/run.lua holds the Lua 5.1 mock suite. tests/test_*.py cover the release
  helpers in scripts/. .github/workflows/ holds CI, opt-in publishing, and the
  approval gate check.
- README.md is the user-facing overview, TESTING.md the verification method,
  source evidence, and in-client checklist, docs/RELEASE_PLAN.md the release
  process, docs/CURSEFORGE_LISTING.md the CurseForge form text, and CHANGELOG.md
  the per-release change list.
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
  saved variables, and the Stones bar and buttons for `/click`), prefixed
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
- Package only WarlockToolsForever.toc, Commands.lua, Core.lua, Shards.lua,
  Stones.lua, Announce.lua, Probe.lua, Options.lua, and LICENSE under the top-level
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
