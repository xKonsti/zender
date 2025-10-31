# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zender is a Zig-based 2D rendering library for building user interfaces. It provides:
- OpenGL-based rendering with custom shaders
- FreeType/HarfBuzz font rendering pipeline
- Layout system via the `zlayout` library
- GLFW window management
- Input handling (keyboard, mouse, cursor management)

The library is designed as both a standalone executable (`src/main.zig`) and an importable module (`src/root.zig`).

## Build & Development Commands

### Building and Running
```bash
# Build and run the application
zig build run

# Build only
zig build

# Run tests
zig build test
```

### Dependencies
The project uses several dependencies managed through `build.zig.zon`:
- `glfw_zig` - Window creation and input (remote git dependency)
- `zigglgen` - OpenGL bindings generator (remote git dependency)
- `freetype` - Font rasterization (local: `lib/freetype_c`)
- `harfbuzz` - Text shaping (local: `lib/harfbuzz`)
- `zlayout` - Layout engine (local: `../zlayout`, external dependency)
- `stb_image` - Image loading (C implementation: `lib/stb/stb_image_impl.c`)

### Zig Version
Minimum Zig version: `0.15.1` (see `build.zig.zon`)

## Architecture

### Core Modules

**src/root.zig** - Main library API entry point
- Exports `core`, `layout`, `drawing`, and `io` namespaces
- Contains minimal usage example in documentation comments (lines 1-45)
- Provides initialization/deinitialization lifecycle

**src/openGL.zig** - Rendering backend
- `Program` - Shader program management
- `Renderer2D` - Batched 2D rendering with:
  - Rectangle drawing with corner radius, borders, colors
  - Text rendering via font atlases
  - Image rendering via textures
  - Line drawing with configurable width and caps
- `ShapeCache` - Per-frame caching of HarfBuzz text shaping results
- Implements scissor clipping via `clipStart`/`clipEnd`

**src/font.zig** - Font management
- `FontCache` - Caches FreeType faces and HarfBuzz fonts by family/style/size
- `FontAtlas` - Dynamic texture atlas for glyph rendering
- `ShapedGlyph` - Output of HarfBuzz text shaping
- Supports Geist font family in multiple weights (light, regular, medium, semibold, bold, extrabold, black)
- Font files embedded from `src/resources/Font/Geist/*.ttf`

**src/glfw.zig** - Window management wrapper
- Window creation, event polling
- Input callbacks (keyboard, mouse, character input)
- Content scale handling for HiDPI displays

### Key Patterns

#### Frame Rendering Loop
```zig
while (!zen.core.shouldClose()) {
    zen.core.beginFrame();        // Clear buffers, reset input queues

    zen.layout.beginLayout();     // Start layout pass
    // ... UI layout code ...
    const cmds = zen.layout.endLayout();

    zen.drawing.start();          // Activate shaders
    zen.drawing.drawLayout(cmds); // Execute draw commands
    zen.drawing.end();            // Flush batches

    zen.core.endFrame();          // Swap buffers
}
```

#### Layout System Integration
The layout system (`zlayout` dependency) generates draw commands that are translated in `root.zig:drawLayout` (lines 233-361):
- `.clipStart`/`.clipEnd` - Manages OpenGL scissor regions
- `.drawRect` - Converts to `Renderer2D.drawRect` calls
- `.drawText` - Converts to `Renderer2D.drawText` with font lookups
- `.drawImage` - Converts opaque pointers back to `ImageTexture`

#### Input Queues
Input events are captured via callbacks and stored in frame-based queues:
- `char_input_queue` - Unicode character input (up to 32 chars)
- `key_pressed_queue` - Special keys (arrows, function keys, etc., up to 16 keys)
- `mouse_button_pressed_queue` - Mouse button presses (up to 8 buttons)

Queues are cleared at the start of each frame in `core.beginFrame()` (line 147).

### Shader Files
- `src/vert.glsl` - Vertex shader
- `src/frag.glsl` - Fragment shader for main rendering
- `src/frag2.glsl`, `src/frag_dis.glsl` - Alternative fragment shaders (not actively used)

### Text Rendering Pipeline
1. Font requested via `getFont(family, style, size)` - cached in `FontCache`
2. Text shaped using HarfBuzz - cached in `ShapeCache` per frame
3. Glyphs rasterized to atlas if missing
4. Quad vertices generated with atlas UVs
5. Batched and drawn via `Renderer2D`

Measurement (`measureText` in `root.zig:748`) follows the same pipeline without rendering.

## Important Implementation Details

### Font Lazy Loading
Fonts are loaded on-demand but common sizes/styles can be preloaded via `preloadCommon()` (called in `core.init()`).

### OpenGL Requirements
- OpenGL 4.1 Core profile (see `build.zig:86`)
- Extensions: ARB_clip_control, NV_scissor_exclusive

### Content Scale
Window content scale (for HiDPI) is handled via `window.getContentScale()` and applied in:
- `Renderer2D.begin()` for viewport setup
- `drawing.drawLayout()` for clip rectangles (line 244)
- `drawing.drawText()` passed to renderer

### Memory Management
- Uses `std.heap.GeneralPurposeAllocator` in main
- Font atlases dynamically grow as needed
- Shape cache evicts entries unused for >60 frames
