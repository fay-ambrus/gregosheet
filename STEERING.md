# Gregosheet Plugin Architecture

## Overview
A LuaLaTeX package for typesetting Gregorian chant sheet music using the GuidoHU font.

## Interface

### Tone definitions
```latex
\deftone{8szo}{<s...melody...}{8. szó tónus}
```
Stores tone melody (GuidoHU notes) and a red label. Tones are referenced by name.

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
pieces → parse → merge → measure → justify → break → render
```

Each stage produces data consumed by the next. No stage mutates its input.

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
- Strips leading clef/key-sig from piece 2+ (becomes key-sig-change info).
- Computes naturals at piece boundaries via `gregosheet.keysig`.
- Handles `{type="floating_text", text="..."}` entries from `\addtext`.
- Inserts `piece_boundary` events with title and key sig info.
- Syllables are paired per-piece during merge (no cross-piece bleed).
  Each note/barline event gets a `syllable_idx` pointing into the syllables list.
  Barlines only consume `*`. Comments are flushed without consuming notes.
- Inserts `{type="tone_group", events=[], label=""}` inline after each piece
  that has a tone. Tone groups are events in the stream, not a separate structure.

### 3. Measure (`gregosheet.measure.lua`)
- Only place that touches the font system (`node.hpack`).
- `measure_width_sp(text, fontid)` — core measurement function.
- `measure_events(events)` — attaches `width_sp` to every event.
- `measure_syllables(syllables)` — attaches `width_sp` to every syllable.
- Also measures tone_group events if present.

### 4. Justify (`gregosheet.justify.lua`)
- Works on an infinite-width line (no line-breaking concerns).
- Syllables already paired with events via `syllable_idx` (from merge).
- Computes syllable x-positions (centered under note or left-aligned for recited).
- Resolves lyric overlaps by widening preceding delimiters.
- Inserts hyphen pseudo-syllables between non-word-end syllables.
- Places comment syllables inline (red, no note above, participates in overlap).
- Places floating_text events as comment syllables at current position.
- Enforces fixed delimiters around barlines: `-` before, `--` after.
- After this step, all widths and positions are final.
- Tone_group is NOT processed here (no lyrics, fixed tight delimiters).
- Delimiter utilities: `get_minimal_delimiter_over_distance`, `get_maximal_delimiter_under_distance`.

### 5. Break (`gregosheet.break.lua`)
- Iterative loop: peels off one line at a time from the infinite line.
- Each iteration:
  1. `find_overflow` — first event whose `right_edge` (event + syllable width) exceeds page.
  2. `find_break_point` — scan backwards for last note that fits.
  3. Apply adjusters:
     - `adjust_split_recited` — if overflow is a recited note, syllabify and split.
       After split: reset delimiters from split point to standard width, re-justify with `reset_prev=true`.
     - `adjust_barline` — if break starts with barline, move break to last note before it.
     - `adjust_tone_group` — tone groups are atomic, break before if needed.
  4. Emit system: slice events, collect syllables (paired by `syllable_idx` + unpaired by position),
     remove first delimiter (clef already ends with `-`), pad interior lines with trailing delimiter.
  5. Advance `start_idx`.
- Safety: `break_idx` always advances past `start_idx` to prevent infinite loops.
- **Recited note splitting:**
  When a recited note's syllable overflows:
  1. Syllabify the text (Hungarian rules via `gregosheet.syllabify`).
  2. Fit max syllables on current line.
  3. Chunk with ≥4 syllables → stays recited (one note, text underneath).
  4. Chunk with <4 syllables → expanded to individual notes (one per syllable).
  5. Reset delimiters after split, re-justify remainder with no inherited `prev_syl`.

### 6. Render (`gregosheet.render.lua`)
- Emits TeX `\hbox` commands for each system.
- Titles: `\hbox to 0pt{...}` with `\rlap`, red uppercase, above music.
- Music: `\hbox{...}` with MusicFont, clef + event glyphs.
  - Tone_group events: render sub-event glyphs with tight `-` delimiters.
- Lyrics: `\hbox to 0pt{...}` with `\hskip` positioned syllables.
  - `comment=true` → red text.
  - Tone_group label: red text left-aligned at tone start position.

## Supporting modules

### `gregosheet.common.lua`
- Constants: delimiter chars, character classification patterns, tolerances.
- Code array init (`pattern_to_codes`, `code_in_array`, `init_codes`).
- Delimiter width init (`init_delimiter_widths`).
- Debug utilities.

### `gregosheet.keysig.lua`
- `gregosheet.accidentals` table: position → {sharp, flat, natural}.
- `init_accidentals()` — builds lookup tables.
- `compute_naturals(old_key, new_key)` — returns natural chars to prepend at key change.

### `gregosheet.syllabify.lua`
- `gregosheet.syllabify(text)` — syllabifies Hungarian text (with `_` as spaces).
- Used by break step when splitting recited notes at line boundaries.
- Handles digraphs/trigraphs (cs, sz, gy, ny, etc.).

## Key design decisions

### Justify-then-break (not break-then-justify)
Lyric overlap resolution pushes content rightward. If we broke lines first, justification could overflow lines, requiring iteration. By justifying on an infinite line first, all widths are settled before breaking. Breaking becomes a trivial read-only scan. Interior lines are padded by stretching only the trailing delimiter (cannot cascade).

### Tones as inline mini-sheets
Tones are defined with `\deftone{name}{melody}{label}` and referenced by name.
Each piece can have its own tone, inserted as a `tone_group` event in the stream
right after that piece's melody. If a piece has no tone, nothing is inserted.
Tone groups render as GuidoHU notes with tight spacing (single `-` delimiters)
and a red label left-aligned underneath. No lyrics, no lyric-driven spacing.
Tone groups are never split across lines.

### Floating text as dedicated type
`\addtext` emits `{type="floating_text", text="..."}` in the Lua pieces table. The merge step handles it directly rather than encoding it as a fake piece with empty melody.

### Font IDs captured at document begin
Both `music_fontid` and `lyrics_fontid` are captured via `\AtBeginDocument` using `\musicfontsize` and `\lyricfontsize` (defined in document's styles file).

### Catcode overrides in environment
`_` (catcode 12) is essential — used in lyrics as space-within-syllable. `^` is a GuidoHU note char. `$` is defensive. All restored by TeX grouping at environment end.

## File structure
```
gregosheet.sty                  — LaTeX interface
gregosheet/
  gregosheet.common.lua         — constants, char tables, init helpers
  gregosheet.keysig.lua         — accidentals, compute_naturals
  gregosheet.syllabify.lua      — Hungarian syllabification for recited note splitting
  gregosheet.parse.lua          — parse_melody, parse_lyrics (pure)
  gregosheet.merge.lua          — combine pieces into event + syllable lists + tone_group
  gregosheet.measure.lua        — attach width_sp (only font access)
  gregosheet.justify.lua        — resolve overlaps, place lyrics (infinite line)
  gregosheet.break.lua          — greedy line-breaking, pad interior lines, recited splitting
  gregosheet.render.lua         — emit TeX hbox commands
  gregosheet.main.lua           — orchestrator (calls pipeline in order)
gregosheet-old/                 — reference copy of previous implementation
```

## Sheet data location
- `ordo-cantus-officii/` — all sheet definitions using `\defsheet`
- Tone definitions in a dedicated file (TBD, e.g. `ordo-cantus-officii/toni.tex`)
- Main documents reference them via `\printsheet` or `\addsheet`

## Build command
```
TEXINPUTS=".:./gregosheet:./gregosheet-psalm:" LUAINPUTS=".:./gregosheet:./gregosheet-psalm:" lualatex --shell-escape -interaction=nonstopmode -output-directory=out <file>.tex
```
