//! What the keys do, from t-libs' `term`, which reads them: arrows, and
//! letters for what to do.

use std::io::{Error, Raw};
use std::time::Clock;
use term::Key::{self as Pressed, Char, Ctrl};

/// What a key says to do.
#[derive(Copy, Discard, Eq)]
pub enum Key { Up, Down, Left, Right, Fill, Cross, Clear, Undo, Leave, Other }

/// What the next key pressed says to do.
pub fn read(raw: &mut Raw<'_>, clock: Clock) -> Result<Key, Error> {
    Ok(
        match term::read(raw, clock)? {
            // Arrows; `k`, `j`, `l` and `h`, as in vi; and `w`, `s`, `d`
            // and `a`.
            Pressed::Up | Char('k') | Char('w') => Key::Up,
            Pressed::Down | Char('j') | Char('s') => Key::Down,
            Pressed::Right | Char('l') | Char('d') => Key::Right,
            Pressed::Left | Char('h') | Char('a') => Key::Left,
            Char('f') | Char(' ') => Key::Fill,
            Char('x') => Key::Cross,
            Char('c') | Char('.') => Key::Clear,
            Char('u') => Key::Undo,
            Char('q') | Ctrl('c') | Pressed::Escape => Key::Leave,
            _ => Key::Other,
        },
    )
}
