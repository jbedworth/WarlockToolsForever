# Warlock Tools Forever

Quality-of-life tools for Warlocks in World of Warcraft: Forever. Warlock Tools
Forever (WTF) is a suite of small modules, each with its own switch and
settings page. It starts with Soul Shard management.

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

## Settings

**Options → AddOns → Warlock Tools Forever** (or `/wtf`) has one switch per
module. Each module has its own subpage, such as **Soul Shards**.

## Commands

| Command | Effect |
| --- | --- |
| `/wtf`, `/wtf options` | Open the settings |
| `/wtf shards` | Show your shard count, limit, and whether deletion is on |
| `/wtf debug_shards` | Diagnostics: bags, soul bag sizes, and recent shard gains |
| `/wtf debug_restrictions` | Diagnostics: which combat data this client hides from AddOns |
| `/wtf debug_delete` | Diagnostics: delete one shard above your limit now (out of combat) |

`/warlocktools` works the same as `/wtf`, in case another AddOn uses `/wtf`.

## Development

See [TESTING.md](TESTING.md) for the verification method and in-client
checklist, and [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md) for releases.
Automated tests use mocks; they do not prove in-client behavior.

## License

MIT. See [LICENSE](LICENSE).
