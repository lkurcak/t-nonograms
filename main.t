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
    Option::Some(match word {
        "help" | "h" | "?" => Command::Help,
        "quit" | "q" | "exit" => Command::Quit,
        "list" => Command::List,
        "play" | "p" => Command::Play,
        "new" => Command::New,
        "load" => Command::Load,
        "fill" | "f" => Command::Mark(Cell::Filled),
        "cross" | "x" => Command::Mark(Cell::Empty),
        "clear" | "c" => Command::Mark(Cell::Unknown),
        "undo" => Command::Undo,
        "hint" => Command::Hint,
        "check" => Command::Check,
        "solve" => Command::Solve,
        "show" => Command::Show,
        _ => return Option::None,
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
    let mut session = Session { game: Option::None, rng: Rng::new(2026) };
    let mut line = String::new();
    out.line(&"Nonograms. Type `help` for the commands, or `play 1` to start.")?;
    out.put(&"> ")?;
    while input.read_line(&mut line)? {
        let words = parse::words(line.as_str());
        if let Option::Some(first) = words.as_slice().first() {
            let args = match words.as_slice().split_at(1) {
                Option::Some(parts) => parts.tail,
                Option::None => core::slice::empty(),
            };
            match command(*first) {
                Option::Some(Command::Quit) => return Result::Ok(()),
                Option::Some(c) => run(&mut out, &mut input, &mut session, c, args)?,
                Option::None => out.line(&"There's no such command; `help` lists them.")?,
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
        Command::Help => {
            for l in HELP.iter() {
                out.line(l)?;
            }
            Result::Ok(())
        },
        Command::Quit => Result::Ok(()),
        Command::List => {
            for i in 0..puzzles::count() {
                let mut text = String::new();
                text.put(&(i + 1)).into_ok();
                text.push_str(". ");
                puzzles::describe(i, &mut text);
                out.line(&text)?;
            }
            Result::Ok(())
        },
        Command::Play => {
            let Option::Some(which) = args.first() else {
                return usage(out, "play N, or play NAME")
            };
            let p = match parse::number(*which) {
                Option::Some(n) => if n == 0 { Option::None } else { puzzles::picture(n - 1) },
                Option::None => puzzles::named(*which),
            };
            match p {
                Option::Some(p) => start(out, s, p),
                Option::None => out.line(&"There's no such puzzle; `list` lists them."),
            }
        },
        Command::New => {
            let Option::Some(w) = arg(args, 0) else { return usage(out, "new W H [SEED]") };
            let Option::Some(h) = arg(args, 1) else { return usage(out, "new W H [SEED]") };
            if w == 0 || h == 0 || w > 30 || h > 30 {
                return out.line(&"A random puzzle is 1 to 30 cells wide and high.");
            }
            if let Option::Some(seed) = arg(args, 2) {
                s.rng = Rng::new(seed as u64);
            }
            match puzzles::random(&mut s.rng, w, h) {
                Option::Some(p) => start(out, s, p),
                Option::None => out.line(&"No luck finding one; try again, or another size."),
            }
        },
        Command::Load => {
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
        Command::Mark(cell) => {
            let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };
            let p = &game.puzzle;
            let Option::Some(rows) = args.get(0).and_then(|a| parse::span(*a, p.height)) else {
                return usage(out, "f ROW COL, with each a number or range on the board");
            };
            let Option::Some(cols) = args.get(1).and_then(|a| parse::span(*a, p.width)) else {
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
        Command::Undo => {
            let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };
            match game.history.pop() {
                Option::Some(b) => {
                    game.board = b;
                    show::board(out, &game.puzzle, &game.board)
                },
                Option::None => out.line(&"There's nothing to undo."),
            }
        },
        Command::Hint => {
            let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };
            hint(out, game)
        },
        Command::Check => {
            let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };
            let Option::Some(solution) = &game.solution else {
                return out.line(&"This puzzle has no single solution to check against.");
            };
            match first_mistake(&game.board, solution) {
                Option::Some(i) => {
                    out.put(&"Something's wrong; look again at row ")?;
                    out.put(&(i / game.board.width + 1))?;
                    out.line(&".")
                },
                Option::None => out.line(&"Nothing's wrong so far."),
            }
        },
        Command::Solve => {
            let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };
            game.over = true;
            match &game.solution {
                Option::Some(solution) => {
                    out.line(&"The answer:")?;
                    show::board(out, &game.puzzle, solution)
                },
                Option::None => match solve::solve(&game.puzzle, &game.board) {
                    Option::Some(Answer::Unique(b)) | Option::Some(Answer::Many(b)) => {
                        out.line(&"An answer, from where you are:")?;
                        show::board(out, &game.puzzle, &b)
                    },
                    Option::Some(Answer::None) => out.line(
                        &"From where you are there's none; try `undo`.",
                    ),
                    Option::None => out.line(&"The solver gave up on it."),
                },
            }
        },
        Command::Show => {
            let Option::Some(game) = playing(out, s)? else { return Result::Ok(()) };
            show::board(out, &game.puzzle, &game.board)
        },
    }
}

/// The number that's argument `i`, if there's one.
fn arg(args: &[&str], i: usize) -> Option<usize> { parse::number(*args.get(i)?) }

/// Says how a command is written.
fn usage(out: &mut Stdout, how: &str) -> Result<(), std::io::Error> {
    out.put(&"Write it as `")?;
    out.put(&how)?;
    out.line(&"`.")
}

/// The game being played, or `None`, having said why there's none.
fn playing<'a>(
    out: &mut Stdout,
    s: &'a mut Session,
) -> Result<Option<&'a mut Game>, std::io::Error> {
    match s.game.as_mut() {
        Option::Some(game) => {
            if game.over {
                out.line(&"That puzzle is over; `play` or `new` starts another.")?;
                Result::Ok(Option::None)
            } else {
                Result::Ok(Option::Some(game))
            }
        },
        Option::None => {
            out.line(&"There's no puzzle yet; try `play 1`, or `list`.")?;
            Result::Ok(Option::None)
        },
    }
}

/// Starts playing `p`, after working out its solution.
fn start(out: &mut Stdout, s: &mut Session, p: Puzzle) -> Result<(), std::io::Error> {
    let board = Board::new(p.width, p.height);
    let solution = match solve::solve(&p, &board) {
        Option::Some(Answer::Unique(b)) => Option::Some(b),
        Option::Some(Answer::Many(_)) => {
            out.line(&"This puzzle has more than one solution; any will do.")?;
            Option::None
        },
        Option::Some(Answer::None) => return out.line(&"This puzzle has no solution."),
        Option::None => {
            out.line(&"The solver gave up on this puzzle, so there are no hints.")?;
            Option::None
        },
    };
    out.put(&"Puzzle: ")?;
    out.put(&p.name)?;
    out.put(&", ")?;
    out.put(&p.width)?;
    out.put(&"x")?;
    out.line(&p.height)?;
    show::board(out, &p, &board)?;
    s.game = Option::Some(Game { puzzle: p, board, history: List::new(), solution, over: false });
    Result::Ok(())
}

/// Reads a puzzle from its clues and starts playing it.
fn load(out: &mut Stdout, s: &mut Session, rows: &str, cols: &str) -> Result<(), std::io::Error> {
    let Option::Some(rows) = parse::clues(rows) else {
        return out.line(&"Those row clues aren't numbers.")
    };
    let Option::Some(cols) = parse::clues(cols) else {
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
    Result::Ok(())
}

/// The index of the first cell of `board` that `solution` says is wrong,
/// row by row: filled where it's empty, or marked empty where it's filled.
fn first_mistake(board: &Board, solution: &Board) -> Option<usize> {
    for y in 0..board.height {
        for x in 0..board.width {
            let have = board.get(x, y);
            if have != Cell::Unknown && have != solution.get(x, y) {
                return Option::Some(y * board.width + x);
            }
        }
    }
    Option::None
}

/// Fills in a cell that a row or column makes certain, and says why, or
/// says where a mistake is.
fn hint(out: &mut Stdout, game: &mut Game) -> Result<(), std::io::Error> {
    if let Option::Some(solution) = &game.solution {
        if let Option::Some(i) = first_mistake(&game.board, solution) {
            out.put(&"Row ")?;
            out.put(&(i / game.board.width + 1))?;
            out.put(&", column ")?;
            out.put(&(i % game.board.width + 1))?;
            return out.line(&" is wrong.");
        }
    }
    let Option::Some(step) = solve::next_step(&game.puzzle, &game.board) else {
        return out.line(
            &"No row or column says anything more on its own; something must be guessed.",
        );
    };
    if step.by_row {
        out.put(&"Row ")?;
        out.put(&(step.y + 1))?;
        out.put(&" says column ")?;
        out.put(&(step.x + 1))?;
    } else {
        out.put(&"Column ")?;
        out.put(&(step.x + 1))?;
        out.put(&" says row ")?;
        out.put(&(step.y + 1))?;
    }
    out.line(&if step.cell == Cell::Filled { " is filled." } else { " is empty." })?;
    game.history.push(game.board.copy());
    game.board.set(step.x, step.y, step.cell);
    moved(out, game)
}
