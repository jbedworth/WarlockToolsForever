# Changelog

Player-facing changes for each Warlock Tools Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 0.1.0-beta

- First public beta for WoW: Forever.
- Soul Shard management: shards that Drain Soul creates above your limit are deleted with no prompt, on your next key press or click (the game allows item deletion only then). Shards you move into your bags yourself are never deleted.
- The limit matches your soul bags' size, including a soul bag in the reagent bag slot, or 6 without a soul bag; you can set your own in Options > AddOns > Warlock Tools Forever > Soul Shards.
- Stones: a movable bar with Soulstone and Healthstone buttons. Left-click uses your best stone (a Soulstone on your friendly target, or yourself); right-click creates your best rank, and the Healthstone button creates the best rank your friendly player target can use. Works in macros with `/click`.
- Announce: when your Ritual of Summoning or a Soulstone use on another player succeeds, tell your raid or party and whisper the target. Each message has its own switch and editable text.
- `/wtf shards` shows your shard count and limit. `/wtf options` opens the settings.
- Settings are saved per character.
