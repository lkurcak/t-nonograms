//! Drawing a board with its clues as text.
//!
//! ```text
//!           1
//!         3 1 3 1 3
//!       +----------
//!   1 1 | # . # . .  1
//!     5 | # # # # #  2
//!       +----------
//!         1 2 3 4 5
//! ```
//!
//! Row clues are on the left, column clues on top, read downwards; `#` is
//! a filled cell, `x` one marked empty, and `.` one not known yet. Rows
//! are numbered on the right and columns at the bottom, from 1.

use core::fmt::Write;

use crate::board::{Board, Puzzle};
use crate::line::Cell::{Empty, Filled, Unknown};

/// How many digits `n` has in decimal.
fn digits(n: usize) -> usize {
    let mut d: usize = 1;
    let mut rest = n;
    while rest >= 10 {
        rest = rest / 10;
        d = d + 1;
    }
    d
}

/// Writes `n` spaces.
fn spaces<W: Write>(w: &mut W, n: usize) -> Result<(), W::Error> {
    for _ in 0..n {
        w.write_char(' ')?;
    }
    Ok(())
}

/// Writes `n` right-aligned in `width` columns.
fn number<W: Write>(w: &mut W, n: usize, width: usize) -> Result<(), W::Error> {
    let d = digits(n);
    if d < width {
        spaces(w, width - d)?;
    }
    w.put(&n)
}

/// How wide a clue is written: its numbers with a space between,
/// or `0` if it has none.
fn clue_width(clue: &[usize]) -> usize {
    if clue.is_empty() {
        return 1;
    }
    let mut n: usize = 0;
    for b in clue {
        n = n + digits(*b) + 1;
    }
    n - 1
}

/// How many numbers a column's clue is written with: `0` if it has none.
fn col_depth(clue: &[usize]) -> usize {
    if clue.is_empty() { 1 } else { clue.len() }
}

/// Writes a clue, its numbers with a space between, or `0` if it has none.
fn clue<W: Write>(w: &mut W, clue: &[usize]) -> Result<(), W::Error> {
    if clue.is_empty() {
        return w.write_char('0');
    }
    let mut first = true;
    for b in clue {
        if !first {
            w.write_char(' ')?;
        }
        first = false;
        w.put(b)?;
    }
    Ok(())
}

/// Writes `board`, with `p`'s clues around it.
pub fn board<W: Write>(w: &mut W, p: &Puzzle, board: &Board) -> Result<(), W::Error> {
    board_at(w, p, board, None)
}

/// Writes `board`, with `p`'s clues around it, and the cell at index
/// `cursor`, row by row, if there's one, shown in reverse, as a terminal
/// does after the escape sequence `ESC [ 7 m`.
pub fn board_at<W: Write>(
    w: &mut W,
    p: &Puzzle,
    board: &Board,
    cursor: Option<usize>,
) -> Result<(), W::Error> {
    // Each cell takes `cw` columns, enough for any number above or below.
    let mut most = p.largest_clue();
    if p.width > most {
        most = p.width;
    }
    let cw = digits(most) + 1;
    let mut rw: usize = 0;
    for y in 0..p.height {
        let n = clue_width(p.row(y));
        if n > rw {
            rw = n;
        }
    }
    let mut depth: usize = 1;
    for x in 0..p.width {
        let n = p.col(x).len();
        if n > depth {
            depth = n;
        }
    }

    // The column clues, lined up at the bottom.
    for t in 0..depth {
        spaces(w, rw + 2)?;
        // Up to the last column with a number here, so the line doesn't
        // end in spaces.
        let mut end: usize = 0;
        for x in 0..p.width {
            if t + col_depth(p.col(x)) >= depth {
                end = x + 1;
            }
        }
        for x in 0..end {
            let c = p.col(x);
            let len = col_depth(c);
            if t + len < depth {
                spaces(w, cw)?;
            } else {
                let i = t + len - depth;
                number(w, c.get(i).copied().unwrap_or(0), cw)?;
            }
        }
        w.write_char('\n')?;
    }
    rule(w, rw, cw * p.width)?;
    for y in 0..p.height {
        let c = p.row(y);
        spaces(w, rw - clue_width(c))?;
        clue(w, c)?;
        w.write_str(" |")?;
        for x in 0..p.width {
            spaces(w, cw - 1)?;
            let here = cursor == Some(y * p.width + x);
            if here {
                w.write_str("\u{1b}[7m")?;
            }
            w.write_char(match board.get(x, y) {
                Unknown => '.',
                Filled => '#',
                Empty => 'x',
            })?;
            if here {
                w.write_str("\u{1b}[0m")?;
            }
        }
        number(w, y + 1, digits(p.height) + 2)?;
        w.write_char('\n')?;
    }
    rule(w, rw, cw * p.width)?;
    spaces(w, rw + 2)?;
    for x in 0..p.width {
        number(w, x + 1, cw)?;
    }
    w.write_char('\n')
}

/// Writes the line above or below the grid.
fn rule<W: Write>(w: &mut W, rw: usize, n: usize) -> Result<(), W::Error> {
    spaces(w, rw + 1)?;
    w.write_char('+')?;
    for _ in 0..n {
        w.write_char('-')?;
    }
    w.write_char('\n')
}

/// Writes the picture `board` makes, `##` for each filled cell and spaces
/// for the rest, with nothing around it.
pub fn picture<W: Write>(w: &mut W, board: &Board) -> Result<(), W::Error> {
    for y in 0..board.height() {
        // Up to the last filled cell, so no line ends in spaces.
        let mut end: usize = 0;
        for x in 0..board.width() {
            if board.get(x, y) == Filled {
                end = x + 1;
            }
        }
        for x in 0..end {
            w.write_str(if board.get(x, y) == Filled { "##" } else { "  " })?;
        }
        w.write_char('\n')?;
    }
    Ok(())
}
