# HME's interface: design system

The look lives in two files. Pages build from their pieces and rarely set a colour of their own.

- `UI/Theme.lua`: tokens, type, shapes, ornament, buttons, the window.
- `UI/Kit.lua`: badges, bars, lists, segmented controls, KPI tiles, confidence pips, empty states, money and rate text.

## Identity: a field atlas (0.4.0)

An adventurer's field notebook more than a web dashboard: warm charcoal pages, moss green for what is alive and selected, brass for the engraved details, and contour lines where a map would have them. Ornament stays quiet and never carries meaning on its own.

## Principles

- **One accent, one primary action.** Moss green marks what is selected and the one main action of a view: Start farming, Find a farm, Add goal. Everything else is a secondary button (raised surface), a ghost button (text only) or a danger button (red text: Stop farming, the remove ×).
- **Colour carries meaning.** Gold is for money. The game's skill-up colours (grey, green, yellow, orange, red) are for skill-ups. Warning orange and danger red are for problems. Brass is ornament only. Text comes in three warm tones.
- **One number leads.** A farm row leads with the number its goal is about (skill-ups, gold or materials an hour); a tile shows its range underneath. The HUD and the Skinning levels box lead with large numbers.
- **Say how sure.** Confidence is four diamonds and a sentence ("Estimate: not measured yet · medium confidence"). Estimates are called estimates; a perfect circuit is shown apart from what a real session gets; gold from auction prices says "est.".
- **Nothing is cut.** Buttons and badges grow to fit their label; a big number steps down a size or two before the game would cut it; lists of names are fitted by measuring and end in "+N". Text that does not fit wraps or moves; it is never shrunk below 11.
- **Arranged around now.** The Dashboard shows the farming panel while you farm and the next step when you don't; what you have not learned takes one line, not a card each.
- **Say what to do when there is nothing.** Empty states explain how to get something there; a session with nothing recognised says so in words instead of zeros.

## Tokens (`T.C`)

| Token | Use |
|---|---|
| `side`, `win`, `field`, `card`, `raised`, `raisedHi` | warm charcoal surfaces, darkest to lightest |
| `line`, `edge`, `fieldEdge` | hairlines and outlines (warm white at low alpha) |
| `text`, `text2`, `text3` | primary, secondary, tertiary text |
| `accent`, `accentHi`, `accentInk`, `accentWash` | moss green; its hover; text on it; selected rows |
| `brass` | ornament: the header rule, contour lines, ticks, medallions, pips |
| `gold` | money and value |
| `success`, `warning`, `danger`, `info` | meaning |

`T.HEX` has the same colours as hex for inline colour codes (and `silver`, `copper` for money letters). Older names (`red`, `orange`, `tabOn` ...) still exist, mapped onto the palette, so code from GatherPath keeps working.

## Type

Inter is bundled (`Media/Fonts`, SIL Open Font License 1.1, `Inter-LICENSE.txt`):

| Role | Weight and size | Stands in for |
|---|---|---|
| `body` | Regular 13 | GameFontHighlight |
| `small` | Regular 12 | GameFontHighlightSmall |
| `meta` | Regular 11, tertiary | GameFontDisableSmall |
| `metaLg` | Regular 12, tertiary | GameFontDisable |
| `strong` | SemiBold 13 | GameFontNormal |
| `label` | SemiBold 11, tertiary, sentence case | GameFontNormalSmall |
| `title` | SemiBold 17 | GameFontNormalLarge |
| `display` | Bold 24 | GameFontNormalHuge |

`T.Text(parent, text, roleOrTemplate, color, size)` accepts a role or a game template name. `T.FitText(fs, width, role, size, min)` steps a number down to fit. `T.StringWidth(fs)` is the uncut width. If the font file does not load, or Settings, General, "Interface font" is "Game font", the game's own font is used.

## Art

`tools/make_ui_art.py` generates every shape in `Media/UI` (white, tinted in game; no third-party art):

- `Round`, `RoundEdge`: fill and outline, nine-sliced. `Track`, `Circle`: switches and knobs. `Chevron`: menus. `Shadow`.
- `Topo`: contour lines of a made-up landscape (header, hero and farming cards).
- `Medallion`: the ring round profession icons. `Pip`: the diamond (confidence, page titles, you-are-here). `Tick`: a card's corner mark. `Compass`, `Glow`.

`T.Surface`, `T.Outline` and `T.Shadow` fall back to flat squares where the client has no nine-slice textures, or when Settings, General, "Corners" is "Square". `T.Topo`, `T.Tick` and `T.Glow` add the ornament.

## Components

- Buttons: `T.FlatButton(parent, text, w, h, kind)` and `K.Button(parent, text, w, h, onClick, tip, kind)`, kinds `primary`, `secondary`, `ghost`, `danger`; they grow to fit their label (`b.autoFit = false` keeps a fixed width).
- `K.Badge` (a tinted pill that fits its text), `K.Pips` (confidence, `K.CONF_LEVEL`), `K.Bar` (resizable progress bar with a mark), `K.Segments`, `K.List` (virtual list), `K.Stat` (KPI tile: label, fitted value, sub line), `K.Empty`.
- Text helpers: `K.Money(copper)` ("3g 13s"), `K.Rate`, `K.MoneyRate`, `K.Range` ("113–163").
- `T.Card` (sentence-case title, brass corner tick), `T.Dropdown`, `T.EditBox`, `T.Slider`, `T.ScrollArea`, `T.LabeledSwitch`.
- The window, `T.Window`: a header with contour lines, a brass rule and the two-tone name; a sidebar with sentence-case sections; page titles with a brass diamond; a status line. `win:SetUIScale(s)` keeps it on the screen at any UI scale.

## Looking at it without the game

```bash
python tools/ui_preview.py --shots
```

This draws 40 states into `build/preview/` and screenshots them with Chrome or Edge in headless mode (no window opens, focus never moves). Open `build/preview/review.html`: every state with its checks and, after `--approve`, what changed since the baseline.

- **States**: every page and its important states (Dashboard not farming, farming, the 43-minute session with nothing recognised, all four professions, none; Farm Finder for leveling, profit, a material, best beasts, compare, a profession you don't have; Goals empty and with a long list; Stats empty and with three weeks of sessions; every Routes page; Setup; Settings), the HUD, the Skinning levels box, and the whole screen at 1280×800 (UI scale 1.0 and 1.15), 1366×768, 1920×1080 (0.71 and 1.0), 2560×1440 (0.64) and 3440×1440 (0.8), drawn at their real pixel size.
- **Data**: the character from the first real-client reports (level 41, Skinning 143/225, Hillsbrad), auction prices, sessions, goals (`tools/preview/scenes.lua`).
- **Checks**: overlapping text (within one top-level frame), text outside its panel (0.5.0: a top-level frame that draws a surface; scroll clipping respected), text cut short, text within 8% of its box ("tight": may be cut by the game's own text measure), cramped buttons, text under 10.5 px on screen, dim text, missing addon art, frames off the screen. `--strict` fails on overlap, cut or cramped.

They are renders, not game screenshots: text sizes are estimates (deliberately a little wide), game textures are placeholders, spell icons come from a public icon CDN when the browser can reach it. The game is the final word: `docs/MANUAL_TESTING.md` items 63-76 cover the 0.4.0 look in the client. When a real screenshot shows something the previews missed, the previews get a check or a state for it (0.4.0 added real prices and money, which is how gold an hour got cut in game but not in the previews).
