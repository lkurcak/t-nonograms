# t-nonograms

Nonograms, a game and a solver, written in T, the language at
`~/repos/tooling/t-lang` (GitHub: lkurcak/t-lang). Like tcalc and t-libs
(`~/repos/tooling/`), part of its purpose is to find out what using T is
like, here for a game.

- `main.t` is the program's root: the command loop. Modules: `line` (one
  line's solver, and `Cell`), `grid` (`Board`, `Puzzle`), `solve` (the whole
  puzzle: line propagation, then guessing), `puzzles` (drawn pictures, and
  random ones), `show` (drawing a board), `parse` (reading commands and
  clues).
- `tests/run.sh` runs what CI runs: `t check --deny-warnings`, `t fmt
  --check`, `t test`, and the transcript of `tests/input.txt` against
  `tests/expected.txt`, both interpreted and compiled with `t build`.
  `BLESS=1` rewrites the expected transcript.
- CI pins a `t` release (`t-version` + `t-sha256` in .github/workflows/t.yml, which calls forge's shared t-ci.yml); bump both after
  a t-lang release, from `gh release view vX.Y.Z -R lkurcak/t-lang --json
  assets`.
- `FRICTION.md` is the friction log: label entries gap / by design / unsure
  / works, with the code that hit them. It's evidence for t-lang steps,
  planned in t-lang, not here. Don't change t-lang from here.
- The interpreter is slow for the solver (seconds for a 20x20); use `t build`
  to play big puzzles.
