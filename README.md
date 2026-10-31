# QuickNotes

Tiny native sticky notes for macOS. Notes live on your desktop, you can drag them around, and they stay put (even after restarting your Mac) until you delete them.

## Features

- **Draggable**: grab the top bar to move a note
- **Resizable**: drag the bottom-right corner
- **Persistent**: text, position, size and color are saved automatically
- **Lives on the desktop**: notes sit just above your desktop icons, behind other windows, and show on every Space
- **Float mode**: turn on *Float Above Windows* in the menu bar to keep notes on top
- **Copy & paste**: ⌘C / ⌘X / ⌘V / ⌘A / ⌘Z work as usual, or right-click for Cut, Copy, Paste
- **6 colors**: click the 🎨 button to cycle through them
- **Menu bar app**: no Dock icon. Use the menu bar icon for *New Note* (⌘N), *Show All Notes*, *Open at Login*, and *Quit*

## Build & run

Needs macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Turiya11/QuickNotes.git
cd QuickNotes
./build.sh --install       # builds and copies QuickNotes.app to /Applications
open /Applications/QuickNotes.app
```

Then choose **Open at Login** from the menu bar icon so your notes come back every time you log in.

Running `./build.sh` without `--install` puts the app in `build/QuickNotes.app`.

## Where notes are stored

`~/Library/Application Support/QuickNotes/notes.json`, a plain JSON file you can back up or sync.

## Deleting notes

Click ✕ on a note. If the note has text, you'll be asked to confirm.
