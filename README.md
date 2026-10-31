# quarto-gatech

![Quarto Extension](https://img.shields.io/badge/Quarto-Extension-blue?logo=quarto)
![RevealJS](https://img.shields.io/badge/RevealJS-Presentations-black?logo=reveal.js)

A Quarto format extension that applies Georgia Tech brand identity to RevealJS presentations.

## Install

Start a new presentation from the template:

```bash
quarto use template btgould/quarto-gatech
```

This copies the extension into `_extensions/` and adds a starter `template.qmd`.
To add the format to an existing project instead, run `quarto add btgould/quarto-gatech`.

## Use

```yaml
---
title: My Talk
format: gatech-revealjs
---
```

```bash
quarto preview template.qmd   # live reload while editing
quarto render template.qmd    # write template.html
```

`#` headings start a section and `##` headings start a slide. Both get GT-branded
backgrounds automatically. See `demo.qmd` for every feature below on a rendered deck.

## Features

- **Branding**: official GT colors, Roboto type, and background images for the title,
  section, and content slides. The deck is 1920×1080 with a `c/t` slide counter.
- **Per-slide references**: add a `bibliography:` and each slide lists the entries it
  cites along its bottom edge (details below).
- **Callouts** are recolored with GT's bright palette. Give a callout a title with
  `::: {.callout-tip title="My title"}`.
- **Theorem blocks**: divs with a `#thm-`, `#lem-`, `#def-`, … id become gold callouts
  that can be cross-referenced with `@thm-…`. Add `name="…"` for a title and
  `number="…"` to override the automatic number.
- **Highlights**: `.hl-purple`, `.hl-blue`, `.hl-electric`, `.hl-canopy`, `.hl-buzz`,
  `.hl-horizon`. Combine one with `.fragment` and the highlight fades in on click.
- **Layout**: `::: {.horiz}` places its children side by side, centered.

## Options

Set these under the format:

```yaml
format:
  gatech-revealjs:
    toc: true                  # agenda slide listing sections and slides
    hide-section-slides: false # show `#` divider slides (hidden by default)
```

Standard [RevealJS options](https://quarto.org/docs/presentations/revealjs/) work
here too (`incremental`, `transition`, `slide-number`, …).

### Hidden section slides

By default the `#` divider slides are removed from the talk. The headings
still group the slides and still appear in the table of contents, so `toc: true` gives
a single agenda slide instead of a divider before every section. The slide counter
counts only the slides that are shown. To keep one divider, write
`# Title {.gatech-show-section}`. To keep all of them, set `hide-section-slides: false`.

Content written directly under a `#` heading (before the first `##`) lives on the
divider slide, so it is hidden along with it. Put it on a `##` slide instead.

### Per-slide references

A citation inside a fragment (`. . .` or `::: {.fragment}`) shows up together with that
fragment. A citation outside any fragment shows up with the slide. The end-of-deck
bibliography keeps full entries. The per-slide copies are compacted: venue names are
abbreviated using `_extensions/gatech/citation-abbrev.lua` (extend it for venues it
doesn't know), and page, volume, and DOI details are dropped. When you export to PDF,
the references flow inline so they aren't cut off at the bottom of the page.

To bold your own name (or anyone's) in the per-slide references, list it under
`bold-authors:` in the front matter, written as the bibliography prints it (IEEE style
gives `J. Doe`; a middle initial needs its own entry, e.g. `J. A. Doe`):

```yaml
bold-authors:
  - "J. Doe"
  - "J. A. Doe"
```

To collect every reference on a final slide, end the deck with an empty `## References`
heading.

## Customizing

Colors, fonts, and spacing are SCSS variables at the top of
`_extensions/gatech/custom.scss`. Each is declared `!default`, so you can override it
from your own theme file without editing the extension:

```yaml
format:
  gatech-revealjs:
    theme: [my-overrides.scss]   # layered on top of the GT theme
```

Background images live in `_extensions/gatech/assets/`. To use a different one on a
single slide, set it on the heading:
`## Slide {background-image="_extensions/gatech/assets/background_section_car.jpg"}`.

| File | Used for |
|---|---|
| `background_title.png` | Title slide |
| `background_slide.png` | `##` content slides and the TOC |
| `background_slide_nologo.png` | `background_slide.png` without the logo and corner curve; use per slide with `{background-image="assets/background_slide_nologo.png" background-size="contain"}` |
| `background_section_blank.jpg` | `#` section slides |
| `background_section_{building,car,students}.jpg` | Alternative section backgrounds |

## Requirements

Quarto ≥ 1.7.0

## Credits

Brendan Gould and Evanns Morales
