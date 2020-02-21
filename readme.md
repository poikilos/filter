# Minetest Mod: Advanced Filter [filter]

Filter language using an advanced system of filters including pre- and
post-sanitized word and partial word searches.

There is a default configuration at the URL specified by the default
`filter_url`. The default configuration includes words, word_partials,
and deep_partials (checked after removing spaces from the message).

There is no default local word list, and adding words to the local word
list is done through the `/filter` chat command. You need the `server`
priv to use the chat command. Removing words in this way does not affect
the web word list.

The `/filter` chat command can `add`, `remove` or `list` words. The
words are stored in `mod_storage`, which means that this mod requires
0.4.16 or above to function. Type `/filter download` to re-download the
web configuration from the URL specified as `filter_url`.

If a player speaks a word that is listed in the filter list, they are
muted for 1 minute. After that, their `shout` privilege is restored.
If they leave, their `shout` privilege is still restored, but only after
the time expires, not before.


## Differences from minetest-mods/filter
- Detect and ignore non-spoken characters.
- `filter_deep = true`: check for partial words after removing spaces to
  reduce filter evasion.
- Download filter settings from the web (that part is optional, and is
  turned on by setting this as a trusted mod).
  - Set a custom URL in minetest.conf: `filter_url = ` (see
    settingtypes.txt for default)
  - Add `secure.http_mods = filter` (or `secure.trusted_mods = filter`)
    along with any other mods you may need to have that permission.
    (otherwise, `minetest.request_http_api()` returns nil when
    `secure.enable_security = true` [which is the default if not set in
    minetest.conf])
  - The URL must provide json in the following format ("_comment" is
    optional):
```json
{
"_comment": "This page is only intended to be read by the strong language filter program, not displayed.",
"partials": [],
"word_partials": [],
"words": []
}
```
  - `words` are compared to words in each chat message.
  - The filter looks for `word_partials` inside words of the message.
  - `partials` is the most strict, since spaces are removed from the
    message before the check.
  - [ ] Adding partials to the deep partials list while filter_fuzzy
    is on will reduce performance slightly, since every character of
    the message will be checked to see if it starts with a word similar
    to the string (see https://github.com/profan/lua-bk-tree).
- See settingtypes.txt for additional explanations of the options.


## Download
- [Download ZIP](https://github.com/poikilos/filter/archive/master.zip)
- `git clone https://github.com/poikilos/filter.git`
- [Browse Source on GitHub](https://github.com/poikilos/filter)


## Developer Notes
(Poikilos)

### Tasks
- [x] Implement web-based configuration.
- [x] Implement deep search (without spaces)
  - [x] Remove partials and split into deep_partials and word_partials.
    - [ ] Remove partials from the copy of the config on pastebin.
- [x] Remove public functions.
- [ ] Implement `filter_fuzzy`.
