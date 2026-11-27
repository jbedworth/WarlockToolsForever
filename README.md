# Warlock Tools Forever

Quality-of-life tools for Warlocks in World of Warcraft: Forever. Warlock Tools
Forever (WTF) is a suite of small modules, each with its own switch and
settings page: Soul Shard management, Soulstone and Healthstone buttons with
trading and reminders, and summon and Soulstone announcements. The DoT
tracker and the Fear and Banish control bar are in **Dyre's Debuff Tracker**
(see below).

## Compatibility

WTF is for World of Warcraft: Forever `1.60.1` (tested on build `70450`),
Interface `16001`, Lua `5.1`. It does not check the client version or build,
because builds change often. At login it checks for the APIs it needs and
disables itself with one message if any are missing. It runs on Warlocks only;
on other classes it prints one message and stays off.

## Dyre's Shields Up and Dyre's Buff Reminders

In version 1.3.0, four features moved out of WTF into two of Dyre's AddOns
that every class can use:

- The **shield display** (the crescent for Shadow Ward, Sacrifice, and
  other shields) is in **Dyre's Shields Up** (`/dsu`).
- The **cooldown chimes**, the **Nightfall sound**, and the **Demon Armor
  reminder** are in **Dyre's Buff Reminders** (`/dbr`). Its Demon Armor icon
  casts your armor when you click it, as WTF's did.
- Proc overlays (spell activation overlays, such as Nightfall and
  Decimation) are not in WTF: a Dyre's AddOn draws them (Dyre's Toolkit 2.11
  or later). That AddOn also plays the Nightfall sound with its arcs, and
  WTF's Procs page then shows **Nightfall arcs and sound** and opens its
  settings.

The CurseForge app installs both with WTF. They copy your WTF settings for
these features once, the first time they run on a character. If one is
missing, WTF still works and says once at login to install it from
CurseForge (or to enable it in the AddOn list). WTF's Shield display, Chimes,
Procs, and Reminders settings pages show that AddOn's settings, with the
same names as on its own page: every Warlock proc, and every Warlock
reminder (Demon Armor, a missing demon, and the Voidwalker's taunt in a
group). The Procs page also has Dyre's Debuff Tracker's Demonic Brand
settings. A change there is the same change as on that AddOn's own page. With an older Dyre's Toolkit or an older version
of that AddOn, the page has a button that opens that AddOn's settings.
While the AddOn is missing, a box on the page says what it would add. WTF
no longer plays any sound, so it no longer needs Dyre's Sounds.

## Dyre's Debuff Tracker

In version 1.11.0, WTF's DoT and crowd-control features moved to **Dyre's
Debuff Tracker** (`/ddt`), where they are kept up to date:

- the **DoT tracker** (target, focus, and other mobs' panels), the DoT colors
  and order, and the **DoT dots on nameplates**;
- **Predictive DoT damage** (the block on the health bar, and **DIES**);
- the **smart curse**, with its key binding and the "! Curse" macro;
- the **Control bar** for Fear and Banish, with the Focus box, the Fear
  timers under nameplates, the "! Fear", "! Banish", and "! Seduction"
  macros, and the Fear, Banish, Enslave Demon, and Howl of Terror
  announcements.

The CurseForge app installs Dyre's Debuff Tracker with WTF. It takes your WTF
settings for these features once. WTF keeps them as they were and never
changes them, and says in chat what it copied. If Dyre's Debuff Tracker is missing,
WTF still works and says once at login to install it from CurseForge (or to
enable it in the AddOn list). WTF's **DoT Tracker**, **DoTs**, and
**Control** settings pages show Dyre's Debuff Tracker's settings for them
(with an older Dyre's Toolkit or Debuff Tracker, a button that opens its
settings).

## Dyre's Toolkit

**Dyre's Toolkit** gives all of Dyre's AddOns one layout mode and one
settings home. The CurseForge app installs it with WTF. With it:

- WTF's settings are under **Options → AddOns → Dyre's AddOns → Warlock
  Tools Forever**, and WTF's own pages (Soul Shards, Stones, and the rest)
  are under that.
- `/wtf unlock`, `/dyre unlock`, or the toolkit's minimap button unlock the
  frames of every Dyre's AddOn at once. WTF's frames snap to the frames of
  Dyre's other AddOns, and the toolkit draws the grid (with **Snap to the
  grid** on its settings page).
- In the game's AddOn list, WTF is in the Dyre's AddOns group.

Without the toolkit, WTF works as before, with its own top-level settings
page, its own unlock, and its own grid, and says once in chat to install it.

**Your profile** (Dyre's Toolkit 2.10.0 or later): WTF's settings and frame
places and sizes are part of your Dyre's Toolkit profile,
one per character. On the toolkit's settings page, copy them from another
character or the Defaults, or export and import them as one text line, for
every Dyre's AddOn at once. They apply at once, with no reload, and never in
combat. Each character keeps its own Soulstone timer and its shard count
from the current dungeon. The old DoT tracker and Control bar settings, kept
for Dyre's Debuff Tracker, are not in a profile.

WTF works well with **Weapon Skills Forever**, another of Dyre's AddOns. It
is optional: WTF does not need it.

## Soul Shards

Drain Soul fills your bags with shards. WTF deletes each shard that Drain Soul
creates above your limit, with no prompt. The game lets AddOns delete items
only on a key press or click, and not in combat or during boss fights,
challenge modes, PvP matches, or on maps that restrict AddOns. So the extra
shard goes on your next key press or click on the game world when none of
those applies: out of combat, almost at once. WTF passes every key on to the
game unchanged.

- **The limit** matches the total size of your equipped soul bags (also one in
  the reagent bag slot), or 6 if you have none. Turn off **Match soul bag size** to set your own, from 1 to 60.
- **Only created shards are deleted.** A shard counts as created when it
  arrives while you channel Drain Soul or within 3 seconds after, or within
  9 seconds of a Shadowburn hit (Forever's Shadowburn gives a shard if the
  target dies within 8 seconds). Shards you
  move into your bags yourself, from the bank, mail, or trade, are never
  deleted, even above the limit. The one exception: in a dungeon or raid.
- **Dungeons and raids:** as you leave one, WTF deletes the shards above your
  limit that you got inside, on your next key presses, also after a `/reload`
  or a relog. The shards you brought in stay, less the ones you used. A
  shard traded to you inside counts as one you got inside.
- **Only the new shard goes.** If you carry more than the limit on purpose, WTF
  deletes only the shard Drain Soul just created and keeps the rest. WTF
  remembers how many shards to keep: the shards you had at login and the ones
  you move in yourself, but created ones only up to your limit. So a new shard
  it could not delete at once (for example the second of two from one kill)
  still goes on a later key press, and lowering your limit deletes nothing.
  One shard goes per key press or click.
- **Carried bags only,** including your reagent bag, where Forever puts
  shards first. The bank is never touched.
- **Safety:** WTF waits while your cursor holds an item, and deletes only after
  it checks that the cursor holds one Soul Shard. If the client blocks a
  deletion, WTF puts the shard back, says so once, and stops deleting until
  you `/reload`.
- Each deletion prints one chat line; you can turn that off.
- **Shard counter:** a Soul Shard icon on screen with your shard count: red
  when low (2 or fewer by default; **Low shard warning** sets it), green at
  your limit. Hover it for the count, the limit, and how many are above it.
  Hide it on the Soul Shards settings page, and change its size there
  (**Shard counter size**, 50-150%); see [Moving frames](#moving-frames) to
  place it.
- **Right-click the shard counter** to delete every shard above your limit,
  also ones you brought in yourself, in a dungeon or anywhere else. The first
  goes at once and the rest on your next key presses or clicks, one each.
  In combat or a boss fight, WTF says they go after combat, and they go on
  your first key presses after it. If the game does not let AddOns delete
  items in a dungeon, WTF says so, and they go when you leave it. It works
  with automatic deletion off too;
  the shards you get after it then stay. With none above your limit, it says
  so. There is no popup.

## Stones

A small bar with a Soulstone and a Healthstone button; see
[Moving frames](#moving-frames) to place it. **Stones bar size** on the
Stones settings page makes it smaller or bigger (50-150%). **Layout**
(Horizontal or Vertical) makes it a row or a column; it needs Dyre's
Toolkit 2.18.0 or later, and without it the bar is a row.

- **Left-click** uses the best stone you carry. A Soulstone goes on your
  friendly target, grouped or not, or on you without one; Soulstones cannot
  be applied in combat. A Healthstone is used on you, except with a friendly player
  targeted: then left-click **trades** them the best Healthstone they can use
  (you press **Trade** yourself), or, if you carry none for their level,
  creates one; left-click again to trade it. During combat or a boss fight the
  game does not let WTF move the stone, so it goes in at your next key press
  after, or WTF tells you to drag it in.
- **Right-click** creates the best rank you know. With a friendly player
  targeted, the Healthstone button creates the best rank that player can use.
  You can carry one Healthstone of each rank, so when you already carry that
  rank, it creates the next lower one instead.
- The number on each button is how many of that stone you carry.
- **Middle-click** on the Healthstone button always uses your best
  Healthstone on yourself, whatever you have targeted.
- **Macros for your action bars:** WTF keeps two macros in your character
  macros, **! Healthstone** and **! Soulstone**. Drag them from the Macros
  window to a bar. Left-click uses your best stone (a Soulstone on your
  friendly target, or on you), right-click creates one, also in combat; their
  icon shows the stone. WTF updates them as your bags and spells change.
  Turn **Keep stone macros** off on the Stones settings page to remove them.
  (On Forever, `/click` macros do not press AddOn buttons, so these macros
  use the game's own `/use`.)
- Spellstone and Firestone buttons and reminders are planned; they show as
  greyed-out **Coming soon** switches on the Stones settings page.
- The game lets the buttons change only out of combat, so a stone made or used
  in combat updates them when combat ends.
- **Stone status:** WTF remembers who has your Soulstone and says in chat when
  it ends (30 minutes). It also reminds you when no Soulstone is up or you
  carry no Healthstone: on entering an instance, joining a group, and after a
  fight, at most every 10 minutes. Turn the reminders off on the Stones
  settings page. `/wtf stones` shows the status.

## Announce

When your Ritual of Summoning starts, or a Soulstone use on another player
succeeds, WTF tells your group and whispers the target. For a summon, the
target is the player you have targeted. When the trade window opens for a
Healthstone you trade with the Healthstone button, WTF whispers the player. Each of the five
messages has its own switch and text in **Options → AddOns → Warlock Tools Forever → Announce**:
`%T` is the target's full name ("First Last", as the game shows it) and `%Z`
your zone.

- Group messages go to your raid, else your party, and nothing when you are
  alone. You can choose Say instead, but the game may block it outdoors.
- The summon whisper teases the target's sloth-like pace and asks them to
  accept the summon.
- The Soulstone whisper tells the target that a sliver of their soul is
  trapped in a stone and drags them back to life where they fell.
- When you create a Healthstone or a Soulstone, WTF emotes (for example,
  "Dyre crushes a Soul Shard and forges a Healthstone from the screaming
  essence within."), at most once a minute per stone. The game lets AddOns
  emote only during a key press or click, so the emote goes out with your
  next one, within 30 seconds.
- The default texts credit Warlock Tools Forever (WTF), and the Healthstone
  whisper says: "Here, have a Healthstone. Some poor creature's essence gives
  you more health!" Edit a text to say anything you like.

## Settings

**Options → AddOns → Warlock Tools Forever** (or `/wtf`) has one switch per
module. Each module has its own subpage, such as **Soul Shards**. With Dyre's
Toolkit, the page is under **Dyre's AddOns**.

## Moving frames

All WTF frames move together. Tick **Unlock frames to move them** on the
main WTF settings page, or type `/wtf unlock`: every WTF frame gets a gold
outline, so you can drag them. Frames are magnetic: drop one near another and it snaps beside it, 20
pixels apart and lined up. Hold **Shift** while dragging to move a whole
snapped group. Untick it, or type `/wtf lock`, to lock them again.
`/wtf reset` puts them back in their default places. Everything starts locked.

While unlocked, a faint grid covers the screen, with red lines through its
center, so you can line frames up. Turn off **Show a grid while unlocked** on
the main settings page if you'd rather not see it.

With Dyre's Toolkit, unlocking unlocks every Dyre's AddOn's frames, WTF's
frames also snap to theirs, and the unlock switch and the grid are the
toolkit's: they are on the **Dyre's AddOns** page, and WTF's page has none of
its own. `/wtf unlock` and `/wtf lock` still work.
While frames are locked, hold **Ctrl** and drag a frame to move just that
one, freely; not in combat.

## Commands

| Command | Effect |
| --- | --- |
| `/wtf`, `/wtf options` | Open the settings |
| `/wtf shards` | Show your shard count, limit, and whether deletion is on |
| `/wtf stones` | Show who has your Soulstone and the stones you carry |
| `/wtf unlock` | Unlock every WTF frame (with Dyre's Toolkit, every Dyre's AddOn's frames), so you can drag them |
| `/wtf lock` | Lock them again where they are |
| `/wtf reset` | Move every WTF frame back to its default place |
| `/wtf debug_shards` | Diagnostics: bags, soul bag sizes, and recent shard gains |
| `/wtf debug_restrictions` | Diagnostics: which combat data this client hides from AddOns |
| `/wtf debug_delete` | Diagnostics: delete one shard above your limit now (out of combat) |
| `/wtf debug_stones` | Diagnostics: known stone ranks, carried stones, and level requirements |
| `/wtf debug_announce` | Diagnostics: the latest summon and Soulstone cast events |
| `/wtf debug_emote` | Diagnostics: two test emotes from a timer, one per chat function, and which the game blocks |

`/warlocktools` works the same as `/wtf`, in case another AddOn uses `/wtf`.

## Development

See [TESTING.md](TESTING.md) for the verification method and in-client
checklist, and [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md) for releases.
Automated tests use mocks; they do not prove in-client behavior.

## Support

Dyre's AddOns are free. If you enjoy them, you can support them on Ko-fi: https://ko-fi.com/dyre_janelle

## License

MIT. See [LICENSE](LICENSE).
