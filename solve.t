//! Solving a whole puzzle: solving lines until none says anything new, and
//! then, if cells are still unknown, guessing one and solving again.

use alloc::list::List;

use crate::grid::{Board, Puzzle};
use crate::line::{self, Cell, Outcome};

/// What solving a puzzle found.
#[derive(Discard)]
pub enum Answer {
    /// It has no solution.
    None,
    /// It has exactly this one.
    Unique(Board),
    /// It has more than one; this is one of them.
    Many(Board),
}

/// How many cells guessing, and the solving that follows it, may try
/// before solving gives up: enough for the puzzles here, few enough that a
/// bad one doesn't hang the game.
const BUDGET: usize = 200000;

/// What solving lines until none says anything new found.
#[derive(Copy, Discard, Eq)]
pub enum Spread {
    /// Some line can't be solved.
    Contradiction,
    /// Every line agrees with the board.
    Settled,
}

/// Solves lines of `board`, as `line::solve` does, until none says
/// anything new, starting from those `rows` and `cols` mark as maybe
/// having something to say.
fn settle(p: &Puzzle, board: &mut Board, rows: &mut List<bool>, cols: &mut List<bool>) -> Spread {
    let mut line: List<Cell> = List::new();
    let mut before: List<Cell> = List::new();
    loop {
        let mut any = false;
        for y in 0..p.height {
            if !take(rows, y) {
                continue;
            }
            any = true;
            board.row(y, &mut line);
            board.row(y, &mut before);
            match line::solve(p.row(y), line.as_mut_slice()) {
                Outcome::Contradiction => return Spread::Contradiction,
                Outcome::Changed(0) => {},
                Outcome::Changed(_) => {
                    mark_changes(before.as_slice(), line.as_slice(), cols);
                    board.put_row(y, line.as_slice());
                },
            }
        }
        for x in 0..p.width {
            if !take(cols, x) {
                continue;
            }
            any = true;
            board.col(x, &mut line);
            board.col(x, &mut before);
            match line::solve(p.col(x), line.as_mut_slice()) {
                Outcome::Contradiction => return Spread::Contradiction,
                Outcome::Changed(0) => {},
                Outcome::Changed(_) => {
                    mark_changes(before.as_slice(), line.as_slice(), rows);
                    board.put_col(x, line.as_slice());
                },
            }
        }
        if !any {
            return Spread::Settled;
        }
    }
}

/// Is `marks[i]` set? Unsets it.
fn take(marks: &mut List<bool>, i: usize) -> bool {
    match marks.get_mut(i) {
        Option::Some(m) => core::mem::replace(m, false),
        Option::None => false,
    }
}

/// Marks each line across where `before` and `after` differ.
fn mark_changes(before: &[Cell], after: &[Cell], across: &mut List<bool>) {
    let mut i: usize = 0;
    while i < before.len() && i < after.len() {
        if before[i] != after[i] {
            if let Option::Some(m) = across.get_mut(i) {
                *m = true;
            }
        }
        i = i + 1;
    }
}

/// `n` marks, all set.
fn all(n: usize) -> List<bool> {
    let mut marks = List::with_capacity(n);
    for _ in 0..n {
        marks.push(true);
    }
    marks
}

/// Solves lines of `board` until none says anything new, as a person does
/// with no guessing, and says whether that was consistent.
pub fn by_lines(p: &Puzzle, board: &mut Board) -> Spread {
    let mut rows = all(p.height);
    let mut cols = all(p.width);
    settle(p, board, &mut rows, &mut cols)
}

/// What the search has found so far.
#[derive(Discard)]
struct Search {
    /// The first solution found.
    first: Option<Board>,
    /// Was a second one found?
    second: bool,
    /// How many more guesses it may make.
    budget: usize,
}

/// Solves `p`, from what `start` says, finding up to two solutions.
/// `Option::None` if it gave up first.
pub fn solve(p: &Puzzle, start: &Board) -> Option<Answer> {
    let mut search = Search { first: Option::None, second: false, budget: BUDGET };
    let complete = explore(p, start.copy(), &mut search);
    let Search { first, second, .. } = search;
    if !complete {
        return Option::None;
    }
    Option::Some(match first {
        Option::None => Answer::None,
        Option::Some(b) => if second { Answer::Many(b) } else { Answer::Unique(b) },
    })
}

/// Looks for solutions from `board`, recording them in `search`, and says
/// whether it looked everywhere it needed to (`false` if it ran out of
/// budget).
fn explore(p: &Puzzle, mut board: Board, search: &mut Search) -> bool {
    if by_lines(p, &mut board) == Spread::Contradiction {
        return true;
    }
    let Option::Some(i) = board.first_unknown() else {
        if search.first.is_some() {
            search.second = true;
        } else {
            search.first = Option::Some(board);
        }
        return true;
    };
    if search.budget == 0 {
        return false;
    }
    search.budget = search.budget - 1;
    let x = i % board.width;
    let y = i / board.width;
    let mut guess = board.copy();
    guess.set(x, y, Cell::Filled);
    if !explore(p, guess, search) {
        return false;
    }
    if search.second {
        return true;
    }
    board.set(x, y, Cell::Empty);
    explore(p, board, search)
}

/// One cell that the clues of a single row or column, with what `board`
/// says, make certain: the first such, looking at rows and then columns.
#[derive(Copy, Discard)]
pub struct Step { pub x: usize, pub y: usize, pub cell: Cell, pub by_row: bool }

/// The first cell one line of `board` makes certain, if any.
pub fn next_step(p: &Puzzle, board: &Board) -> Option<Step> {
    let mut line: List<Cell> = List::new();
    for y in 0..p.height {
        board.row(y, &mut line);
        if let Outcome::Changed(_) = line::solve(p.row(y), line.as_mut_slice()) {
            for x in 0..p.width {
                let now = board.get(x, y);
                let then = line.get(x).copied().unwrap_or(now);
                if now != then {
                    return Option::Some(Step { x, y, cell: then, by_row: true });
                }
            }
        }
    }
    for x in 0..p.width {
        board.col(x, &mut line);
        if let Outcome::Changed(_) = line::solve(p.col(x), line.as_mut_slice()) {
            for y in 0..p.height {
                let now = board.get(x, y);
                let then = line.get(y).copied().unwrap_or(now);
                if now != then {
                    return Option::Some(Step { x, y, cell: then, by_row: false });
                }
            }
        }
    }
    Option::None
}

/// The puzzle with these clues, as `parse::clues` reads them.
fn clued(rows: &str, cols: &str) -> Puzzle {
    let rows = crate::parse::clues(rows).unwrap();
    let cols = crate::parse::clues(cols).unwrap();
    let name = alloc::string::String::from("test");
    Puzzle { name, width: cols.len(), height: rows.len(), rows, cols }
}

/// What `solve` says of the puzzle with these clues: `none`, `unique`,
/// `many` or `gave up`.
fn verdict(rows: &str, cols: &str) -> &'static str {
    let p = clued(rows, cols);
    match solve(&p, &Board::new(p.width, p.height)) {
        Option::Some(Answer::None) => "none",
        Option::Some(Answer::Unique(b)) => if p.solved_by(&b) { "unique" } else { "wrong" },
        Option::Some(Answer::Many(b)) => if p.solved_by(&b) { "many" } else { "wrong" },
        Option::None => "gave up",
    }
}

#[test]
fn solutions_are_counted_up_to_two() {
    assert_eq(&verdict("2, 0", "1, 1"), &"unique");
    // Either diagonal.
    assert_eq(&verdict("1, 1", "1, 1"), &"many");
    assert_eq(&verdict("2, 0", "0, 2"), &"none");
    // Clues that disagree on how many cells are filled.
    assert_eq(&verdict("1, 1", "2, 2"), &"none");
}

#[test]
fn guessing_finds_what_lines_cannot() {
    // Solving lines stops with cells unknown, but only one way to fill
    // them in fits every clue:
    //
    //     ..#..
    //     ##...
    //     ##..#
    //     ..##.
    //     .....
    let rows = "1, 2, 2 1, 2, 0";
    let cols = "2, 2, 1 1, 1, 1";
    let p = clued(rows, cols);
    let mut b = Board::new(5, 5);
    assert(by_lines(&p, &mut b) == Spread::Settled);
    assert(b.unknowns() > 0);
    assert_eq(&verdict(rows, cols), &"unique");
}

#[test]
fn a_step_comes_from_one_line() {
    let p = clued("3, 0, 1", "1, 2, 1");
    let s = next_step(&p, &Board::new(3, 3)).unwrap();
    assert(s.by_row);
    assert_eq(&s.y, &0);
    assert_eq(&s.x, &0);
    assert(s.cell == Cell::Filled);
}
