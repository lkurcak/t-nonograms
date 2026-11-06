//! Nonograms: a game, and a solver.
//!
//! It reads commands, one a line, after a `> ` prompt, until its input ends
//! or it's told to `quit`. `help` lists them.

use alloc::list::List;
use alloc::string::String;
use core::fmt::Write;
use std::io::{Stdin, Stdout};
use std::Os;

use grid::{Board, Puzzle};
use line::Cell;
use puzzles::Rng;
use solve::Answer;
use Command::{Check, Help, Hint, List, Load, Mark, New, Play, Quit, Show, Solve, Undo};
use line::Cell::{Empty, Filled, Unknown};

mod grid;
mod line;
mod parse;
mod puzzles;
mod show;
mod solve;

const HELP: [&str; 22] = [
    "Fill in cells so that each row and column has the blocks its clue says,",
    "in order, with at least one empty cell between blocks.",
    "",
    "  list            the puzzles there are",
    "  play N | NAME   play puzzle N from the list, or the one named NAME",
    "  new W H [SEED]  play a random puzzle, W wide and H high",
    "  load            type a puzzle's clues: the rows on one line, then the",
    "                  columns, each like `1 2, 3, 0` (lines apart with commas);",
    "                  the solver says how many solutions it has",
    "  f ROW COL       fill cells; ROW and COL can be ranges, like `2-5`",
    "  x ROW COL       mark cells empty",
    "  c ROW COL       clear cells",
    "  undo            take back the last move",
    "  hint            fill in a cell one row or column makes certain",
    "  check           say whether any cell is wrong",
    "  solve           give up, and see the answer",
    "  show            show the board again",
    "  help            this",
    "  quit            stop",
    "",
    "Rows are numbered on the right, from 1, and columns at the bottom.",
    "Try `play 1`.",
];

/// What a command can say to do.
#[derive(Copy, Discard, Eq)]
enum Command { Help, Quit, List, Play, New, Load, Mark(Cell), Undo, Hint, Check, Solve, Show }

/// The command `word` names.
fn command(word: &str) -> Option<Command> {
    Some(match word {
        "help" | "h" | "?" => Help,
        "quit" | "q" | "exit" => Quit,
        "list" => List,
        "play" | "p" => Play,
        "new" => New,
        "load" => Load,
        "fill" | "f" => Mark(Filled),
        "cross" | "x" => Mark(Empty),
        "clear" | "c" => Mark(Unknown),
        "undo" => Undo,
        "hint" => Hint,
        "check" => Check,
        "solve" => Solve,
        "show" => Show,
        _ => return None,
    })
}

/// A puzzle being played.
#[derive(Discard)]
struct Game {
    puzzle: Puzzle,
    /// What the player has filled in and marked so far.
    board: Board,
    /// The boards before each move, the last one last.
    history: List<Board>,
    /// The puzzle's solution, if it has exactly one.
    solution: Option<Board>,
    /// Has it been solved, or given up?
    over: bool,
}

/// Everything commands change: the game, and where random puzzles come
/// from.
#[derive(Discard)]
struct Session { game: Option<Game>, rng: Rng }

/// Reads commands until there are no more, or one says to stop.
fn main(os: Os) -> Result<(), std::io::Error> {
    let mut input = os.stdin;
    let mut out = os.stdout;
    let mut session = Session { game: None, rng: Rng::new(2026) };
    let mut line = String::new();
    out.line(&"Nonograms. Type `help` for the commands, or `play 1` to start.")?;
    out.put(&"> ")?;
    while input.read_line(&mut line)? {
        let words = parse::words(line.as_str());
        if let Some(first) = words.first() {
            let args = match words.as_slice().split_at(1) {
                Some(parts) => parts.tail,
                None => core::slice::empty(),
            };
            match command(*first) {
                Some(Quit) => return Ok(()),
                Some(c) => run(&mut out, &mut input, &mut session, c, args)?,
                None => out.line(&"There's no such command; `help` lists them.")?,
            }
        }
        out.put(&"> ")?;
    }
    out.line(&"")
}

/// Does what `c` says, with `args`, the words after it.
fn run(
    out: &mut Stdout,
    input: &mut Stdin,
    s: &mut Session,
    c: Command,
    args: &[&str],
) -> Result<(), std::io::Error> {
    match c {
        Help => {
            for l in HELP.iter() {
                out.line(l)?;
            }
            Ok(())
        },
        Quit => Ok(()),
        List => {
            for i in 0..puzzles::count() {
                let mut text = String::new();
                text.put(&(i + 1)).into_ok();
                text.push_str(". ");
                puzzles::describe(i, &mut text);
                out.line(&text)?;
            }
            Ok(())
        },
        Play => {
            let Some(which) = args.first() else { return usage(out, "play N, or play NAME") };
            let p = match parse::number(*which) {
                Some(n) => if n == 0 { None } else { puzzles::picture(n - 1) },
                None => puzzles::named(*which),
            };
            match p {
                Some(p) => start(out, s, p),
                None => out.line(&"There's no such puzzle; `list` lists them."),
            }
        },
        New => {
            let Some(w) = arg(args, 0) else { return usage(out, "new W H [SEED]") };
            let Some(h) = arg(args, 1) else { return usage(out, "new W H [SEED]") };
            if w == 0 || h == 0 || w > 30 || h > 30 {
                return out.line(&"A random puzzle is 1 to 30 cells wide and high.");
            }
            if let Some(seed) = arg(args, 2) {
                s.rng = Rng::new(seed as u64);
            }
            match puzzles::random(&mut s.rng, w, h) {
                Some(p) => start(out, s, p),
                None => out.line(&"No luck finding one; try again, or another size."),
            }
        },
        Load => {
            let mut rows = String::new();
            let mut cols = String::new();
            out.put(&"rows> ")?;
            if !input.read_line(&mut rows)? {
                return out.line(&"");
            }
            out.put(&"cols> ")?;
            if !input.read_line(&mut cols)? {
                return out.line(&"");
            }
            load(out, s, rows.as_str(), cols.as_str())
        },
        Mark(cell) => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            let p = &game.puzzle;
            let Some(rows) = args.get(0).and_then(|a| parse::span(*a, p.height)) else {
                return usage(out, "f ROW COL, with each a number or range on the board");
            };
            let Some(cols) = args.get(1).and_then(|a| parse::span(*a, p.width)) else {
                return usage(out, "f ROW COL, with each a number or range on the board");
            };
            game.history.push(game.board.copy());
            for y in rows.lo..rows.hi + 1 {
                for x in cols.lo..cols.hi + 1 {
                    game.board.set(x, y, cell);
                }
            }
            moved(out, game)
        },
        Undo => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            match game.history.pop() {
                Some(b) => {
                    game.board = b;
                    show::board(out, &game.puzzle, &game.board)
                },
                None => out.line(&"There's nothing to undo."),
            }
        },
        Hint => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            hint(out, game)
        },
        Check => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            let Some(solution) = &game.solution else {
                return out.line(&"This puzzle has no single solution to check against.");
            };
            match first_mistake(&game.board, solution) {
                Some(i) => {
                    out.line(&f"Something's wrong; look again at row {i / game.board.width + 1}.")
                },
                None => out.line(&"Nothing's wrong so far."),
            }
        },
        Solve => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            game.over = true;
            match &game.solution {
                Some(solution) => {
                    out.line(&"The answer:")?;
                    show::board(out, &game.puzzle, solution)
                },
                None => match solve::solve(&game.puzzle, &game.board) {
                    Some(Answer::Unique(b)) | Some(Answer::Many(b)) => {
                        out.line(&"An answer, from where you are:")?;
                        show::board(out, &game.puzzle, &b)
                    },
                    Some(Answer::None) => out.line(&"From where you are there's none; try `undo`."),
                    None => out.line(&"The solver gave up on it."),
                },
            }
        },
        Show => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            show::board(out, &game.puzzle, &game.board)
        },
    }
}

/// The number that's argument `i`, if there's one.
fn arg(args: &[&str], i: usize) -> Option<usize> { parse::number(*args.get(i)?) }

/// Says how a command is written.
fn usage(out: &mut Stdout, how: &str) -> Result<(), std::io::Error> {
    out.line(&f"Write it as `{how}`.")
}

/// The game being played, or `None`, having said why there's none.
fn playing<'a>(
    out: &mut Stdout,
    s: &'a mut Session,
) -> Result<Option<&'a mut Game>, std::io::Error> {
    match s.game.as_mut() {
        Some(game) => {
            if game.over {
                out.line(&"That puzzle is over; `play` or `new` starts another.")?;
                Ok(None)
            } else {
                Ok(Some(game))
            }
        },
        None => {
            out.line(&"There's no puzzle yet; try `play 1`, or `list`.")?;
            Ok(None)
        },
    }
}

/// Starts playing `p`, after working out its solution.
fn start(out: &mut Stdout, s: &mut Session, p: Puzzle) -> Result<(), std::io::Error> {
    let board = Board::new(p.width, p.height);
    let solution = match solve::solve(&p, &board) {
        Some(Answer::Unique(b)) => Some(b),
        Some(Answer::Many(_)) => {
            out.line(&"This puzzle has more than one solution; any will do.")?;
            None
        },
        Some(Answer::None) => return out.line(&"This puzzle has no solution."),
        None => {
            out.line(&"The solver gave up on this puzzle, so there are no hints.")?;
            None
        },
    };
    out.line(&f"Puzzle: {p.name}, {p.width}x{p.height}")?;
    show::board(out, &p, &board)?;
    s.game = Some(Game { puzzle: p, board, history: List::new(), solution, over: false });
    Ok(())
}

/// Reads a puzzle from its clues and starts playing it.
fn load(out: &mut Stdout, s: &mut Session, rows: &str, cols: &str) -> Result<(), std::io::Error> {
    let Some(rows) = parse::clues(rows) else {
        return out.line(&"Those row clues aren't numbers.")
    };
    let Some(cols) = parse::clues(cols) else {
        return out.line(&"Those column clues aren't numbers.")
    };
    let p = Puzzle {
        name: String::from("loaded"),
        width: cols.len(),
        height: rows.len(),
        rows,
        cols,
    };
    start(out, s, p)
}

/// Shows the board after a move, and says if it's solved.
fn moved(out: &mut Stdout, game: &mut Game) -> Result<(), std::io::Error> {
    show::board(out, &game.puzzle, &game.board)?;
    if game.puzzle.solved_by(&game.board) {
        game.over = true;
        out.line(&"Solved!")?;
        show::picture(out, &game.board)?;
    }
    Ok(())
}

/// The index of the first cell of `board` that `solution` says is wrong,
/// row by row: filled where it's empty, or marked empty where it's filled.
fn first_mistake(board: &Board, solution: &Board) -> Option<usize> {
    for y in 0..board.height {
        for x in 0..board.width {
            let have = board.get(x, y);
            if have != Unknown && have != solution.get(x, y) {
                return Some(y * board.width + x);
            }
        }
    }
    None
}

/// Fills in a cell that a row or column makes certain, and says why, or
/// says where a mistake is.
fn hint(out: &mut Stdout, game: &mut Game) -> Result<(), std::io::Error> {
    if let Some(solution) = &game.solution {
        if let Some(i) = first_mistake(&game.board, solution) {
            let w = game.board.width;
            return out.line(&f"Row {i / w + 1}, column {i % w + 1} is wrong.");
        }
    }
    let Some(step) = solve::next_step(&game.puzzle, &game.board) else {
        return out.line(
            &"No row or column says anything more on its own; something must be guessed.",
        );
    };
    let state = if step.cell == Filled { "filled" } else { "empty" };
    if step.by_row {
        out.line(&f"Row {step.y + 1} says column {step.x + 1} is {state}.")?;
    } else {
        out.line(&f"Column {step.x + 1} says row {step.y + 1} is {state}.")?;
    }
    game.history.push(game.board.copy());
    game.board.set(step.x, step.y, step.cell);
    moved(out, game)
}
