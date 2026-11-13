//! Boards and puzzles: a grid of cells, and the clues of its rows and
//! columns.

use alloc::list::List;
use alloc::string::String;

use crate::line::Cell;
use crate::line::Cell::{Empty, Filled, Unknown};
use grid::Grid;

/// A grid of cells, `width()` by `height()`.
#[derive(Discard)]
pub struct Board { cells: Grid<Cell> }

impl Board {
    /// A board of unknown cells.
    pub fn new(width: usize, height: usize) -> Board {
        let Some(cells) = Grid::new(width, height, Unknown) else {
            panic("a board that big doesn't fit in memory")
        };
        Board { cells }
    }

    /// How many cells wide it is.
    pub fn width(&self) -> usize { self.cells.width() }

    /// How many cells high it is.
    pub fn height(&self) -> usize { self.cells.height() }

    /// The same board, again.
    pub fn copy(&self) -> Board { Board { cells: self.cells.copy() } }

    /// The cell in column `x` of row `y`; past the edge, empty.
    pub fn get(&self, x: usize, y: usize) -> Cell { self.cells.at(x, y).copied().unwrap_or(Empty) }

    /// Makes the cell in column `x` of row `y` `c`, if there's one there.
    pub fn set(&mut self, x: usize, y: usize, c: Cell) {
        if x < self.cells.width() && y < self.cells.height() {
            self.cells.set(x, y, c);
        }
    }

    /// Row `y`, into `line`, instead of what it held.
    pub fn row(&self, y: usize, line: &mut List<Cell>) {
        line.clear();
        for x in 0..self.width() {
            line.push(self.get(x, y));
        }
    }

    /// Column `x`, into `line`, instead of what it held.
    pub fn col(&self, x: usize, line: &mut List<Cell>) {
        line.clear();
        for y in 0..self.height() {
            line.push(self.get(x, y));
        }
    }

    /// Makes row `y` what `line` says.
    pub fn put_row(&mut self, y: usize, line: &[Cell]) {
        let mut x: usize = 0;
        for c in line {
            self.set(x, y, *c);
            x = x + 1;
        }
    }

    /// Makes column `x` what `line` says.
    pub fn put_col(&mut self, x: usize, line: &[Cell]) {
        let mut y: usize = 0;
        for c in line {
            self.set(x, y, *c);
            y = y + 1;
        }
    }

    /// How many cells aren't known.
    pub fn unknowns(&self) -> usize { self.cells.iter().filter(|c| **c == Unknown).count() }

    /// The first cell that isn't known, row by row, as its index.
    pub fn first_unknown(&self) -> Option<usize> {
        let mut i: usize = 0;
        for c in self.cells.iter() {
            if *c == Unknown {
                return Some(i);
            }
            i = i + 1;
        }
        None
    }
}

/// A puzzle: a name, a size, and the clue of each row and column.
#[derive(Discard)]
pub struct Puzzle {
    pub name: String,
    pub width: usize,
    pub height: usize,
    pub rows: List<List<usize>>,
    pub cols: List<List<usize>>,
}

impl Puzzle {
    /// The clue of row `y`, or none past the edge.
    pub fn row(&self, y: usize) -> &[usize] {
        match self.rows.get(y) {
            Some(c) => c.as_slice(),
            None => core::slice::empty(),
        }
    }

    /// The clue of column `x`, or none past the edge.
    pub fn col(&self, x: usize) -> &[usize] {
        match self.cols.get(x) {
            Some(c) => c.as_slice(),
            None => core::slice::empty(),
        }
    }

    /// The puzzle whose answer is `picture`, named `name`.
    pub fn of(name: &str, picture: &Board) -> Puzzle {
        let mut line = List::new();
        let mut rows = List::with_capacity(picture.height());
        for y in 0..picture.height() {
            picture.row(y, &mut line);
            rows.push(clue_of(line.as_slice()));
        }
        let mut cols = List::with_capacity(picture.width());
        for x in 0..picture.width() {
            picture.col(x, &mut line);
            cols.push(clue_of(line.as_slice()));
        }
        Puzzle {
            name: String::from(name),
            width: picture.width(),
            height: picture.height(),
            rows,
            cols,
        }
    }

    /// The largest number in a clue, or 0 if they're all empty.
    pub fn largest_clue(&self) -> usize {
        let mut most: usize = 0;
        for c in &self.rows {
            for b in c {
                if *b > most {
                    most = *b;
                }
            }
        }
        for c in &self.cols {
            for b in c {
                if *b > most {
                    most = *b;
                }
            }
        }
        most
    }

    /// Does `board`'s every row and column have its clue, reading what
    /// isn't known as empty?
    pub fn solved_by(&self, board: &Board) -> bool {
        let mut line = List::new();
        for y in 0..self.height {
            board.row(y, &mut line);
            if clue_of(line.as_slice()).as_slice() != self.row(y) {
                return false;
            }
        }
        for x in 0..self.width {
            board.col(x, &mut line);
            if clue_of(line.as_slice()).as_slice() != self.col(x) {
                return false;
            }
        }
        true
    }
}

/// The blocks of filled cells in `line`, in order: its clue.
pub fn clue_of(line: &[Cell]) -> List<usize> {
    let mut clue = List::new();
    let mut run: usize = 0;
    for c in line {
        if *c == Filled {
            run = run + 1;
        } else if run > 0 {
            clue.push(run);
            run = 0;
        }
    }
    if run > 0 {
        clue.push(run);
    }
    clue
}
