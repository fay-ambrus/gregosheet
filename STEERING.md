# Gregosheet Plugin Architecture

## Overview
A LuaLaTeX package for typesetting Gregorian chant sheet music using the GuidoHU font.

## Interface

### Tone definitions
```latex
\deftone{8szo}{<s...melody...}{8. szó tónus}
```
Stores tone melody (GuidoHU notes) and a red label. Tones are referenced by name.
The `.sty` resolves tone names to melody+label before passing to Lua.

### Sheet definitions
```latex
\defsheet[tone={8szo}]{Name}{melody}{lyrics}
```
Stores melody, lyrics, and optional tone reference as separate macros.

### Gregosheet environment
```latex
\begin{gregosheet}
  \addsheet[title={Antiphona}, tone={8szo}]{Name}  % named sheet (tone overrides defsheet)
  \addinline[title={...}, tone={8szo}]{melody}{lyrics}  % inline sheet
  \addtext{T.P.}                                    % floating red text
\end{gregosheet}
```

### Shorthand
```latex
\printsheet{Name}  % equivalent to \begin{gregosheet}\addsheet{Name}\end{gregosheet}
```

## Pipeline

```
pieces → parse → merge → measure → [justify ↔ break] → render
```

Justify and break are interleaved: break calls justify per line.

### 1. Parse (`gregosheet.parse.lua`)
- Pure functions, no font access, no width measurement.
- `parse_melody(str)` → token list: `{type, glyph}` where type is note|delimiter|symbol|barline.
- `parse_lyrics(str)` → syllable list: `{text, word_end, comment}`.
- All consecutive chars of the same type are grouped into one token.
- `<...>` in lyrics = comment (red, doesn't consume a note).
- `@` = empty syllable (consumes a note, renders nothing).
- `_` replaced with space for display.

### 2. Merge (`gregosheet.merge.lua`)
- Combines parsed pieces into a single flat event list + syllable list.
- `extract_leading_symbols(tokens)` — extracts clef (validated) + key sig (validated: all sharps or all flats).
- Emits `piece_boundary` events with clef, key, title, and computed clef/key changes.
- Comments (from `<...>` in lyrics and `\addtext`) become `{type="comment", syllable_idx, width_sp=0, glyph=""}` events with empty fixed delimiters around them (no duplicate if one already exists).
- Syllables are paired per-piece (no cross-piece bleed). Each note event gets `syllable_idx`.
  Barlines only consume `*`. Comments don't consume notes.
- Tone notes are inserted as individual events after each piece (not a tone_group).
  First tone note gets the label syllable (`tone=true`), rest get empty syllables.
  Tone delimiters are fixed to single `-`.
- Leading delimiter of each piece is fixed to `-` (reuses existing if present).

### 3. Measure (`gregosheet.measure.lua`)
- Only place that touches the font system (`node.hpack`).
- `measure_width_sp(text, fontid)` — core measurement function.
- `measure_events(events)` — attaches `width_sp` to every event.
  Non-fixed delimiters are normalized to `std_delimiter_sequence` ("---").
  `piece_boundary` gets `value` computed from `clef_at_boundary + key_at_boundary + "-"`.
- `measure_syllables(syllables)` — attaches `width_sp` to every syllable.

### 4. Justify (`gregosheet.justify.lua`)
- Called per line by break. Processes events from index 1 until overflow.
- `justify(events, syllables, width_limit_sp)` → `overflow_idx | nil, music_cursor`.
- Syllable placement:
  - Text wider than glyph → centered under note.
  - Text narrower than glyph → left-aligned at note start.
  - Recited notes → always left-aligned.
  - Tone syllables (`syl.tone`) → always left-aligned.
- Resolves lyric overlaps by widening preceding delimiters.
- Inserts hyphens in-place between non-word-end syllables when gap > `tolerable_syllable_gap_sp`.
  Hyphen insertion updates all `syllable_idx` references.
- Enforces fixed delimiters around barlines: `-` before, `--` after.
- Overflow detected when music_cursor or syllable right edge exceeds `width_limit_sp`.
- Constants used: `gregosheet.space_width_sp`, `gregosheet.hyphen_width_sp` (computed once in `init_delimiter_widths`).

### 5. Break (`gregosheet.break.lua`)
- Iterative loop: justify → break → emit → slice → prepend clef → repeat.
- Each iteration:
  1. Call `justify(events, syllables, page_width - clef_width)` → get overflow index.
  2. If overflow is a recited note → `handle_recited_split` (see below).
  3. `find_break_delimiter` — if overflow is a delimiter, use it; else scan back.
     Exception: delimiter before a barline is skipped (go back one more).
  4. Pad line: extend break delimiter with `-` chars until gap ≤ `w_star`, then append `*`.
     (`*` renders mostly before its start position; only `-` width extends after.)
  5. Emit system: events before break + padded delimiter.
  6. Slice emitted events/syllables from lists, fix `syllable_idx` references.
  7. If next event is `piece_boundary` → merge into clef for next line.
     Otherwise prepend synthetic clef (current glyph + key + "-").
  8. Reset `start_sp` on remaining events/syllables, repeat.
- Last line (no overflow): emit as-is without padding.

- **Recited note splitting (`handle_recited_split`):**
  1. Syllabify the recited text (Hungarian rules via `gregosheet.syllabify`).
  2. Find split point: max syllables that fit on current line.
  3. Chunk1 (current line):
     - ≥4 syllables → stays recited (one note, trimmed text).
     - <4 syllables → expanded to individual normal notes (via `recited_to_normal`).
       Re-justify the whole line. If some expanded notes overflow, move them back to chunk2.
  4. Chunk2 (next line):
     - ≥4 syllables → single recited note.
     - <4 syllables → expanded to individual normal notes.
     - Appended to remaining events for next iteration.

### 6. Render (`gregosheet.render.lua`)
- Emits TeX `\hbox` commands for each system.
- Titles: `\hbox to 0pt{...}` with `\rlap`, red uppercase, above music.
- Music: `\hbox{...}` with MusicFont, clef value + event glyphs.
  `piece_boundary` events render their `value`.
- Lyrics: `\hbox to 0pt{...}` with `\hskip` positioned syllables.
  - `comment=true` or `tone=true` → red text.

## Supporting modules

### `gregosheet.common.lua`
- Constants: delimiter chars (`¨`, `-`, `_`, `*`), character classification patterns, tolerances.
- Code array init (`pattern_to_codes`, `code_in_array`, `init_codes`).
- Delimiter width init (`init_delimiter_widths`) — also computes `space_width_sp`, `hyphen_width_sp`, `w_star`.
- Debug utilities.

### `gregosheet.keysig.lua`
- `gregosheet.accidentals` table: position → {sharp, flat, natural}.
- `init_accidentals()` — builds lookup tables.
- `validate_key(key_str)` — errors if key mixes sharps and flats or has invalid chars.
- `compute_key_signature(old_key, new_key)` — returns glyphs to display at key change.
  If old is empty → return new key. If new is empty → return naturals of old. Else return new key.
- `compute_clef_change(old_clef, new_clef)` — returns new clef if changed, empty if same.

### `gregosheet.syllabify.lua`
- `gregosheet.syllabify(text)` — syllabifies Hungarian text (with `_` as spaces).
- Used by break step when splitting recited notes at line boundaries.
- Handles digraphs/trigraphs (cs, sz, gy, ny, etc.).

## Key design decisions

### Justify-per-line (interleaved with break)
Each line is justified independently. Break calls justify, gets the overflow point,
handles line-boundary logic (splitting, padding), slices off the emitted line,
and repeats. No cascading widening across lines.

### Tones as individual note events
Tone notes are regular events in the stream (not a grouped structure).
First tone note carries the label syllable (`tone=true`, rendered red, left-aligned).
Remaining tone notes get empty syllables. Tone delimiters are fixed to `-`.

### Comments and floating text unified
Both `<...>` in lyrics and `\addtext{...}` become `{type="comment"}` events
with `width_sp=0`, `glyph=""`, and a linked syllable. Surrounded by empty fixed
delimiters (stretchable by justify for overlap resolution). No duplicate delimiter
if one already precedes.

### Line padding with `*`
The `*` glyph renders mostly before its start position (overlaps with preceding content).
Only a `-` width extends after its start. Padding algorithm: extend break delimiter
with `-` chars until gap ≤ `w_star`, then append `*`.

### Font IDs captured at document begin
Both `music_fontid` and `lyrics_fontid` are captured via `\AtBeginDocument` using `\musicfontsize` and `\lyricfontsize` (defined in document's styles file).

### Catcode overrides in environment
`_` (catcode 12) is essential — used in lyrics as space-within-syllable. `^` is a GuidoHU note char. `$` is defensive. All restored by TeX grouping at environment end.

## File structure
```
gregosheet.sty              — LaTeX interface
gregosheet.common.lua       — constants, char tables, init helpers
gregosheet.keysig.lua       — accidentals, validate_key, compute_key_signature
gregosheet.syllabify.lua    — Hungarian syllabification for recited note splitting
gregosheet.parse.lua        — parse_melody, parse_lyrics (pure)
gregosheet.merge.lua        — combine pieces into event + syllable lists
gregosheet.measure.lua      — attach width_sp (only font access)
gregosheet.justify.lua      — resolve overlaps, place lyrics (per line, stops at overflow)
gregosheet.break.lua        — line-breaking loop, padding, recited splitting
gregosheet.render.lua       — emit TeX hbox commands
gregosheet.main.lua         — orchestrator (calls pipeline in order)
GuidoHU.ttf                 — music font (freely distributable, © Bali János)
spec/                       — busted tests
  spec_helper.lua           — module loader and TeX stubs
  parse_spec.lua
  merge_spec.lua
  keysig_spec.lua
  measure_spec.lua
  justify_spec.lua
.github/workflows/test.yml  — CI: runs tests on push/PR
```

## Testing

Tests use [busted](https://lunarmodules.github.io/busted/) with Lua 5.3.

```bash
busted
```

The `spec/spec_helper.lua` provides a custom package searcher for dotted filenames
and stubs TeX-only globals (`texio`, `node`, `tex`). Stages that don't touch the
font system (parse, merge, justify, break, syllabify, keysig) are tested as pure Lua.
The mock `measure_width_sp` respects delimiter character widths (200/100/50 for `_`/`-`/`¨`).

## Usage as submodule

In a document repo:
```bash
git submodule add https://github.com/fay-ambrus/gregosheet.git gregosheet
ln -s gregosheet/gregosheet.sty gregosheet.sty
```

Build command:
```
TEXINPUTS=".:./gregosheet:" LUAINPUTS=".:./gregosheet:" lualatex --shell-escape -interaction=nonstopmode -output-directory=out <file>.tex
```

## TODO
- Title overflow: split long titles by syllabification, put overflow on first token of next line.
