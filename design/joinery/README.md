# uji / Joinery

Joinery is the visual foundation for uji's README and website. Start with [the cover](readme-cover.png) or open [the visual preview](preview.html).

## The idea

A coding agent you can shape with Lua.

The main artwork is a wooden **u**, opened at its joints, with one vermilion key suspended above it. The fitted pieces express the way you can change uji's tools, commands, windows and keybindings. The loose key also resembles a terminal block cursor.

The visual character is a precise workshop print: solid geometry, engraved grain, warm paper, deep green ink. The exposed joints give us a repeatable subject for future illustrations.

## Why it fits the project

- [The agent crate](../../crates/agent/src/lib.rs) is independent of the terminal and Lua, so it can be embedded on its own.
- [The Lua API](../../crates/uji/src/api/mod.rs) exposes windows, commands, tools, events, providers and keybindings.
- [The default configuration](../../crates/agent/config/default.lua) constructs the terminal layout and defines behavior in Lua.

Those are the features the identity should communicate. Use real configuration examples beside the artwork.

## Visual rules

Keep a single joint or assembly as the focal point. The object should be recognizable at thumbnail size.

Use engraved texture inside the illustration. Keep text, controls and code crisp. Leave plenty of paper around the artwork.

Use vermilion sparingly. It belongs to the loose key, the cursor, or one active control. Large areas stay paper or green.

Use stepped seams and rectangular cutouts for small decorative details. Keep the small mark flat, with no wood grain.

The cover's generated lettering is an initial wordmark study. The supplied SVG is a separate, editable emblem that works at small sizes.

## Palette

| Token | Hex | Use |
| --- | --- | --- |
| Paper | `#F3EFDF` | Main background |
| Ink | `#26372E` | Text, mark, dark sections |
| Olive | `#8B9475` | Illustration faces, quiet fills |
| Wood | `#C8BA96` | Exposed joints, supporting fills |
| Vermilion | `#C65036` | Key, cursor, active accent |

Use ink on paper for body copy. Olive and wood are decorative fills, not body-text colors on paper. The colors are also available in [palette.css](palette.css).

Use a heavy lowercase grotesk for the name, a plain sans serif for prose, and monospace for code and small labels. The preview uses system fonts and needs no font downloads. A custom outline wordmark can extend this kit later.

## README

Use the compact header at the top, then get straight to what uji does and how to run it. Its 3:1 shape and 640-pixel display width keep the introduction close to the top. The two backgrounds match GitHub's standard light and dark themes. Keep installation commands as actual text below the image.

From the repository root:

```markdown
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="design/joinery/readme-header-dark.png">
  <img src="design/joinery/readme-header-light.png" width="640" alt="uji. A coding agent you can shape with Lua.">
</picture>
```

## Website

Use [website-art.png](website-art.png) with real HTML text over the empty left side on wide screens. On narrow screens, place the text above the artwork and crop to the illustrated right side with CSS. The preview demonstrates both layouts.

Suggested opening copy:

> A coding agent you can shape with Lua.
>
> Change the tools, commands, keybindings and terminal layout. Embed the Rust engine in your own application.

Pair it with a short real Lua example. Let the documentation carry the technical detail.

If animated later, move only the red key into its slot once, over about 240 ms. Honor reduced-motion settings. The static cover already carries the idea.

## Included files

- `readme-header-light.png` and `readme-header-dark.png`: compact headers for GitHub's standard light and dark backgrounds.
- `readme-header-prompts.md`: exact prompts used to adapt the cover into compact headers.
- `readme-cover.png`: generated cover with name and description.
- `website-art.png`: generated artwork with no text.
- `mark.svg`: editable emblem for light backgrounds.
- `mark-on-dark.svg`: editable emblem for dark backgrounds.
- `palette.css`: reusable color and font variables.
- `preview.html`: self-contained local concept preview, with relative asset links.
- `generation-prompt.md`: exact image prompts and generation method.

The raster images were made with the built-in imagegen tool. The SVG marks and preview were authored directly. Use this kit as the reference for future README and website artwork.
