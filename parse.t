//! Reading what's typed: words, numbers, ranges of them, and clues.

use alloc::list::List;
use alloc::string::String;
use core::fmt::Write;

/// The words of `line`: what's between spaces, tabs and line breaks.
pub fn words(line: &str) -> List<&str> {
    let mut out = List::new();
    let bytes = line.as_bytes();
    let mut start: usize = 0;
    let mut i: usize = 0;
    while i <= bytes.len() {
        let gap = match bytes.get(i) {
            Option::Some(b) => *b == b' ' || *b == b'\t' || *b == b'\n' || *b == b'\r',
            Option::None => true,
        };
        if gap {
            if start < i {
                if let Option::Some(w) = line.get(start, i) {
                    out.push(w);
                }
            }
            start = i + 1;
        }
        i = i + 1;
    }
    out
}

/// The number `s` writes in decimal, if it's only digits and fits.
pub fn number(s: &str) -> Option<usize> {
    if s.is_empty() {
        return Option::None;
    }
    let mut n: usize = 0;
    for c in s.chars() {
        let '0'..='9' = c else { return Option::None };
        let d = (c as u32 - 0x30) as usize;
        n = checked_add(checked_mul(n, 10)?, d)?;
    }
    Option::Some(n)
}

/// Numbers `lo` to `hi`, both included.
#[derive(Copy, Discard)]
pub struct Span { pub lo: usize, pub hi: usize }

/// A number, `5`, or a range of them, `2-7` (or `7-2`), each at least 1
/// and at most `most`, as a span counted from 0.
pub fn span(s: &str, most: usize) -> Option<Span> {
    let mut dash: Option<usize> = Option::None;
    let mut i: usize = 0;
    for b in s.as_bytes().iter() {
        if *b == b'-' {
            dash = Option::Some(i);
        }
        i = i + 1;
    }
    let Span { lo, hi } = match dash {
        Option::None => {
            let n = number(s)?;
            Span { lo: n, hi: n }
        },
        Option::Some(d) => {
            let parts = s.split_at(d)?;
            let a = number(parts.head)?;
            let b = number(parts.tail.get(1, parts.tail.len())?)?;
            if a <= b { Span { lo: a, hi: b } } else { Span { lo: b, hi: a } }
        },
    };
    if lo == 0 || hi > most {
        return Option::None;
    }
    Option::Some(Span { lo: lo - 1, hi: hi - 1 })
}

/// Clues for several lines, written `1 2, 3, 0, 1 1 1`: the lines apart
/// with commas, the blocks of a line apart with spaces, and `0` (or
/// nothing) for a line with none. `None` if anything else is in it.
pub fn clues(text: &str) -> Option<List<List<usize>>> {
    let mut out = List::new();
    let bytes = text.as_bytes();
    let mut start: usize = 0;
    let mut i: usize = 0;
    while i <= bytes.len() {
        let comma = match bytes.get(i) {
            Option::Some(b) => *b == b',',
            Option::None => true,
        };
        if comma {
            let part = text.get(start, i)?;
            let mut clue = List::new();
            for w in words(part).iter() {
                let n = number(*w)?;
                if n > 0 {
                    clue.push(n);
                }
            }
            out.push(clue);
            start = i + 1;
        }
        i = i + 1;
    }
    Option::Some(out)
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
    let Option::Some(lines) = clues(text) else { return String::from("none") };
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
    assert_eq(&number("42").unwrap_or(0), &42);
    assert(number("").is_none());
    assert(number("4a").is_none());
    assert(number("-1").is_none());
    assert(number("99999999999999999999999").is_none());
}

#[test]
fn spans_count_from_one_and_stay_on_the_board() {
    let s = span("3", 5).unwrap();
    assert_eq(&s.lo, &2);
    assert_eq(&s.hi, &2);
    let s = span("5-2", 5).unwrap();
    assert_eq(&s.lo, &1);
    assert_eq(&s.hi, &4);
    assert(span("0", 5).is_none());
    assert(span("6", 5).is_none());
    assert(span("2-", 5).is_none());
    assert(span("-", 5).is_none());
}

#[test]
fn clues_are_lines_apart_with_commas() {
    assert_eq(&clue_text("1 2, 3,0,, 4 ").as_str(), &"1 2|3|||4");
    assert_eq(&clue_text("").as_str(), &"");
    assert_eq(&clue_text("1, x").as_str(), &"none");
}
