//! Where puzzles come from: pictures drawn here, and random ones.

use alloc::string::String;
use core::fmt::Write;
use rand::Rng;

use crate::board::{Board, Puzzle};
use crate::parse;
use crate::solve::{self, Answer, Spread};
use crate::line::Cell::{Empty, Filled};

/// A picture drawn here: its name, and its rows, one a line, `#` for a
/// filled cell and `.` for an empty one.
#[derive(Copy, Discard)]
struct Picture { name: &'static str, rows: &'static str }

/// The pictures, in the order they're listed.
const PICTURES: [Picture; 5] = [
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
    Picture {
        name: "heart",
        rows: "
            .##...##.
            ####.####
            #########
            #########
            .#######.
            ..#####..
            ...###...
            ....#....
        ",
    },
    Picture {
        name: "house",
        rows: "
            ....##....
            ...####...
            ..######..
            .########.
            ##########
            .#......#.
            .#.##...#.
            .#.##.###.
            .#....###.
            .########.
        ",
    },
    Picture {
        name: "sailboat",
        rows: "
            ......#.....
            ......##....
            ......###...
            .....####...
            ....#.####..
            ...##.#####.
            ..###.######
            .####.......
            ......#.....
            ############
            .##########.
            ..########..
        ",
    },
    Picture {
        name: "cat",
        rows: "
            .#...........#.
            .##.........##.
            .###.......###.
            .#############.
            .#############.
            .##..#####..##.
            .##.#.###.#.##.
            .##..#####..##.
            .######.######.
            ##############.
            .#####...######
            ..###########..
            ...#########...
            #....#####....#
            .###########...
        ",
    },
];

/// How many pictures there are.
pub fn count() -> usize { PICTURES.len() }

/// The name of picture `i`, from 0, and its size.
pub fn describe(i: usize, out: &mut String) {
    let pictures = PICTURES;
    let Some(pic) = pictures.get(i) else { return };
    out.push_str(pic.name);
    out.push_str(" (");
    let board = draw(pic.rows);
    out.put(&board.width()).into_ok();
    out.push('x');
    out.put(&board.height()).into_ok();
    out.push(')');
}

/// The board `rows` draw: `#` filled, anything else empty.
fn draw(text: &str) -> Board {
    let rows = parse::words(text);
    let rows = rows.as_slice();
    let mut width: usize = 0;
    for r in rows.iter() {
        let n = r.chars().count();
        if n > width {
            width = n;
        }
    }
    let mut board = Board::new(width, rows.len());
    let mut y: usize = 0;
    for r in rows.iter() {
        let mut x: usize = 0;
        for c in r.chars() {
            board.set(x, y, if c == '#' { Filled } else { Empty });
            x = x + 1;
        }
        while x < width {
            board.set(x, y, Empty);
            x = x + 1;
        }
        y = y + 1;
    }
    board
}

/// Picture `i`, from 0, as a puzzle, or `None` if there's no such picture.
pub fn picture(i: usize) -> Option<Puzzle> {
    let pictures = PICTURES;
    let pic = pictures.get(i)?;
    Some(Puzzle::of(pic.name, &draw(pic.rows)))
}

/// The picture named `name`, as a puzzle.
pub fn named(name: &str) -> Option<Puzzle> {
    let mut i: usize = 0;
    for pic in PICTURES.iter() {
        if pic.name == name {
            return picture(i);
        }
        i = i + 1;
    }
    None
}

/// How many pictures to draw, at most, looking for one a person can solve
/// a line at a time.
const TRIES: usize = 500;

/// A random puzzle, `width` by `height`, with one solution that solving
/// lines finds without guessing; or, after `TRIES` pictures without one,
/// the first with one solution; or `None` if there was none of that
/// either.
pub fn random(rng: &mut Rng, width: usize, height: usize) -> Option<Puzzle> {
    let mut fallback: Option<Puzzle> = None;
    for _ in 0..TRIES {
        let mut picture = Board::new(width, height);
        for y in 0..height {
            for x in 0..width {
                picture.set(x, y, if rng.chance(60) { Filled } else { Empty });
            }
        }
        let p = Puzzle::of("random", &picture);
        let mut board = Board::new(width, height);
        if solve::by_lines(&p, &mut board) == Spread::Settled && board.unknowns() == 0 {
            return Some(p);
        }
        if fallback.is_none() {
            if let Some(Answer::Unique(_)) = solve::solve(&p, &Board::new(width, height)) {
                fallback = Some(p);
            }
        }
    }
    fallback
}

#[test]
fn every_picture_has_one_solution() {
    for i in 0..count() {
        let p = picture(i).unwrap();
        match solve::solve(&p, &Board::new(p.width, p.height)) {
            Some(Answer::Unique(b)) => assert(p.solved_by(&b)),
            _ => panic("not unique"),
        }
    }
}
