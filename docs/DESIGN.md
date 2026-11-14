# HME's interface: design system

The look lives in two files. Pages build from their pieces and rarely set a colour of their own.

- `UI/Theme.lua`: tokens, type, shapes, buttons, the window.
- `UI/Kit.lua`: badges, bars, lists, segmented controls, KPI tiles, empty states.

## Principles

- **One accent, one primary action.** Leaf green marks what is selected and the one main action of a view: Start farming, Find a farm, Add goal, Done. Everything else is a secondary button (raised surface), a ghost button (text only) or a danger button (red text, for Remove and Delete).
- **Colour carries meaning.** Gold is for money. The game's skill-up colours (grey, green, yellow, orange, red) are for skill-ups. Warning orange and danger red are for problems. Text is in three tones: primary, secondary and tertiary.
- **Numbers first.** What a farm gives (skill-ups an hour, gold an hour, travel) shows as KPI tiles before the detail text. The HUD and the Skinning levels box lead with large numbers.
- **Calm surfaces.** Dark charcoal, slightly cool, in tiers: sidebar, window, field, card, raised. Rounded corners and hairline outlines replace heavy borders.
- **Say what to do when there is nothing.** Empty lists explain how to get something into them.

## Tokens (`T.C`)

| Token | Use |
|---|---|
| `side`, `win`, `field`, `card`, `raised`, `raisedHi` | surfaces, darkest to lightest |
| `line`, `edge`, `fieldEdge` | hairlines and outlines (white at low alpha) |
| `text`, `text2`, `text3` | primary, secondary, tertiary text |
| `accent`, `accentHi`, `accentInk`, `accentWash` | leaf green; its hover; text on it; selected rows |
| `gold` | money and value |
| `success`, `warning`, `danger`, `info` | meaning |

Older names (`red`, `gold`, `orange`, `tabOn` …) still exist, mapped onto the new palette, so code from GatherPath keeps working. `T.HEX` has the same colours as hex for inline text colour codes.

## Type

Inter is bundled (`Media/Fonts`, SIL Open Font License 1.1, `Inter-LICENSE.txt`), in six roles:

| Role | Weight and size | Stands in for |
|---|---|---|
| `body` | Regular 12 | GameFontHighlight |
| `small` | Regular 11 | GameFontHighlightSmall |
| `meta` | Regular 11, tertiary | GameFontDisableSmall |
| `strong` | SemiBold 12 | GameFontNormal |
| `label` | SemiBold 10, tertiary, written in capitals | GameFontNormalSmall |
| `title` | SemiBold 16 | GameFontNormalLarge |
| `display` | Bold 22 | GameFontNormalHuge |

`T.Text(parent, text, roleOrTemplate, color, size)` accepts either a role or a game template name. If the font file does not load, or Settings, General, "Interface font" is "Game font", the game's own font is used.

## Shapes

`tools/make_ui_art.py` generates the white shapes in `Media/UI` (no third-party art):

- `Round` and `RoundEdge`: a fill and an outline, drawn as nine slices.
- `Track`: the switch pill.
- `Circle`: knobs and dots.
- `Chevron`: the dropdown arrow.
- `Shadow`: a soft drop shadow.

They are tinted in the game. `T.Surface`, `T.Outline` and `T.Shadow` fall back to flat squares where the client has no nine-slice textures, or when Settings, General, "Corners" is "Square".

## Components

- Buttons: `T.FlatButton(parent, text, w, h, kind)` and `K.Button(parent, text, w, h, onClick, tip, kind)`. The kind is `primary`, `secondary`, `ghost` or `danger`, and `b:SetKind()` changes it later.
- Small pieces: `K.Badge` (tinted pill), `K.Bar` (rounded progress bar), `K.Segments` (segmented control), `K.List` (virtual list: hover, an accent bar on the selected row, a centred empty text), `K.Stat` (KPI tile), `K.Empty` (empty state).
- Containers and inputs: `T.Card`, `T.Dropdown`, `T.EditBox` (accent outline while typing), `T.Slider`, `T.ScrollArea`, `T.LabeledSwitch`.
- The window, `T.Window`: a slim header with logo, name, version chip and close button. Below it a quiet sidebar, where the selected tab gets a raised surface and an accent bar. At the bottom, a status line saying which addons are used.

## Looking at it without the game

```bash
python tools/ui_preview.py
```

This draws every page, the HUD and the Skinning levels box as HTML into `build/preview/`. Open `index.html` in a browser.

It uses the real addon code in the test client. `tools/preview/render.lua` records anchors, colours, fonts and textures, then lays them out.

These are renders, not game screenshots:
- Text sizes are estimates.
- Game textures are placeholders.
- Spell icons come from a public icon CDN when the browser can reach it.

The game is the final word. `docs/MANUAL_TESTING.md` items 58 to 61 cover the look in the client.
