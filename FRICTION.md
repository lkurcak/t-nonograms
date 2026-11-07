# Friction log

What got in the way of writing a nonogram game and solver in T, with the
code that hit it. Each entry is labelled:

- **gap**: T should have it;
- **by design**: T leaves it out on purpose, and the entry says what that
  costs here;
- **unsure**: not clear which;
- **works**: something that went better than expected.

The log is evidence for t-lang's plans, not a design for them.

Written against `t` 0.55.0. Entries marked **fixed** say in which
release, and what the code looks like now.

## A game can only read lines — gap

`std` gives a program `read_line` (and, privately, a byte at a time), so
the game is a command loop: you type `f 3 1-5` to fill row 3, columns 1 to
5, and the board is drawn again under it. A nonogram wants a cursor moved
with arrow keys and a key to fill, which needs the terminal out of line
mode (termios, or the Windows console API) and reading keys as they come.
Nothing in `std` does either, and there's no `isatty` to tell a terminal
from a pipe (tcalc's log has that too). Writing ANSI escapes (`\u{1b}[2J`)
would work, but without raw input there's little point.

**`isatty` fixed in 0.63.0** (t-lang step 47): `is_terminal()`, so the game
echoes what it reads when no one's typing it, and `tests/run.sh` no longer
needs `awk`. Raw keys wait for t-lang's Os-C step.

**Raw keys fixed in 0.65.0** (t-lang step 49): `keys` plays with the arrow
keys. `os.stdin.raw()` gives a `Raw`, read a byte at a time; dropping it
puts the terminal back, and so does a panic. Telling the escape key from
the start of an arrow's escape sequence is `raw.wait(deadline)` 30 ms on:
no thread, no timer. Ctrl-C arrives as a key (3), which the game takes as
"go back". The cursor is the cell drawn in reverse video (`ESC [ 7 m`), so
`show::board` grew a `board_at` with an optional cursor. Works; what's
missing is only a library: no escape-sequence parser or screen API, so the
game writes `ESC [ H ESC [ 2 J` and redraws everything after each key.

## No randomness, and no clock to seed it — gap

`new 10 10` makes a random puzzle. The generator was easy (below), but
there's nothing to seed it with: no time, no OS entropy, no process id. So
a session starts from a fixed seed, every run gives the same puzzles in the
same order, and `new W H SEED` takes a seed by hand:

```rust,ignore
let mut session = Session { game: Option::None, rng: Rng::new(2026) };
```

A seed would be something the `Os` hands out, like the streams, so a
function given none can't be nondeterministic. That would fit T well.

**Fixed in 0.65.0** (t-lang step 49): `os.entropy.u64()?` seeds the
session, so each run's random puzzles differ; `new W H SEED` still repeats
one, which is what the transcript test uses. The generator stays a pure
function of its seed, as hoped.

## Writing SplitMix64 — works

`core::num::wrapping_add` and `wrapping_mul`, and `^` and `>>`, which can't
overflow and so don't panic, are all a PRNG needs:

```rust,ignore
self.state = wrapping_add(self.state, 0x9E3779B97F4A7C15);
let mut z = self.state;
z = wrapping_mul(z ^ (z >> 30), 0xBF58476D1CE4E5B9);
z = wrapping_mul(z ^ (z >> 27), 0x94D049BB133111EB);
z ^ (z >> 31)
```

That the wrapping is spelled out is right for this code: it's the one place
in the program where wrapping is wanted.

## No string patterns — gap

Commands are words, and the natural dispatch is a `match` on them:

```rust,ignore
match command {
    "help" | "h" | "?" => ..,
// syntax error: a string literal can't be a pattern yet; compare with `==`
```

So there's an `enum Command`, a `struct Word { word: &'static str, command:
Command }`, a `const WORDS: [Word; 22]` table, and a loop to look a word up.
The table reads well, and the `match` on `Command` is checked for
exhaustiveness, which a `match` on strings wouldn't be. But it's 35 lines
where Rust would need a dozen. The error message says "yet", so this is
expected.

**Fixed** in 0.57.0 (t-lang step 42): string literals are patterns on
`&str`. `command` in `main.t` is now the `match` above, 18 lines, and the
`Word` table is gone; a `_` arm is still needed, which is right.

## No tuples — gap (known)

Twice I wrote a tuple without thinking, both times for a pair of numbers:

```rust,ignore
let (lo, hi) = match dash {
    Option::None => { let n = number(s)?; (n, n) },
    ..
```

and `let (Option::Some(w), Option::Some(h)) = (w, h) else { .. }` for two
arguments that must both parse. The first became the `Span` struct, which
already existed for the result (fine), and the second two `let .. else`s
(fine too). Cheap here, but each was a compile, an error, and a rewrite.

## A `const` can't hold a slice of strings — unsure

The pictures were first a table of name and rows:

```rust,ignore
struct Picture { name: &'static str, rows: &'static [&'static str] }
const PICTURES: [Picture; 5] = [Picture { name: "plus", rows: PLUS.as_slice() }, ..];
// a const can't be of type `[Picture; 5]`: a const is plain data, of
// integers, `bool`, `char`, `()`, `&str` and `&[u8]`, and arrays, structs
// and enums of those
```

`&[u8]` is allowed but `&[&str]` isn't. What worked instead, and reads
better, is one multi-line string per picture, split into words when it's
drawn:

```rust,ignore
Picture {
    name: "plus",
    rows: "
        ..#..
        .###.
        #####
        .###.
        ..#..
    ",
},
```

Line breaks inside string literals (**works**) made this nice. What's left
is that a picture's rows are parsed at run time and checked by a test
(`every_picture_has_one_solution`) instead of when compiling.

## Iterating a `const` array, or a call's result — gap

```rust,ignore
for w in WORDS.iter() { .. }
// error: a temporary value is dropped here while still borrowed; keep it
// in a variable with `let`, so it lives longer
```

Each use of a `const` is a new temporary, and the one in a `for`'s head is
dropped before the loop runs. So every loop over a table is

```rust,ignore
let words = WORDS;
for w in words.iter() { .. }
```

which copies the table. The same for any call: `for w in
words(part).iter()` had to become `let part = words(part); for w in
part.iter()`. Rust keeps a `for` head's temporaries alive for the loop, and
T could too. The error and its suggestion are clear, so it's a small cost,
paid five times here.

**Fixed** in 0.57.0: a `for` now keeps its head's temporaries for the
loop, as Rust does. `for l in HELP.iter()`, `for pic in PICTURES.iter()`
and `for w in words(part).iter()` are written as such. (`let pictures =
PICTURES;` is still there where the value is used after a `let .. else`,
which is right: that's a `let`.)

## Two-dimensional indexing can't be proved — by design

A board is a `List<Cell>`, row by row, and a cell is `cells[y * width +
x]`. The checker can't prove that in range: it's a product of two unknowns,
which the refinement logic leaves out, and an invariant `cells.len() ==
width * height` can't be stated either, for the same reason. So every access
goes through `get`, and has to decide what to do with the `None` that can't
happen:

```rust,ignore
pub fn get(&self, x: usize, y: usize) -> Cell {
    if x >= self.width {
        return Cell::Empty;
    }
    match self.cells.get(y * self.width + x) {
        Option::Some(c) => *c,
        Option::None => Cell::Empty,
    }
}
```

The line solver's `fwd`/`bwd` tables are the same (`Table::get`). Reading a
missing cell as empty is a quiet fallback that would hide a bug, where
indexing would have panicked. Writing `with panic` and `.unwrap()` instead
is the honest alternative, but it spreads `panic` through the solver.
Arrays sized by const generics (`[[Cell; W]; H]`) would prove it, but a
board's size is only known at run time. This is the cost of linear-only
refinements; I'd guess most grid programs pay it.

## `assert` tells the checker nothing — gap

```rust,ignore
let w = words("  f 3\t2-5  ");
assert_eq(&w.len(), &3);
assert_eq(&w[0], &"f");
// error: can't prove `i < self.len()` for argument `i` of `index`
// note: known here: 0 <= w.len(); ..
```

After `assert(ok)` returns, `ok` holds. T has postconditions (`ensures`,
step 30), and `assert(ok: bool) with panic ensures ok` would say so; then
tests could index after asserting a length. The tests compare joined
strings instead (`"f|3|2-5"`), which is arguably clearer, but it was a
detour.

**Fixed** in 0.57.0: `assert(ok)` ensures `ok`, so
`words_are_between_spaces` asserts the length and then indexes.

## No `Eq` for slices, lists or `Option` — gap

Comparing two clues is a loop:

```rust,ignore
pub fn same_clue(a: &[usize], b: &[usize]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: usize = 0;
    while i < a.len() && i < b.len() { .. }
    true
}
```

`Eq` is implemented for `String` and nothing generic: not `[T]`, `List<T>`,
`Option<T>`, `Result`. `Option` isn't `Display` either, so `assert_eq(&number("42"),
&Option::Some(42))` can't be written; it's `assert_eq(&number("42").unwrap_or(0),
&42)`. (`#[derive(Eq)]` on my own enums worked fine.)

**Fixed** in 0.58.0 (t-lang step 43), mostly: `==` on slices, arrays,
`Option` and `Result` turned out to work all along; `List` has `Eq` now.
`same_clue` is gone, `grid.t` compares the slices with `!=`. Printing an
`Option` in `assert_eq` waits for a `Debug` trait (t-lang step 43.1).

**Fixed** in 0.59.0 (step 43.1): `assert_eq` says its sides by `Debug`,
which `Option` has and `#[derive(Debug)]` gives `Span`, so the tests
compare `Option`s and `Span`s whole: `assert_eq(&span("3", 5),
&Option::Some(Span { lo: 2, hi: 2 }))`.

## Reading text: no `split`, `trim` or parsing numbers — gap

`str` has `chars`, `split_at`, `get(lo, hi)`, `as_bytes`, and that's all.
`parse.t` writes `words` (split at whitespace), `number` (decimal to
`usize`, with `checked_mul` and `checked_add`), and `clues` (split at
commas, then words): 90 lines, all over byte indexes. Each is a few lines
in Rust's std. tcalc wrote its own lexer, which is fair for a calculator;
here it's just reading `f 3 2-5`.

**Fixed** in 0.58.0: `str` has `split`, `split_whitespace`, `lines`,
`trim`, `find`, `strip_prefix` and friends, and `parse`. `words` is a loop
over `split_whitespace`, `number` is `s.parse().ok()` (so it now takes a
`+`, as Rust's does), `span` uses `find('-')` and `strip_prefix('-')`, and
`clues` is `split(',')` then `split_whitespace`: the reading part of
`parse.t` went from 107 lines to 62.

The numbers part was pleasant, though: `let '0'..='9' = c else { return
Option::None };` tells the checker `c as u32 - 0x30` can't underflow, and
`?` on the `checked_*`s makes overflow a `None` with no ceremony (**works**).

## No command-line arguments, no files — gap

The solver would naturally be `nonograms solve puzzle.txt`. With no
arguments and no file reading, it's the `load` command, which reads two
lines of clues from stdin. Piping a file of commands in works, so this
didn't block anything.

**Half fixed in 0.63.0** (t-lang step 47): `os.args`. Words on the command
line are a first command, as `nonograms play 3`. Reading a puzzle from a
file waits for files (t-lang's Os-B step).

**Fixed in 0.64.0** (t-lang step 48, files): `load FILE` reads a puzzle's
clues with `os.fs.read_to_string`, so `nonograms load puzzle.txt` works.
The `Fs` lives in the `Session`, beside the random numbers. (No match
guards in T, so `Load` checks `args.first()` inside its arm: fine.)

## Small ones

- `for _ in 0..10` is an error, "cannot infer `T` for this use of
  `core::ops::Range`"; it's `0..10usize`. By design (integers have no
  default type), and the error says what to write.
- `use crate::line::{self, Cell}` isn't allowed ("`self` can only start a
  path"): it's two `use`s. Gap, small. **Fixed** in 0.57.0; `solve.t` and
  `puzzles.t` use it.
- `List` has no `first()`; its slice does, so it's
  `words.as_slice().first()`. `List` doesn't deref to a slice, so
  `as_slice()` is everywhere. Unsure: is there to be a `Deref`?
  **Fixed** in 0.58.0: `List` has `first`, `last` and `contains`; no
  `Deref`, by design (no implicit conversions).
- `match l.get(i) { Option::Some(c) => *c, Option::None => d }` appears a
  dozen times; `Option<&T>` has no `copied()`. `.map(|c| *c).unwrap_or(d)`
  works, and is what I'd use next time. Gap, small. **Fixed** in 0.58.0:
  `line.get(i).copied().unwrap_or(Cell::Empty)`.
- Writing into a `String` with `Write` gives a `Result<(), !>`, so it's
  `text.put(&n).into_ok()`. Sound and explicit; unsure whether it's worth a
  method that doesn't return a `Result`.

## The interpreter is about a thousand times slower than `t build` — unsure

`new 20 20 7` then `solve` takes 11 s in `t main.t` and under 10 ms as a
binary from `t build`. The interpreter checks memory as it goes, which is
its job, so this may just be the price of that; but it means a game, or
any search, should be compiled. `t test` takes 2 s for 13 tests, most of it
the test that solves every picture. `tests/run.sh` runs the transcript both
ways.

## Holes in format strings hold only places — unsure

0.59.0's `f".."` replaced every chain of `out.put(..)?` in `main.t`
(26 lines became 12): `out.line(&f"Puzzle: {p.name}, {p.width}x{p.height}")?`.
But a hole names a variable or a field, nothing more, so `row {i / w + 1}`
is a `let row = i / w + 1;` first, three times here. The docs say why (a
hole never runs code, so it can't hide a `panic`); it reads fine, but
it's the one thing I reached for that wasn't there.

*0.60.0:* a hole holds any expression now (`{i / w + 1}`), and the three
`let`s are gone; `#![warn(format_hole_expressions)]` would bring the old
rule back, as a lint, for a program that wants it.

## Every variant written with its enum — unsure

`Option::`/`Result::` came to 141 of the program's 1,693 lines, and
`Command::` 27 more in `main.t`'s dispatch. The docs say why (Rust's
`None =>` that binds a variable), and the rule caught nothing here, but
it's most of what a `match` says.

*0.61.0:* in a pattern a name that starts with an uppercase letter is a
variant, never a variable, so variants can be imported: `Some`/`None`/
`Ok`/`Err` come with the prelude, and `main.t` imports `Command::{..}`
and `line::Cell::{..}`. Not `solve::Answer`, whose `None` would hide
`Option`'s, nor `Outcome` and `Spread` together, which both have a
`Contradiction`.

## What worked

- **The borrow checker.** I didn't get a single borrow error. Returning
  `Result<Option<&'a mut Game>, Error>` from a function that also writes to
  `out`, and then `game.history.push(game.board.copy())` through that
  reference, just worked.
- **`let .. else`.** Most commands start with two or three of them:
  `let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };`.
- **Effect inference.** No `with` anywhere in the program. In `show.t` I
  first wrote `with W::e` on the generic drawing functions, as the docs do,
  and got "`digits` may panic, but `number` doesn't say `with panic`";
  deleting the `with` let it infer `{panic, W::e}`. The error's help said
  the same.
- **`t build`.** Compiled the whole program first time, and its transcript
  is identical to the interpreter's.
- **`#[blame_caller]` on test helpers.** A failing `solved(..)` in a test
  points at the row in the test, not the `assert_eq` in the helper.
- **Test-only helpers.** There's no `cfg(test)`, but helpers used only by
  `#[test]`s (`cells`, `text`, `clued`) don't get `dead_code` warnings.
