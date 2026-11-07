//! Solving one line: which cells of a row or column are certain, given its
//! clue and what's known of it already.
//!
//! A line of `n` cells with blocks `clue[0]`, ..., `clue[k - 1]` is read as
//! if it had one more cell, `n`, which is always empty, so that every block
//! is followed by an empty cell. `fwd[i][j]` says the first `i` cells can
//! hold the first `j` blocks, each with its empty cell after it, and
//! `bwd[i][j]` says the cells from `i` on can hold the blocks from `j` on.
//! A cell can be empty if, for some `j`, the cells before it hold the
//! first `j` blocks and the cells after it the rest; it can be filled if
//! some block can be placed over it with both sides fitting. What can only
//! be one of those is certain.

use alloc::list::List;
use alloc::string::String;
use grid::Grid;
use Cell::{Empty, Filled, Unknown};
use Outcome::{Changed, Contradiction};

/// What's known of a cell.
#[derive(Copy, Discard, Eq)]
pub enum Cell { Unknown, Filled, Empty }

/// What solving a line found.
#[derive(Copy, Discard, Eq)]
pub enum Outcome {
    /// No way to place the blocks agrees with what's known.
    Contradiction,
    /// This many cells became known.
    Changed(usize),
}

/// A table of `bool`s, `rows` by `cols`, all false at first: a grid, with
/// a row `r` and column `c` the other way round from a grid's `x` and `y`.
#[derive(Discard)]
struct Table { bits: Grid<bool> }

impl Table {
    fn new(rows: usize, cols: usize) -> Table {
        let Some(bits) = Grid::new(cols, rows, false) else {
            panic("a table that big doesn't fit in memory")
        };
        Table { bits }
    }

    fn get(&self, r: usize, c: usize) -> bool { self.bits.at(c, r).copied().unwrap_or(false) }

    fn set(&mut self, r: usize, c: usize) {
        if c < self.bits.width() && r < self.bits.height() {
            self.bits.set(c, r, true);
        }
    }
}

/// What's known of cell `i` of `line`, with the cell past its end empty.
fn at(line: &[Cell], i: usize) -> Cell { line.get(i).copied().unwrap_or(Empty) }

/// Can cell `i` be empty, as far as is known?
fn may_be_empty(line: &[Cell], i: usize) -> bool { at(line, i) != Filled }

/// How many cells before each index are known to be empty: `empties[i]`
/// for the cells `0..i`, so `i` from 0 to `n` (the extra cell isn't
/// counted).
fn count_empties(line: &[Cell]) -> List<usize> {
    let mut empties = List::with_capacity(line.len() + 1);
    let mut seen: usize = 0;
    empties.push(0);
    for c in line.iter() {
        if *c == Empty {
            seen = seen + 1;
        }
        empties.push(seen);
    }
    empties
}

/// Can a block cover cells `s..e` of the line: is none of them known to be
/// empty, and are they all in the line?
fn fits(empties: &[usize], s: usize, e: usize) -> bool {
    match empties.get(s) {
        Some(a) => match empties.get(e) {
            Some(b) => *a == *b,
            None => false,
        },
        None => false,
    }
}

/// The clue's `j`th block, or 0 past the end.
fn block(clue: &[usize], j: usize) -> usize {
    match clue.get(j) {
        Some(b) => *b,
        None => 0,
    }
}

/// Fills in what can be known of `line` from `clue` and what it already
/// says, and tells how many cells it learned, or that it can't be done.
pub fn solve(clue: &[usize], line: &mut [Cell]) -> Outcome {
    let n = line.len();
    let k = clue.len();
    // The line and the empty cell past it.
    let m = n + 1;
    let empties = count_empties(line);
    let empties = empties.as_slice();

    let mut fwd = Table::new(m + 1, k + 1);
    fwd.set(0, 0);
    for i in 0..m {
        for j in 0..k + 1 {
            if !fwd.get(i, j) {
                continue;
            }
            if may_be_empty(line, i) {
                fwd.set(i + 1, j);
            }
            if j < k {
                let e = i + block(clue, j);
                if e < m && fits(empties, i, e) && may_be_empty(line, e) {
                    fwd.set(e + 1, j + 1);
                }
            }
        }
    }
    if !fwd.get(m, k) {
        return Contradiction;
    }

    let mut bwd = Table::new(m + 1, k + 1);
    bwd.set(m, k);
    let mut i = m;
    while i > 0 {
        i = i - 1;
        for j in 0..k + 1 {
            let mut ok = may_be_empty(line, i) && bwd.get(i + 1, j);
            if !ok && j < k {
                let e = i + block(clue, j);
                ok = e < m && fits(empties, i, e) && may_be_empty(line, e) && bwd.get(e + 1, j + 1);
            }
            if ok {
                bwd.set(i, j);
            }
        }
    }

    // `reach[s]`: the furthest end of a block that can start at `s`.
    let mut reach: List<usize> = List::with_capacity(m);
    for _ in 0..m {
        reach.push(0);
    }
    // `can_empty[i]`: cell `i` is between blocks, or the empty cell after
    // one, in some way to place them all.
    let mut can_empty: List<bool> = List::with_capacity(m);
    for _ in 0..m {
        can_empty.push(false);
    }
    for i in 0..n {
        if may_be_empty(line, i) {
            for j in 0..k + 1 {
                if fwd.get(i, j) && bwd.get(i + 1, j) {
                    set(&mut can_empty, i);
                    break;
                }
            }
        }
        for j in 0..k {
            let e = i + block(clue, j);
            if fwd.get(i, j)
                && e < m
                && fits(empties, i, e)
                && may_be_empty(line, e)
                && bwd.get(e + 1, j + 1)
            {
                set(&mut can_empty, e);
                if let Some(r) = reach.get_mut(i) {
                    if *r < e {
                        *r = e;
                    }
                }
            }
        }
    }

    let mut changed: usize = 0;
    let mut covered: usize = 0;
    let mut i: usize = 0;
    while i < n {
        if let Some(r) = reach.get(i) {
            if *r > covered {
                covered = *r;
            }
        }
        let can_fill = i < covered;
        let empty = match can_empty.get(i) {
            Some(b) => *b,
            None => false,
        };
        let now = line[i];
        if !can_fill && !empty {
            return Contradiction;
        }
        if now == Unknown {
            if !can_fill {
                line[i] = Empty;
                changed = changed + 1;
            } else if !empty {
                line[i] = Filled;
                changed = changed + 1;
            }
        }
        i = i + 1;
    }
    Changed(changed)
}

/// Sets `l[i]`, if there's an `l[i]`.
fn set(l: &mut List<bool>, i: usize) {
    if let Some(b) = l.get_mut(i) {
        *b = true;
    }
}

/// The cells `text` draws: `#` filled, `x` empty, anything else unknown.
fn cells(text: &str) -> List<Cell> {
    let mut l = List::new();
    for c in text.chars() {
        l.push(if c == '#' { Filled } else if c == 'x' { Empty } else { Unknown });
    }
    l
}

/// How `line` is drawn, as `cells` reads it, with `.` for unknown.
fn text(line: &[Cell]) -> String {
    let mut s = String::new();
    for c in line.iter() {
        s.push(match *c {
            Unknown => '.',
            Filled => '#',
            Empty => 'x',
        });
    }
    s
}

/// What solving `start` with `clue` gives, drawn, or `"contradiction"`.
#[blame_caller]
fn solved(clue: &[usize], start: &str, want: &str) {
    let mut l = cells(start);
    let got = match solve(clue, l.as_mut_slice()) {
        Contradiction => String::from("contradiction"),
        Changed(_) => text(l.as_slice()),
    };
    assert_eq(&got.as_str(), &want);
}

#[test]
fn overlap_of_blocks_is_filled() {
    solved([3usize, 5].as_slice(), "..........", ".##..####.");
    solved([8usize].as_slice(), "..........", "..######..");
    solved([4usize, 5].as_slice(), "..........", "####x#####");
}

#[test]
fn an_empty_clue_empties_the_line() {
    solved(core::slice::empty(), ".....", "xxxxx");
    solved(core::slice::empty(), "..#..", "contradiction");
}

#[test]
fn known_cells_pin_blocks() {
    // A filled cell at the edge pins the block there.
    solved([3usize].as_slice(), "#.........", "###xxxxxxx");
    // Empty cells leave no room for a block before them.
    solved([2usize].as_slice(), ".x...", "xx.#.");
    // A filled cell far right decides which block reaches it.
    solved([1usize, 1].as_slice(), "......#", ".....x#");
}

#[test]
fn impossible_lines_are_contradictions() {
    solved([6usize].as_slice(), ".....", "contradiction");
    solved([2usize, 2].as_slice(), "....", "contradiction");
    solved([1usize].as_slice(), "#.#", "contradiction");
}

#[test]
fn nothing_new_when_nothing_is_certain() {
    solved([1usize].as_slice(), "...", "...");
    solved([2usize].as_slice(), ".#.", ".#.");
}
