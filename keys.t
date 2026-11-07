//! Keys, read one at a time from the terminal in raw mode: arrows, and
//! letters for what to do. An arrow comes as three bytes, escape, `[` and
//! a letter; escape on its own, with nothing after it for a moment, is the
//! escape key.

use core::io::Read;
use core::time::Duration;
use std::io::{Error, ErrorKind, Raw};
use std::time::Clock;

/// What a key says to do.
#[derive(Copy, Discard, Eq)]
pub enum Key { Up, Down, Left, Right, Fill, Cross, Clear, Undo, Leave, Other }

/// The next key pressed.
pub fn read(raw: &mut Raw<'_>, clock: Clock) -> Result<Key, Error> {
    Ok(
        match byte(raw)? {
            // Escape: an arrow, if the rest of one comes at once.
            27 => {
                if !raw.wait(clock.now().add(Duration::from_millis(30)))? {
                    return Ok(Key::Leave);
                }
                if byte(raw)? != 91 {
                    return Ok(Key::Other);
                }
                match byte(raw)? {
                    65 => Key::Up,
                    66 => Key::Down,
                    67 => Key::Right,
                    68 => Key::Left,
                    _ => Key::Other,
                }
            },
            // `k`, `j`, `l` and `h`, as in vi, and `w`, `s`, `d` and `a`.
            107 | 119 => Key::Up,
            106 | 115 => Key::Down,
            108 | 100 => Key::Right,
            104 | 97 => Key::Left,
            // `f`, or space.
            102 | 32 => Key::Fill,
            // `x`.
            120 => Key::Cross,
            // `c`, or `.`.
            99 | 46 => Key::Clear,
            // `u`.
            117 => Key::Undo,
            // `q`, or Ctrl-C, which in raw mode is a key like any other.
            113 | 3 => Key::Leave,
            _ => Key::Other,
        },
    )
}

/// The next byte of input.
fn byte(raw: &mut Raw<'_>) -> Result<u8, Error> {
    let mut b = [0u8; 1];
    if raw.read(b.as_mut_slice())? == 0 {
        return Err(Error::new(ErrorKind::UnexpectedEnd));
    }
    Ok(b[0])
}
