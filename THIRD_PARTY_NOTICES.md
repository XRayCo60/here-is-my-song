# Third-party notices

`smile` bundles data derived from third-party sources. Their licenses are listed here
as required by those licenses.

## Lilak — Persian Spell Checking Dictionary

- Used for: word membership in `persian_words.tsv` (81,063 POS-tagged entries;
  the 12,624 untagged/user entries of the source were excluded).
- Upstream: https://github.com/b00f/lilak
- License: Apache License, Version 2.0 — https://www.apache.org/licenses/LICENSE-2.0
- Notice: the entries were reformatted into a 4-column TSV
  (`word<TAB>frequency<TAB>status<TAB>source_or_note`); the POS tag is kept in the
  fourth column as `lilak:<tag>`. No warranty is provided by the upstream authors.

## Subtitle word frequencies

- Used for: the `frequency` column in `persian_words.tsv`, as a statistical weight only.
  It is not evidence that a word is valid.
- License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0) —
  https://creativecommons.org/licenses/by-sa/4.0/
- Notice: values were filtered and joined onto the Lilak membership list. Because this
  license is share-alike, `persian_words.tsv` as distributed here is also available
  under CC BY-SA 4.0.

## Project code

`smile.cpp`, `smile_cuda.cu` and `run.ps1` are not covered by the licenses above.
No license has been declared for them yet; add a `LICENSE` file before publishing or
redistributing this repository.
