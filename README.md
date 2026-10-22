# Warlock Tools Forever

Quality-of-life tools for Warlocks in World of Warcraft: Forever. Warlock Tools
Forever (WTF) is a suite of small modules, each with its own switch and
settings page: Soul Shard management, Soulstone and Healthstone buttons with
trading and reminders, summon and Soulstone announcements, a DoT tracker for
several mobs, and a Fear and Banish control bar.

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

The CurseForge app installs both with WTF. They copy your WTF settings for
these features once, the first time they run on a character. If one is
missing, WTF still works and says once at login to install it from
CurseForge (or to enable it in the AddOn list). WTF's Shield, Cooldown
Chimes, Alerts, and Demon Armor settings pages now have a button that opens
that AddOn's settings. WTF no longer plays any sound, so it no longer needs
Dyre's Sounds.

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

Without it, WTF works as before, with its own top-level settings page, its
own unlock, and its own grid, and says once in chat to install it.

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
  deleted, even above the limit.
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
  your limit. Hover it for the count and the limit. Hide it on the Soul
  Shards settings page; see [Moving frames](#moving-frames) to place it.

## Stones

A small bar with a Soulstone and a Healthstone button; see
[Moving frames](#moving-frames) to place it.

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

## DoT tracker

Timers for several mobs at once, by default in this order: your Curse
(whichever one is up), your Bane (Agony, Doom, or Havoc), Corruption,
Immolate, Siphon Life, and Fear and control (Fear, Howl of Terror, Death Coil,
Banish). Put them in your own order on the **DoTs** settings page: drag a
row up or down, and **Reset order** puts back the default. The nameplate dots
use the same order. Each live slot shows the spell's icon, a countdown,
a sweep, and a bar that drains as the spell runs out; a missing or expired
spell shows as a dim icon, so you can see what to recast.

- **Top row: your target**, with a warlock-purple outline. It follows your
  target as you tab or click, and hides when you have no hostile target.
- **Second row: your focus**, with a matching red outline, shown while you have
  a hostile focus.
- **Click a slot in either row** to cast that spell on your target or focus.
  The Bane and Curse slots recast the last Bane or Curse you used.
- **Below: every other mob you DoTed**, up to eight. Your target and focus are
  not listed twice. A mob leaves the list when it dies, when combat ends, or,
  out of combat, when it is out of sight for 10 seconds. In combat, a mob
  whose nameplate goes away (out of range, or nameplates off) keeps its row,
  and its timers come back with its nameplate. These rows show timers only; the
  game does not let AddOns target or cast on a mob picked from a list.
- **Two themes** on the DoT Tracker settings page. Both show only spells you
  know, as do the nameplate dots.
  - **Bars** (the default): see below.
  - **Compact:** a row per mob, its name and an icon per spell, with a
    countdown, a sweep, and a thin bar.
  - **Bars:** a block per mob, its name above one bar line per spell you know,
    with the spell's icon, name, and time left, draining from right to left
    like the Cooldown Manager's bars. A missing spell shows as a dim line with
    its name. In the pinned rows, click a line to recast it.
- **Sizes**, also on the DoT Tracker page, for the theme you chose: Compact
  has icon size, name width, text size, and where the name sits (left, right,
  above, or below the icons); Bars has bar width, line height, text size, and
  the name above or below the bars. **Reset size** puts the theme back as it
  was. A change in combat applies when combat ends.
- **Mob health** (off by default): **Show mob health** turns the line with each
  mob's name into its health bar, in the panel's color (purple for your
  target, red for your focus, dark grey for the others, by default), also in
  combat, and **Health text** adds its number, its percent, or both after the
  name. With a Compact name left or right of the icons, the fill is only
  behind the name.
- **Colors:** each slot's bar has its own color, the same as its nameplate
  dot: Curse purple, Bane red, Corruption white, Immolate orange, Siphon Life
  green, Fear and control yellow. Change them with the swatches on the
  **DoTs** settings page.
- **Settings sections:** the DoT Tracker page starts with **General** (what
  every panel shares), then **Target**, **Focus**, and **Others**, each with
  its panel's color (the outline of your target's and focus's rows, the other
  mobs' row border, and their health fill) and its opacity.
- To place the tracker, unlock your frames (see
  [Moving frames](#moving-frames)): it shows sample rows to drag it by. Your
  target's row, your focus's row, and the list of other mobs each move on
  their own: drag each by its rows. They start stacked as before, and
  `/wtf reset` stacks them again. Until you move it, the list hangs under the
  target and focus rows that show, with no gap for a hidden one. **Target panel opacity**, **Focus panel
  opacity**, and **Other mobs panel opacity** in their sections of the DoT
  Tracker page make each one see-through on its own (100%, fully solid, by
  default).
- The timers come from Blizzard's own aura display, which reads each mob's
  nameplate. Turn on enemy nameplates so listed mobs keep their timers.
- In combat the game can hide which nameplate belongs to which mob. WTF then
  learns a mob's nameplate while that mob is your target or focus, and keeps
  it while the nameplate stays up. A mob you DoT without targeting or
  focusing it (for example with a mouseover macro) can show in the list
  without its timers or health. Target or focus it once to fix that row; at
  the end of combat the list clears. A mouseover cast on a mob with the same
  name as your target can also count for your target.

### DoT dots on nameplates

An optional, quick-glance view, off by default: turn on **Show DoT dots on
nameplates** on the DoT Tracker settings page. In combat, a small bubble above
each hostile nameplate holds one dot per DoT you know, in the slot colors and
the DoT order. A
dot is grey while that DoT is missing. **On nameplates** on the **DoTs** page
chooses which slots appear as dots (all of them by default); it is greyed out
while the dots are off. Raise the bubble with **Dot height
above nameplates** if it overlaps your nameplate AddOn, and make it see-through
with **Nameplate dot opacity** (100%, fully solid, by default).

## Control bar

A bar for each mob you **Fear** or **Banish**, with the mob's name and the time
left, in the same style as the DoT tracker's Bars theme. Several mobs at once
are fine. It follows each mob as you change target, empties when the spell
breaks early, and goes when the mob dies. A cast counts on the mob it starts
on, also when you tab or move the mouse before it lands.

- **Banish follows your focus**, as Mage Tools Forever's Polymorph bar does:
  "! Banish" makes the mob under your mouse your focus, marks it, and
  banishes it. Its bar shows only for a Banish at your focus, and goes when
  your focus becomes another mob or none. A Banish at a mob that is not your
  focus (the plain spell button on your target, for example) shows no bar.
- **Fear rows** follow every mob you Fear. With several mobs of the same
  name, WTF counts a Fear on the one its own casts aim at: your focus, else
  the mob under the mouse, else your target. So a Fear from the plain spell
  button at your target, while your focus has the same name, shows on the
  focus's row; "! Fear" avoids that.
- **Focus box:** above the rows, a box in the focus panel's color shows
  "Focus: <name>" while you have a hostile focus, with your Fear's timer on
  it while it is feared. Click it to Fear your focus again. It aims only at
  your focus, so it never fears another mob, also when your focus changes
  in combat; with no focus it is hidden. Your focus's Fear shows there, not
  again in the rows. On the Control settings page, **How Fear and your focus
  work** says all this in chat.

- **Raid marker:** the "! Banish" macro puts the moon on your focus, in and
  out of combat, so your group knows it is out of the fight (change the
  marker on the Control settings page). The Banish row click and the plain
  spell button do not mark. For a Banish at your focus, the group message
  names the marker.
  Fear marks nothing, so WTF uses only one marker slot in a group. If you mark
  with your own `/tm` macro, set Banish's marker to None: the game toggles a
  marker that is set twice.
- **Group messages:** Fear, Banish, Enslave Demon, and Howl of Terror can tell
  your party or raid as you start casting, with the mob's name and marker
  (Announce page).
- **Click a Banish row** to banish your focus again, with the same spell. The
  click does not mark or change your target; with no focus it does nothing.
  The game lets the click
  change only out of combat: a Banish that starts before the pull is
  clickable all fight; one started in combat becomes clickable when combat
  ends.
- **Fear rows** show each feared mob and its time left; they take no clicks,
  since the game gives AddOns no way to aim at one of several same-named
  mobs (the Focus box is the one Fear click). A **Fear timer under each
  feared mob's nameplate** shows which one is about to break: hover its
  nameplate and press "! Fear", or click it to target it.
- **Macros:** WTF keeps "! Fear", "! Banish", and "! Seduction" in your
  character macros, each once you know its spell ("! Seduction" once your
  Succubus or Incubus has learned Seduction from its Grimoire). "! Fear" makes
  the mob under your mouse (else your target) your focus and fears it. Hold
  Shift as you press it to Fear the mob under your mouse (else your target)
  and keep your focus, for juggling a second mob.
  "! Banish" and "! Seduction" focus the hostile mob under your mouse (or your
  target, out of combat) and cast on your focus; "! Seduction" does nothing
  unless your pet is a Succubus or an Incubus. Turn them off on the Control settings page.

## Settings

**Options → AddOns → Warlock Tools Forever** (or `/wtf`) has one switch per
module. Each module has its own subpage, such as **Soul Shards**. With Dyre's
Toolkit, the page is under **Dyre's AddOns**.

## Moving frames

All WTF frames move together. Tick **Unlock frames to move them** on the
main WTF settings page, or type `/wtf unlock`: every WTF frame gets a gold
outline, and the DoT tracker and control bar show sample rows, so you can drag
them. Frames are magnetic: drop one near another and it snaps beside it, 20
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
While frames are locked, hold **Ctrl** and drag a frame (also a DoT tracker
panel) to move just that one, freely; not in combat.

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
| `/wtf debug_tracker` | Diagnostics: the spell IDs each tracker slot accepts, and tracked mobs |
| `/wtf debug_control` | Diagnostics: the control bar's spell IDs, rows, and clicks |

`/warlocktools` works the same as `/wtf`, in case another AddOn uses `/wtf`.

## Development

See [TESTING.md](TESTING.md) for the verification method and in-client
checklist, and [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md) for releases.
Automated tests use mocks; they do not prove in-client behavior.

## Support

Dyre's AddOns are free. If you enjoy them, you can support them on Ko-fi: https://ko-fi.com/dyre_janelle

## License

MIT. See [LICENSE](LICENSE).
