# Sticky Agent Tasks

A little macOS overlay that shows what your Claude Code sessions are doing. Each
prompt you send becomes a sticky note pinned to the right edge of the screen.
While Claude works, the note is a small amber square that pulses. When the turn
finishes, the note turns green, grows taller, and pops up with a checkmark, so a
done task actually looks done.

The panel floats above your windows, shows on every Space, and is click-through,
so it never gets in the way of what you're doing.

## How it works

- One binary, two jobs. Run with no arguments and it draws the panel. Run
  `record --event start|stop` and it updates a shared file that the panel watches.
- Claude Code hooks do the recording. A `UserPromptSubmit` hook adds a running
  note; a `Stop` hook flips the matching note to done. Multiple sessions share
  one file, guarded by a lock, so notes from every window show up together.
- State lives in `~/.claude/sticky-tasks.json`. Finished notes fade off screen
  after a few seconds and get pruned from the file shortly after.

## Install

```bash
./install.sh
```

That builds a release binary into `~/.local/bin/sticky-tasks`, adds the two
hooks to `~/.claude/settings.json` (idempotent, it won't duplicate them),
launches the panel, and sets it to start again at login.

Open a Claude Code session and send a prompt. A note appears. When Claude
finishes, it turns green and rises.

## Try it without hooks

Click the 🗒️ icon in the menu bar and pick **Add demo note**. A fake task shows
up as running and flips to done after about three seconds.

## Menu bar

- **Add demo note** — drop a sample task to see the effect.
- **Clear all notes** — empty the board.
- **Quit** — stop the panel.

## Uninstall

```bash
./uninstall.sh
```

Removes the login agent, strips the hooks back out of `settings.json`, and
deletes the binary.

## Build and run manually

```bash
swift build          # debug
swift run            # run the panel from source
.build/debug/StickyTasks   # or run the built binary directly
```

## Notes

- The panel needs no Screen Recording or Accessibility permission to run. Taking
  screenshots of it does need Screen Recording, which is a separate macOS setting.
- A note title is the first line or sentence of your prompt, trimmed to fit.
- The subtitle shows the working directory's folder name and, once done, how long
  the turn took.
