# Warlock Tools Forever

Quality-of-life tools for Warlocks in World of Warcraft: Forever. Warlock Tools
Forever (WTF) is a suite of small modules, each with its own switch and
settings page: Soul Shard management, Soulstone and Healthstone buttons, and
summon and Soulstone announcements.

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
  arrives while you channel Drain Soul, or within 3 seconds after. Shards you
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

## Stones

A small bar with a Soulstone and a Healthstone button. Drag it to move it (out
of combat); lock it in the settings; `/wtf reset` puts it back.

- **Left-click** uses the best stone you carry. A Soulstone goes on your
  friendly target, or on you without one; Soulstones cannot be applied in
  combat. A Healthstone is used on you.
- **Right-click** creates the best rank you know. With a friendly player
  targeted, the Healthstone button creates the best rank that player can use.
- The number on each button is how many of that stone you carry.
- The buttons work in macros: `/click WarlockToolsForeverSoulstone` (add
  `RightButton` to create one), and the same for `WarlockToolsForeverHealthstone`.
- The game lets the buttons change only out of combat, so a stone made or used
  in combat updates them when combat ends.

## Announce

When your Ritual of Summoning or a Soulstone use on another player succeeds,
WTF tells your group and whispers the target. Each of the four messages has its
own switch and text in **Options → AddOns → Warlock Tools Forever → Announce**:
`%T` is the target's name and `%Z` your zone.

- Group messages go to your raid, else your party, and nothing when you are
  alone. You can choose Say instead, but the game may block it outdoors.
- The Soulstone whisper explains that the target can revive where they fell.

## Settings

**Options → AddOns → Warlock Tools Forever** (or `/wtf`) has one switch per
module. Each module has its own subpage, such as **Soul Shards**.

## Commands

| Command | Effect |
| --- | --- |
| `/wtf`, `/wtf options` | Open the settings |
| `/wtf shards` | Show your shard count, limit, and whether deletion is on |
| `/wtf reset` | Move the Stones bar back to its default place |
| `/wtf debug_shards` | Diagnostics: bags, soul bag sizes, and recent shard gains |
| `/wtf debug_restrictions` | Diagnostics: which combat data this client hides from AddOns |
| `/wtf debug_delete` | Diagnostics: delete one shard above your limit now (out of combat) |
| `/wtf debug_stones` | Diagnostics: known stone ranks, carried stones, and level requirements |

`/warlocktools` works the same as `/wtf`, in case another AddOn uses `/wtf`.

## Development

See [TESTING.md](TESTING.md) for the verification method and in-client
checklist, and [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md) for releases.
Automated tests use mocks; they do not prove in-client behavior.

## License

MIT. See [LICENSE](LICENSE).
