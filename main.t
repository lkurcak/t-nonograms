//! Nonograms: a game, and a solver.
//!
//! It reads commands, one a line, after a `> ` prompt, until its input ends
//! or it's told to `quit`. `help` lists them. Words on its command line are
//! a first command: `nonograms play 3`, or `nonograms load puzzle.txt`.
//! When its input isn't typed at a terminal, it writes each line after its
//! prompt, so what it writes reads as a session at one. When it is, `keys`
//! plays with the arrow keys instead.

use alloc::list::List;
use alloc::string::String;
use core::fmt::Write;
use std::io::{Stdin, Stdout};
use std::fs::Fs;
use std::time::Clock;
use std::Os;

use board::{Board, Puzzle};
use keys::Key;
use line::Cell;
use puzzles::Rng;
use solve::Answer;
use Command::{Check, Help, Hint, Keys, List, Load, Mark, New, Play, Quit, Show, Solve, Undo};
use line::Cell::{Empty, Filled, Unknown};

mod board;
mod keys;
mod line;
mod parse;
mod puzzles;
mod show;
mod solve;

const HELP: [&str; 25] = [
    "Fill in cells so that each row and column has the blocks its clue says,",
    "in order, with at least one empty cell between blocks.",
    "",
    "  list            the puzzles there are",
    "  play N | NAME   play puzzle N from the list, or the one named NAME",
    "  new W H [SEED]  play a random puzzle, W wide and H high",
    "  load [FILE]     type a puzzle's clues, or read them from FILE: the rows",
    "                  on one line, then the columns, each like `1 2, 3, 0`",
    "                  (lines apart with commas); the solver says how many",
    "                  solutions it has",
    "  f ROW COL       fill cells; ROW and COL can be ranges, like `2-5`",
    "  x ROW COL       mark cells empty",
    "  c ROW COL       clear cells",
    "  undo            take back the last move",
    "  hint            fill in a cell one row or column makes certain",
    "  check           say whether any cell is wrong",
    "  solve           give up, and see the answer",
    "  show            show the board again",
    "  keys            play with the arrow keys: f or space fills, x crosses,",
    "                  c clears, u undoes, q or escape goes back to commands",
    "  help            this",
    "  quit            stop",
    "",
    "Rows are numbered on the right, from 1, and columns at the bottom.",
    "Try `play 1`.",
];

/// What a command can say to do.
#[derive(Copy, Discard, Eq)]
enum Command { Help, Quit, List, Play, New, Load, Mark(Cell), Undo, Hint, Check, Solve, Show, Keys }

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
        "keys" | "k" => Keys,
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
/// from; and the files `load` can read, and the clock `keys` tells escape
/// from an arrow by.
#[derive(Discard)]
struct Session { game: Option<Game>, rng: Rng, fs: Fs, clock: Clock }

/// Does what the command line says, if anything, then reads commands
/// until there are no more, or one says to stop.
fn main(os: Os) -> Result<(), std::io::Error> {
    let mut input = os.stdin;
    let mut out = os.stdout;
    // Random puzzles differ each run; `new W H SEED` gives the same again.
    let seed = os.entropy.u64()?;
    let mut session = Session { game: None, rng: Rng::new(seed), fs: os.fs, clock: os.clock };
    out.line("Nonograms. Type `help` for the commands, or `play 1` to start.")?;
    let mut first = List::new();
    for a in os.args.iter() {
        first.push(a);
    }
    if !first.is_empty() && !obey(&mut out, &mut input, &mut session, first.as_slice())? {
        return Ok(());
    }
    let mut line = String::new();
    out.put("> ")?;
    while read(&mut input, &mut out, &mut line)? {
        let words = parse::words(line.as_str());
        if !obey(&mut out, &mut input, &mut session, words.as_slice())? {
            return Ok(());
        }
        out.put("> ")?;
    }
    out.line("")
}

/// Does what command `words` says, if it's one: `false` if it says to stop.
fn obey(
    out: &mut Stdout,
    input: &mut Stdin,
    s: &mut Session,
    words: &[&str],
) -> Result<bool, std::io::Error> {
    let Some(first) = words.first() else { return Ok(true) };
    let args = match words.split_at(1) {
        Some(parts) => parts.tail,
        None => core::slice::empty(),
    };
    match command(*first) {
        Some(Quit) => return Ok(false),
        Some(c) => run(out, input, s, c, args)?,
        None => out.line("There's no such command; `help` lists them.")?,
    }
    Ok(true)
}

/// Reads the next line of `input` into `line`, as `read_line` does, and if
/// no one's typing it, writes it to `out`, after the prompt there, as a
/// terminal would.
fn read(input: &mut Stdin, out: &mut Stdout, line: &mut String) -> Result<bool, std::io::Error> {
    let more = input.read_line(line)?;
    if more && !input.is_terminal() {
        out.line(&line.as_str())?;
    }
    Ok(more)
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
                None => out.line("There's no such puzzle; `list` lists them."),
            }
        },
        New => {
            let Some(w) = arg(args, 0) else { return usage(out, "new W H [SEED]") };
            let Some(h) = arg(args, 1) else { return usage(out, "new W H [SEED]") };
            if w == 0 || h == 0 || w > 30 || h > 30 {
                return out.line("A random puzzle is 1 to 30 cells wide and high.");
            }
            if let Some(seed) = arg(args, 2) {
                s.rng = Rng::new(seed as u64);
            }
            match puzzles::random(&mut s.rng, w, h) {
                Some(p) => start(out, s, p),
                None => out.line("No luck finding one; try again, or another size."),
            }
        },
        Load => {
            if let Some(path) = args.first() {
                return load_file(out, s, *path);
            }
            let mut rows = String::new();
            let mut cols = String::new();
            out.put("rows> ")?;
            if !read(input, out, &mut rows)? {
                return out.line("");
            }
            out.put("cols> ")?;
            if !read(input, out, &mut cols)? {
                return out.line("");
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
                None => out.line("There's nothing to undo."),
            }
        },
        Hint => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            hint(out, game)
        },
        Check => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            let Some(solution) = &game.solution else {
                return out.line("This puzzle has no single solution to check against.");
            };
            match first_mistake(&game.board, solution) {
                Some(i) => {
                    out.line(&f"Something's wrong; look again at row {i / game.board.width() + 1}.")
                },
                None => out.line("Nothing's wrong so far."),
            }
        },
        Solve => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            game.over = true;
            match &game.solution {
                Some(solution) => {
                    out.line("The answer:")?;
                    show::board(out, &game.puzzle, solution)
                },
                None => match solve::solve(&game.puzzle, &game.board) {
                    Some(Answer::Unique(b)) | Some(Answer::Many(b)) => {
                        out.line("An answer, from where you are:")?;
                        show::board(out, &game.puzzle, &b)
                    },
                    Some(Answer::None) => out.line("From where you are there's none; try `undo`."),
                    None => out.line("The solver gave up on it."),
                },
            }
        },
        Show => {
            let Some(game) = playing(out, s)? else { return Ok(()) };
            show::board(out, &game.puzzle, &game.board)
        },
        Keys => {
            let clock = s.clock;
            let Some(game) = playing(out, s)? else { return Ok(()) };
            let Ok(mut raw) = input.raw() else {
                return out.line("`keys` needs a terminal to type at; use `f`, `x` and `c`.");
            };
            let mut x: usize = 0;
            let mut y: usize = 0;
            while !game.puzzle.solved_by(&game.board) {
                // Clear the screen, and draw the board, with the cursor.
                out.put("\u{1b}[H\u{1b}[2J")?;
                show::board_at(out, &game.puzzle, &game.board, Some(y * game.puzzle.width + x))?;
                out.line("arrows move; f fills, x crosses, c clears, u undoes, q goes back")?;
                match keys::read(&mut raw, clock)? {
                    Key::Up => y = if y > 0 { y - 1 } else { y },
                    Key::Down => y = if y + 1 < game.puzzle.height { y + 1 } else { y },
                    Key::Left => x = if x > 0 { x - 1 } else { x },
                    Key::Right => x = if x + 1 < game.puzzle.width { x + 1 } else { x },
                    Key::Fill => toggle(game, x, y, Filled),
                    Key::Cross => toggle(game, x, y, Empty),
                    Key::Clear => toggle(game, x, y, Unknown),
                    Key::Undo => {
                        if let Some(b) = game.history.pop() {
                            game.board = b;
                        }
                    },
                    Key::Leave => break,
                    Key::Other => {},
                }
            }
            raw.discard();
            moved(out, game)
        },
    }
}

/// Makes the cell at `x`, `y` `cell`, or unknown if it's that already, as a
/// move that can be undone.
fn toggle(game: &mut Game, x: usize, y: usize, cell: Cell) {
    game.history.push(game.board.copy());
    let now = if game.board.get(x, y) == cell { Unknown } else { cell };
    game.board.set(x, y, now);
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
                out.line("That puzzle is over; `play` or `new` starts another.")?;
                Ok(None)
            } else {
                Ok(Some(game))
            }
        },
        None => {
            out.line("There's no puzzle yet; try `play 1`, or `list`.")?;
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
            out.line("This puzzle has more than one solution; any will do.")?;
            None
        },
        Some(Answer::None) => return out.line("This puzzle has no solution."),
        None => {
            out.line("The solver gave up on this puzzle, so there are no hints.")?;
            None
        },
    };
    out.line(&f"Puzzle: {p.name}, {p.width}x{p.height}")?;
    show::board(out, &p, &board)?;
    s.game = Some(Game { puzzle: p, board, history: List::new(), solution, over: false });
    Ok(())
}

/// Reads a puzzle from the file at `path`, its row clues on the first line
/// and its column clues on the second, and starts playing it.
fn load_file(out: &mut Stdout, s: &mut Session, path: &str) -> Result<(), std::io::Error> {
    let text = match s.fs.read_to_string(path) {
        Ok(text) => text,
        Err(e) => return out.line(&f"Can't read {path}: {e}"),
    };
    let mut lines = text.as_str().lines();
    let rows = lines.next().unwrap_or("");
    let cols = lines.next().unwrap_or("");
    load(out, s, rows, cols)
}

/// Reads a puzzle from its clues and starts playing it.
fn load(out: &mut Stdout, s: &mut Session, rows: &str, cols: &str) -> Result<(), std::io::Error> {
    let Some(rows) = parse::clues(rows) else { return out.line("Those row clues aren't numbers.") };
    let Some(cols) = parse::clues(cols) else {
        return out.line("Those column clues aren't numbers.")
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
        out.line("Solved!")?;
        show::picture(out, &game.board)?;
    }
    Ok(())
}

/// The index of the first cell of `board` that `solution` says is wrong,
/// row by row: filled where it's empty, or marked empty where it's filled.
fn first_mistake(board: &Board, solution: &Board) -> Option<usize> {
    for y in 0..board.height() {
        for x in 0..board.width() {
            let have = board.get(x, y);
            if have != Unknown && have != solution.get(x, y) {
                return Some(y * board.width() + x);
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
            let w = game.board.width();
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
