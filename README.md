<img src="assets/icon.svg" width="64" height="64" alt="">

# GoodSticky

Native macOS desktop sticky notes. Built with Swift and AppKit, with no web view, Electron, package dependencies, account, or network requests.

## Run

Requires macOS 13+ and Apple's Swift command-line tools (`xcode-select --install`). Full Xcode is not required.

```sh
./scripts/build.sh
open dist/GoodSticky.app
```

The app lives in the menu bar, with no Dock icon. Closing the library leaves the desktop widgets running. The build script produces a local, ad-hoc-signed app; a distributed release would need Developer ID signing and notarization.

## Your desktop notes

- **New note:** press **⌃⌥N** anywhere, use the menu bar, or choose **New note** in the library. Change the global shortcut in **Preferences**. A conflicting shortcut is rejected without losing your existing one.
- **Edit:** click a note and type. Notes save automatically after a short debounce. Normal quit commits pending edits first and stays open if saving fails.
- **Move / resize:** drag the top strip; resize from an edge. Notes remember their position and size and are brought back into view if a display disappears.
- **Copy / hide:** hover over a widget to reveal the controls. Hidden notes remain under **Hidden**; click one to restore it.
- **Color / transparency:** the **•••** menu offers seven paper colors and six opacity levels. Only the paper fades, so text remains readable. Preferences set defaults for new notes.
- **Pictures / files:** drag files onto a note, paste copied files, or choose **Attach files…**. Pictures get a small inline preview; click an attachment to open it in its default app. Imports and thumbnail decoding happen off the main thread. Files are copied into the library, so moving the original does not break an attachment.
- **Stacks:** use **••• → Stack with…** to combine widgets. Named tabs switch between notes; **⌃Tab** and **⌃⇧Tab** cycle the active stack. **Remove this note from stack** separates a note again.
- **Layering:** widgets normally sit at the desktop level, across Spaces. A new note or a note opened from the library comes forward for editing and returns to the desktop after it loses focus. **Keep above other apps** pins an individual note in front.
- **Find / manage:** the menu bar opens the searchable library, preferences, and commands to show, hide, or bring all notes forward.

These are interactive desktop widgets implemented as borderless `NSPanel` surfaces, rather than a WidgetKit extension. That supports direct text editing, arbitrary placement and resizing, file drops, and instant global-shortcut creation without normal window chrome or Dock/task-switcher entries. The library and preferences are ordinary native windows.

## Local storage

`~/Library/Application Support/GoodSticky/notes.json` contains note text, positions, settings, and attachment references. Copied files live beside it in `Attachments/`. Back up that directory to back up your library. An unreadable library is never overwritten automatically. Deleting a note is confirmed and removes its copied attachments; hiding is reversible. Attachment files are removed only after the updated library commits successfully; persisted cleanup records survive an interrupted quit.

## Verification

```sh
./scripts/test.sh
# With the app closed, exercise actual AppKit widget lifecycle in an isolated temporary library:
dist/GoodSticky.app/Contents/MacOS/GoodSticky --smoke-test
# Optional rendered UI snapshots:
dist/GoodSticky.app/Contents/MacOS/GoodSticky --smoke-test --snapshot-dir .build/qa
```

The standalone model harness checks Unicode/content/settings round-trips, debounced saves, independent attachment copies, attachment cleanup, deletion persistence, corrupt-library protection, failed-write recovery, and attachment deletion crash consistency. It runs with command-line tools alone. The app smoke test exercises creating, stacking, hiding, restoring, separating, and deleting actual widgets, minimum-size attachment layout, shared stack pinning, and raising multiple widgets, then removes its temporary library.
