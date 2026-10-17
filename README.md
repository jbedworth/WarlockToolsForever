# Warlock Tools Forever

Quality-of-life tools for Warlocks in World of Warcraft: Forever. Warlock Tools
Forever (WTF) is a suite of small modules, each with its own switch and
settings page: Soul Shard management, Soulstone and Healthstone buttons with
trading and reminders, summon and Soulstone announcements, a DoT tracker for
several mobs, and a Nightfall sound.

## Compatibility

WTF is tested on the Forever beta, `1.60.1` build `70338`, Interface `16001`,
Lua `5.1`. It does not check the client version or build, because beta builds
change several times a week. At login it checks for the APIs it needs and
disables itself with one message if any are missing. It runs on Warlocks only;
on other classes it prints one message and stays off.

## Soul Shards

Drain Soul fills your bags with shards. WTF deletes each shard that Drain Soul
creates above your limit, with no prompt. The game lets AddOns delete items
only on a key press or click, so the extra shard goes on your next key press
or click on the game world, which during play is almost at once. WTF passes
every key on to the game unchanged.

- **The limit** matches the total size of your equipped soul bags (also one in
  the reagent bag slot), or 6 if you have none. Turn off **Match soul bag size** to set your own, from 1 to 60.
- **Only created shards are deleted.** A shard counts as created when it
  arrives while you channel Drain Soul or within 3 seconds after, or within
  9 seconds of a Shadowburn hit (Forever's Shadowburn gives a shard if the
  target dies within 8 seconds). Shards you
  move into your bags yourself, from the bank, mail, or trade, are never
  deleted, even above the limit.
- **Only the new shard goes.** If you carry more than the limit on purpose, WTF
  deletes only the shard Drain Soul just created and keeps the rest.
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
  creates one; left-click again to trade it.
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
  use the game's own `/use` and `/cast`.)
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

Timers for several mobs at once, in this order: your Curse (whichever one is
up), your Bane (Agony, Doom, or Havoc), Corruption, Immolate, Siphon Life, and
Fear and control (Fear, Howl of Terror, Death Coil, Banish). Each live slot shows the spell's icon, a countdown,
a sweep, and a bar that drains as the spell runs out; a missing or expired
spell shows as a dim icon, so you can see what to recast.

- **Top row: your target**, with a warlock-purple outline. It follows your
  target as you tab or click, and hides when you have no hostile target.
- **Second row: your focus**, with a matching red outline, shown while you have
  a hostile focus.
- **Click a slot in either row** to cast that spell on your target or focus.
  The Bane and Curse slots recast the last Bane or Curse you used.
- **Below: every other mob you DoTed**, up to eight. Your target and focus are
  not listed twice. A mob leaves the list when it dies, when it is out of
  sight for 10 seconds, or when combat ends. These rows show timers only; the
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
- **Colors:** each slot's bar has its own color, the same as its nameplate
  dot: Curse purple, Bane red, Corruption white, Immolate orange, Siphon Life
  green, Fear and control yellow. Change them on the **DoT Colors** settings
  page.
- To place the tracker, unlock your frames (see
  [Moving frames](#moving-frames)): it shows sample rows to drag it by.
- The timers come from Blizzard's own aura display, which reads each mob's
  nameplate. Turn on enemy nameplates so listed mobs keep their timers.

### DoT dots on nameplates

An optional, quick-glance view, off by default: turn on **Show DoT dots on
nameplates** on the DoT Tracker settings page. In combat, a small bubble above
each hostile nameplate holds one dot per DoT you know, in the slot colors. A
dot is grey while that DoT is missing. The **DoT Colors** page chooses which
slots appear as dots (Fear and control is off by default). Raise the bubble with **Dot height
above nameplates** if it overlaps your nameplate AddOn.

## Alerts

**Nightfall sound** (off by default, on the Alerts settings page): a sound
when Nightfall procs Shadow Trance, so your next Shadow Bolt is instant. Choose
from imp laughs and chirps (the default is the Imp spell chirp) or Raid warning,
Ready check, or Alarm clock, in a menu grouped like the Cooldown Manager's;
choosing one plays it once, so you can audition them. The game
plays the sound itself, also in combat.

## Control bar

A bar for each mob you **Fear** or **Banish**, with the mob's name and the time
left, in the same style as the DoT tracker's Bars theme. Several mobs at once
are fine. It follows each mob as you change target, empties when the spell
breaks early, and goes when the mob dies.

- **Raid marker:** a mob you Banish gets the moon when the cast lands, so your
  group knows it is out of the fight (change it on the Control settings page).
  Fear marks nothing, so WTF uses only one marker slot in a group.
- **Group messages:** Fear, Banish, Enslave Demon, and Howl of Terror can tell
  your party or raid as you start casting, with the mob's name and marker
  (Announce page).
- **Click a Banish row** to banish your focus again (with no focus, WTF targets
  the mob by name and returns you to your target). The game lets the click
  change only out of combat: a Banish that starts before the pull is
  clickable all fight; one started in combat becomes clickable when combat
  ends.
- **Fear rows** show each feared mob and its time left; they take no clicks,
  since the game gives AddOns no way to aim at one of several same-named
  mobs. Instead, a **Fear timer under each feared mob's nameplate** shows which
  one is about to break: click its nameplate to target it, then Fear.
- **Macros:** WTF keeps "! Fear", "! Banish", and "! Seduction" in your
  character macros, each once you know its spell ("! Seduction" once your
  Succubus or Incubus has learned Seduction from its Grimoire). "! Fear" Fears the mob under your mouse, else your
  target: hover a feared mob's nameplate as its timer runs out and press it.
  "! Banish" and "! Seduction" focus the hostile mob under your mouse (or your
  target, out of combat) and cast on your focus; "! Seduction" does nothing
  unless your pet is a Succubus or an Incubus. Turn them off on the Control settings page.

## Cooldown chimes

A sound just before **Death Coil**, **Howl of Terror**, **Shadow Ward**, your
**Soulstone**, and **Fel Domination** are ready again (Shadowburn,
Conflagrate, Amplify Curse, Bane of Doom, and Inferno are off by default), also
in combat. Each spell has its own sound, picked from a menu like the Cooldown
Manager's: the game's interface sounds, the Cooldown Manager's 93 alert
sounds, or a voice that says the spell's name. Pick how early it plays on the
Cooldown Chimes page.

## Shield display

The shield crescent from Mage Tools Forever: it fills with your **Shadow Ward**,
your Voidwalker's **Sacrifice**, or any absorb on you, like Power Word: Shield,
and drains as it absorbs, also in combat. A Paladin's **Blessing of
Protection** on you, which has no absorb, shows as a gold innermost arc that
drains with its time left. If you also use Mage
Tools Forever, you still see one crescent.

## Demon Armor reminder

An icon with a pulsing gold border while you have neither Demon Armor nor
Demon Skin, out of combat. Click it to cast your armor.

## Settings

**Options → AddOns → Warlock Tools Forever** (or `/wtf`) has one switch per
module. Each module has its own subpage, such as **Soul Shards**.

## Moving frames

All WTF frames move together. Tick **Unlock frames to move them** on the
main WTF settings page, or type `/wtf unlock`: every WTF frame gets a gold
outline, and the DoT tracker and control bar show sample rows, so you can drag
them. Frames are magnetic: drop one near another and it snaps beside it, 20
pixels apart and lined up. Hold **Shift** while dragging to move a whole
snapped group. Scroll over the Demon Armor icon to resize it. Untick it, or type `/wtf lock`, to lock them again.
`/wtf reset` puts them back in their default places. Everything starts locked.

While unlocked, a faint grid covers the screen, with red lines through its
center, so you can line frames up. Turn off **Show a grid while unlocked** on
the main settings page if you'd rather not see it.

## Commands

| Command | Effect |
| --- | --- |
| `/wtf`, `/wtf options` | Open the settings |
| `/wtf shards` | Show your shard count, limit, and whether deletion is on |
| `/wtf stones` | Show who has your Soulstone and the stones you carry |
| `/wtf unlock` | Unlock every WTF frame, so you can drag them |
| `/wtf lock` | Lock them again where they are |
| `/wtf reset` | Move every WTF frame back to its default place |
| `/wtf debug_shards` | Diagnostics: bags, soul bag sizes, and recent shard gains |
| `/wtf debug_restrictions` | Diagnostics: which combat data this client hides from AddOns |
| `/wtf debug_delete` | Diagnostics: delete one shard above your limit now (out of combat) |
| `/wtf debug_stones` | Diagnostics: known stone ranks, carried stones, and level requirements |
| `/wtf debug_announce` | Diagnostics: the latest summon and Soulstone cast events |
| `/wtf debug_emote` | Diagnostics: two test emotes from a timer, one per chat function, and which the game blocks |
| `/wtf debug_tracker` | Diagnostics: the spell IDs each tracker slot accepts, and tracked mobs |
| `/wtf debug_control` | Diagnostics: the control bar's spell IDs, rows, clicks, and the last marker |
| `/wtf debug_chimes` | Diagnostics: each chime spell, its cooldown, and the sound |
| `/wtf debug_shield` | Diagnostics: the absorb APIs and the shields WTF tracks |
| `/wtf debug_reminders` | Diagnostics: the Demon Armor reminder and its click |

`/warlocktools` works the same as `/wtf`, in case another AddOn uses `/wtf`.

## Development

See [TESTING.md](TESTING.md) for the verification method and in-client
checklist, and [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md) for releases.
Automated tests use mocks; they do not prove in-client behavior.

## License

MIT. See [LICENSE](LICENSE).
