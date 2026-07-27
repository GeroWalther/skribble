# Skribble

A native macOS paint app with a second mode that lets you draw **over your live screen** to explain things.

Built with SwiftUI + AppKit, no dependencies. Vector-based, so undo, selection, resizing and PDF export all stay sharp.

---

## Build & run

```bash
./build.sh --run       # release build, bundle, launch
./build.sh --install   # also copy to /Applications
./build.sh --debug     # debug build
```

Output lands in `build/Skribble.app`. Requires Xcode 14+ toolchain and macOS 14+.

The bundle is **ad-hoc signed**. The first launch may need a right-click → *Open*, or
`xattr -dr com.apple.quarantine build/Skribble.app`.

---

## Mode 1 — Paint canvas

A regular document window: white page, tool row, color palette, zoom.

**Tools:** pencil, highlighter, line, arrow, rectangle, rounded rectangle, ellipse,
triangle, star, text, eraser, select.

- **Dashed** toggle gives outlines a dashed stroke.
- **Shift** while dragging constrains lines/arrows to 45° steps and boxes to squares.
- **Select** tool: click to pick, shift-click to add, drag to marquee, drag the handles
  to resize, double-click a text object to re-edit it.
- The eraser removes whole objects it touches (vector eraser, not a pixel rubber).

### Using fill

There is one active color, and a **paint bucket** (💧 `drop.fill`, shortcut `f` in the
overlay) to apply it as a fill:

1. Draw a shape — circle, rectangle, triangle, star, rounded rect.
2. Pick the color you want.
3. Choose the **bucket** and click the shape. It fills.

You can click anywhere inside the shape, not just on its outline, even when it has no fill
yet. Overlapping shapes fill the topmost one under the pointer.

- **⌥-click** a filled shape to clear its fill again.
- **Clicking bare canvas** repaints the page background (canvas window only — never in
  screen-drawing mode, where it would drop an opaque sheet over your whole screen). Both
  are undoable.
- Only closed shapes can be filled; lines, arrows and freehand strokes ignore the bucket.
- The **Fill** toggle is the shortcut for the common case: with it on, new closed shapes
  come out already filled with the current color.

With shapes selected, picking a color recolors them — their fill if the bucket is the
active tool, otherwise their outline.

The bucket is in the screen-drawing sidebar too.

### Files & export

| Action | Shortcut |
|---|---|
| New canvas | `⌘N` |
| Open / Save / Save As | `⌘O` / `⌘S` / `⇧⌘S` |
| Export as PNG | `⇧⌘E` |
| Export as JPEG | `⇧⌘J` |
| Export as PDF | `⇧⌘P` |
| Copy as image | `⌘C` |

Drawings save as `.skribble` (JSON). PNG/JPEG export at 2× for crisp results; **PDF export
is true vector**. JPEG has no alpha, so a transparent canvas is flattened onto white
automatically.

**Exports follow the focused window.** If screen drawing is active but you're working in a
canvas window, `⇧⌘E` exports the canvas, not the (possibly empty) annotation layer.
Exporting an empty drawing warns instead of silently writing a blank file.

---

## Mode 2 — Draw on screen

Press **⌃⌥⌘D** (or the menu-bar ✎ icon → *Draw on Screen*) and a transparent layer covers
every display. Draw straight onto whatever is on screen.

### The edge sidebar

Move the pointer to the **left edge of the screen** and a compact dark palette slides in —
tools, colors, stroke widths, fill/dash toggles, undo/redo/clear, and export. It slides
away on its own about a second after you leave it. A faint hairline strip marks the
trigger zone so it's findable.

With multiple displays the sidebar appears on whichever screen you hit the edge of.

### Overlay shortcuts

| Action | Key |
|---|---|
| Exit screen drawing | `Esc` |
| Undo / redo | `⌘Z` / `⇧⌘Z` |
| Delete selection (or clear all) | `Delete` |
| Copy annotations | `⌘C` |
| Tools | `p` pen · `h` highlighter · `l` line · `a` arrow · `r` rect · `u` rounded · `o` ellipse · `g` triangle · `s` star · `f` fill bucket · `t` text · `e` eraser · `v` select |

Global hotkeys, which work from any app:

| Action | Key |
|---|---|
| Toggle screen drawing | `⌃⌥⌘D` |
| Toggle click-through | `⌃⌥⌘P` |
| Erase all annotations | `⌃⌥⌘E` |

### Click-through

While annotating, the overlay captures the mouse — clicks don't reach the apps below.
Toggle **click-through** (sidebar hand icon, or `⌃⌥⌘P`) to let clicks pass through so you
can scroll, switch tabs and click around with your annotations still floating on top. The
sidebar and the edge trigger stay live either way, so you can always toggle back.

### Dim

The sun/moon button cycles a dim layer (off → 25% → 50%) behind the annotations, which
helps when presenting.

### Exporting annotations

From the sidebar's ⬇︎ menu:

- **Copy / Save annotations** — transparent PNG or PDF, no permissions needed.
- **Save screen + annotations** — a finished screenshot with your drawing composited on
  top, as PNG, JPEG or PDF.

The screenshot option uses ScreenCaptureKit and therefore needs **Screen Recording**
permission (System Settings › Privacy & Security › Screen Recording). Skribble's own
windows are excluded from the capture, so the overlay and sidebar never appear in the
result. Everything else in the app works without granting it.

---

## Layout

```
Sources/Skribble/
  main.swift                  NSApplication bootstrap
  AppDelegate.swift           menu-bar item, hotkeys, menu actions, window list
  MainMenuBuilder.swift       the menu bar
  MainWindowController.swift  one paint window
  DocumentIO.swift            .skribble open/save
  HotKeyManager.swift         Carbon global hotkeys (no Accessibility permission)
  Model/
    Tool.swift                the tool enum
    RGBAColor.swift           codable sRGB color + palettes
    DrawShape.swift           one drawn object: geometry, paths, hit tests, transforms
    Drawing.swift             shape list, selection, undo/redo, persistence
    ToolSettings.swift        current tool + styling
    AppState.swift            shared overlay state
  Render/
    Renderer.swift            the single Core Graphics draw path
    Exporter.swift            PNG / JPEG / PDF / clipboard
    ScreenCapture.swift       ScreenCaptureKit desktop grab
  Views/
    DrawCanvas.swift          the interactive surface (both modes)
    CanvasWorkspace.swift     paint window chrome
    OverlayViews.swift        overlay root + edge sidebar
    Controls.swift            shared buttons, swatches, width picker
  Overlay/
    Panels.swift              transparent panels + left-edge trigger strip
    OverlayController.swift   overlay lifecycle, sidebar animation, keys, export
```

### Two notes on the implementation

**One renderer.** `Renderer` draws into a `CGContext` in a top-left-origin space. The live
canvas feeds it SwiftUI's `GraphicsContext.withCGContext`, and the exporters feed it a
flipped bitmap or PDF context. Screen, PNG and PDF output therefore cannot drift apart.

**Transparent windows and hit testing.** AppKit lets clicks fall straight through fully
transparent windows, so the overlay and the edge strip each carry a fraction of a percent
of background opacity. It's invisible, and it's what makes drawing on empty screen area
work at all.
