//! Reading what's typed: words, numbers, ranges of them, and clues.

use alloc::list::List;
use alloc::string::String;
use core::fmt::Write;

/// The words of `line`: what's between whitespace.
pub fn words(line: &str) -> List<&str> {
    let mut out = List::new();
    for w in line.split_whitespace() {
        out.push(w);
    }
    out
}

/// The number `s` writes in decimal, if it's only digits (and maybe a
/// `+`) and fits.
pub fn number(s: &str) -> Option<usize> { s.parse().ok() }

/// Numbers `lo` to `hi`, both included.
#[derive(Copy, Debug, Discard, Eq)]
pub struct Span { pub lo: usize, pub hi: usize }

/// A number, `5`, or a range of them, `2-7` (or `7-2`), each at least 1
/// and at most `most`, as a span counted from 0.
pub fn span(s: &str, most: usize) -> Option<Span> {
    let Span { lo, hi } = match s.find('-') {
        None => {
            let n = number(s)?;
            Span { lo: n, hi: n }
        },
        Some(d) => {
            let (head, tail) = s.split_at(d)?;
            let a = number(head)?;
            let b = number(tail.strip_prefix('-')?)?;
            if a <= b { Span { lo: a, hi: b } } else { Span { lo: b, hi: a } }
        },
    };
    if lo == 0 || hi > most {
        return None;
    }
    Some(Span { lo: lo - 1, hi: hi - 1 })
}

/// Clues for several lines, written `1 2, 3, 0, 1 1 1`: the lines apart
/// with commas, the blocks of a line apart with spaces, and `0` (or
/// nothing) for a line with none. `None` if anything else is in it.
pub fn clues(text: &str) -> Option<List<List<usize>>> {
    let mut out = List::new();
    for part in text.split(',') {
        let mut clue = List::new();
        for w in part.split_whitespace() {
            let n = number(w)?;
            if n > 0 {
                clue.push(n);
            }
        }
        out.push(clue);
    }
    Some(out)
}

/// `parts`, with `|` between.
fn joined(parts: &[&str]) -> String {
    let mut s = String::new();
    let mut first = true;
    for p in parts.iter() {
        if !first {
            s.push('|');
        }
        first = false;
        s.push_str(*p);
    }
    s
}

/// What `clues` reads from `text`, written back with `|` between lines.
fn clue_text(text: &str) -> String {
    let Some(lines) = clues(text) else { return String::from("none") };
    let mut s = String::new();
    let mut first = true;
    for l in lines.iter() {
        if !first {
            s.push('|');
        }
        first = false;
        let mut first_block = true;
        for b in l.iter() {
            if !first_block {
                s.push(' ');
            }
            first_block = false;
            s.put(b).into_ok();
        }
    }
    s
}

#[test]
fn words_are_between_spaces() {
    let w = words("  f 3\t2-5  ");
    assert(w.len() == 3);
    assert_eq(&w[0], &"f");
    assert_eq(&w[2], &"2-5");
    assert_eq(&joined(words("a\nb\r\nc").as_slice()).as_str(), &"a|b|c");
    assert(words("   ").is_empty());
}

#[test]
fn numbers_are_digits_that_fit() {
    assert_eq(&number("42"), &Some(42));
    assert_eq(&number(""), &None);
    assert_eq(&number("4a"), &None);
    assert_eq(&number("-1"), &None);
    assert_eq(&number("99999999999999999999999"), &None);
}

#[test]
fn spans_count_from_one_and_stay_on_the_board() {
    assert_eq(&span("3", 5), &Some(Span { lo: 2, hi: 2 }));
    assert_eq(&span("5-2", 5), &Some(Span { lo: 1, hi: 4 }));
    assert_eq(&span("0", 5), &None);
    assert_eq(&span("6", 5), &None);
    assert_eq(&span("2-", 5), &None);
    assert_eq(&span("-", 5), &None);
}

#[test]
fn clues_are_lines_apart_with_commas() {
    assert_eq(&clue_text("1 2, 3,0,, 4 ").as_str(), &"1 2|3|||4");
    assert_eq(&clue_text("").as_str(), &"");
    assert_eq(&clue_text("1, x").as_str(), &"none");
}
