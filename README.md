# GoodSticky

Native macOS desktop notes with a menu bar resident. No web view, Electron, third-party dependencies, Dock icon, or app-switcher entry.

Closing the **Notes** list or **Preferences** leaves the desktop notes running. **Quit GoodSticky** explicitly stops the resident and removes its visible surfaces; launching it restores saved notes. Keeping editable notes on the desktop requires the resident process to run. These are desktop surfaces, not WidgetKit extensions.

## Build and install

The app targets macOS 13+. Build with a macOS 15+ SDK and current Swift command-line tools; full Xcode is not required.

```sh
./scripts/build.sh
# Quit an existing GoodSticky resident from its menu before installing an update.
./scripts/install.sh
```

The installer stages and verifies the app, atomically swaps it into `~/Applications/GoodSticky.app`, keeps the previous bundle at `~/Applications/.GoodSticky-previous.app`, and requests **Open at login** through macOS ServiceManagement. Login registration is refreshed after an atomic update so it continues to point to the installed app. The checkbox in Preferences reflects the system's registration status. If macOS requires approval, approve it in Login Items. Startup registration was verified locally; verification does not include rebooting the computer.

For development without installation:

```sh
open dist/GoodSticky.app
```

The app is locally ad-hoc signed. Public distribution requires Developer ID signing and notarization.

## Controls

- Click the menu bar icon for the compact **Notes** list. Right-click it for show/hide-all, bring-forward, preferences, and quit commands.
- **⌃⌥N** creates and focuses a new note. Change the global shortcut in Preferences. Closing the list does not disable the shortcut.
- Notes default to **220 × 180 points**. Drag the top-left grip to move one and the bottom-right grip to resize it down to **140 × 96**. Focus the resize grip and use arrow keys for keyboard resizing; Shift makes one-point changes.
- Hover to copy, hide, attach files, change color/opacity, or open options. Copy briefly changes its icon to a checkmark. **⌘W** hides the active note or closes the active management window.
- Choose from seven paper colors and 35–100% paper opacity. Text stays opaque. Low-opacity contrast depends on the wallpaper.
- Drop files/pictures onto a note, paste copied files, or use its paperclip control. Regular files are copied into the library in a utility queue. Symlink targets are copied as independent files; folders and Finder aliases are rejected. An import spinner stays visible during copying; quitting during an import offers a visible wait state and cancellation. Image previews adapt to the space available and use bounded thumbnails. At small sizes, the paperclip menu keeps every attachment accessible. Click an attachment to open it; remove it from its menu.
- **Options → Stack with…** combines notes. Named tabs or **⌃Tab / ⌃⇧Tab** switch notes. An overflow menu covers stacks that do not fit. Hiding affects the active note; pinning applies to the stack. **Remove this note from stack** separates it again.
- Notes normally stay at desktop level, across Spaces. Newly opened notes come forward for editing. **Keep above other apps** pins a note/stack; **Bring notes forward** temporarily raises all visible notes.

The management list and preferences are created only when opened and released when closed. Notes remember their text, size, position, color, opacity, visibility, attachments, and stacks. Existing notes that still used the original oversized default are compacted once; custom sizes are preserved.

## Storage and performance

An interprocess file lock allows only one resident per library, including direct executable/development launches. A duplicate launch activates the existing resident without opening a second writer.

`~/Library/Application Support/GoodSticky/notes.json` stores notes and preferences; copied files live in `Attachments/`. Back up this directory to preserve the library. Writes are debounced and atomic. Attachment removal commits before file cleanup, and persisted cleanup records recover interrupted operations. Normal quit stays open if saving fails. An unreadable library is never overwritten.

There is no idle polling or animation loop. Writes happen after changes; file copying and thumbnail decoding use utility queues. The thumbnail cache is limited to 24 entries / 4 MB, and identical in-flight decodes are coalesced. Opacity changes preserve attachment views. Failed previews collapse to a file entry. Closing management windows releases their view trees. Actual RAM and CPU usage depend on note count, text, pictures, displays, and macOS framework caching; zero cost is not promised.

## Verification

For reproducible launch, footprint and settled CPU measurements, run
`./scripts/bench.sh dist/GoodSticky.app 10`. See [benchmark methodology and verified results](docs/benchmarks/README.md).

```sh
./scripts/test.sh
./scripts/test-install.sh
# Isolated temporary library; does not mutate the user's notes:
dist/GoodSticky.app/Contents/MacOS/GoodSticky --smoke-test --snapshot-dir .build/qa
```

Model checks cover content/settings persistence, Unicode, debounced writes, independent attachment copies, failed writes, commit-before-delete safety, cleanup recovery, corrupt-library protection, writer exclusion, symlink copies, and folder rejection. Atomic installer checks verify replacement, previous-bundle retention, stale-file removal, and signature-failure safety. AppKit checks exercise creating/stacking/hiding/restoring/separating notes, corner-drag size math and minimum layout, attachments, shared pinning, raising notes, keyboard tab switching, accessibility, focus-visible controls, keeping notes visible after both management windows close, preserving the active editor, quit-wait UI/cancellation replies, coalesced thumbnails, and failed-preview collapse. Live UI checks additionally verify physical corner dragging, editing at minimum size, per-note themes/opacity, shortcut creation, closing the UI, and enabled login registration.
