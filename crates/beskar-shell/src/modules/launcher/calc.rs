//! Zero-dependency safe math expression evaluator for the unified launcher.

/// Evaluates a math expression if valid and contains arithmetic operators.
pub fn evaluate_math(expr: &str) -> Option<f64> {
    let clean = expr.trim().to_lowercase();
    if clean.is_empty() {
        return None;
    }

    // Require at least one arithmetic character or math keyword to avoid matching plain words
    let has_math_op = clean.contains('+')
        || clean.contains('-')
        || clean.contains('*')
        || clean.contains('/')
        || clean.contains('^')
        || clean.contains('%')
        || clean.starts_with("sqrt")
        || clean.starts_with("sin")
        || clean.starts_with("cos")
        || clean.starts_with("tan")
        || clean.starts_with("abs");

    if !has_math_op {
        return None;
    }

    // Check for invalid non-math characters
    for ch in clean.chars() {
        if !ch.is_ascii_digit()
            && !matches!(
                ch,
                '+' | '-'
                    | '*'
                    | '/'
                    | '^'
                    | '%'
                    | '('
                    | ')'
                    | '.'
                    | ' '
                    | 's'
                    | 'q'
                    | 'r'
                    | 't'
                    | 'i'
                    | 'n'
                    | 'c'
                    | 'o'
                    | 'a'
                    | 'b'
                    | 'p'
                    | 'e'
            )
        {
            return None;
        }
    }

    let mut parser = Parser::new(&clean);
    let result = parser.parse_expression();
    if parser.has_remaining() || result.is_none() {
        None
    } else {
        result.filter(|v| v.is_finite())
    }
}

pub fn format_calc_result(val: f64) -> String {
    if (val.fract().abs() < 1e-9) && val.abs() < 1e15 {
        format!("{:.0}", val)
    } else {
        let s = format!("{:.6}", val);
        let trimmed = s.trim_end_matches('0').trim_end_matches('.');
        trimmed.to_string()
    }
}

struct Parser<'a> {
    chars: Vec<char>,
    pos: usize,
    _marker: std::marker::PhantomData<&'a ()>,
}

impl<'a> Parser<'a> {
    fn new(input: &'a str) -> Self {
        Self {
            chars: input.chars().filter(|c| !c.is_whitespace()).collect(),
            pos: 0,
            _marker: std::marker::PhantomData,
        }
    }

    fn peek(&self) -> Option<char> {
        self.chars.get(self.pos).copied()
    }

    fn next_char(&mut self) -> Option<char> {
        let ch = self.chars.get(self.pos).copied();
        if ch.is_some() {
            self.pos += 1;
        }
        ch
    }

    fn has_remaining(&self) -> bool {
        self.pos < self.chars.len()
    }

    fn parse_expression(&mut self) -> Option<f64> {
        let mut left = self.parse_term()?;

        while let Some(op) = self.peek() {
            if op == '+' || op == '-' {
                self.next_char();
                let right = self.parse_term()?;
                if op == '+' {
                    left += right;
                } else {
                    left -= right;
                }
            } else {
                break;
            }
        }
        Some(left)
    }

    fn parse_term(&mut self) -> Option<f64> {
        let mut left = self.parse_factor()?;

        while let Some(op) = self.peek() {
            if op == '*' || op == '/' || op == '%' {
                self.next_char();
                let right = self.parse_factor()?;
                if op == '*' {
                    left *= right;
                } else if op == '/' {
                    if right.abs() < 1e-12 {
                        return None;
                    }
                    left /= right;
                } else {
                    if right.abs() < 1e-12 {
                        return None;
                    }
                    left %= right;
                }
            } else {
                break;
            }
        }
        Some(left)
    }

    fn parse_factor(&mut self) -> Option<f64> {
        let mut left = self.parse_primary()?;

        if let Some('^') = self.peek() {
            self.next_char();
            let right = self.parse_factor()?;
            left = left.powf(right);
        }
        Some(left)
    }

    fn parse_primary(&mut self) -> Option<f64> {
        if let Some('+') = self.peek() {
            self.next_char();
            return self.parse_primary();
        }
        if let Some('-') = self.peek() {
            self.next_char();
            return self.parse_primary().map(|v| -v);
        }

        if let Some('(') = self.peek() {
            self.next_char();
            let expr = self.parse_expression()?;
            if self.next_char() != Some(')') {
                return None;
            }
            return Some(expr);
        }

        // Functions
        if self.consume_str("sqrt") {
            return self.parse_function_arg().and_then(|v| {
                if v >= 0.0 {
                    Some(v.sqrt())
                } else {
                    None
                }
            });
        }
        if self.consume_str("sin") {
            return self.parse_function_arg().map(|v| v.to_radians().sin());
        }
        if self.consume_str("cos") {
            return self.parse_function_arg().map(|v| v.to_radians().cos());
        }
        if self.consume_str("tan") {
            return self.parse_function_arg().map(|v| v.to_radians().tan());
        }
        if self.consume_str("abs") {
            return self.parse_function_arg().map(|v| v.abs());
        }
        if self.consume_str("pi") {
            return Some(std::f64::consts::PI);
        }
        if self.consume_str("e") {
            return Some(std::f64::consts::E);
        }

        self.parse_number()
    }

    fn parse_function_arg(&mut self) -> Option<f64> {
        if self.peek() == Some('(') {
            self.next_char();
            let val = self.parse_expression()?;
            if self.next_char() == Some(')') {
                Some(val)
            } else {
                None
            }
        } else {
            self.parse_primary()
        }
    }

    fn consume_str(&mut self, s: &str) -> bool {
        let chars: Vec<char> = s.chars().collect();
        if self.pos + chars.len() <= self.chars.len()
            && &self.chars[self.pos..self.pos + chars.len()] == chars.as_slice()
        {
            self.pos += chars.len();
            true
        } else {
            false
        }
    }

    fn parse_number(&mut self) -> Option<f64> {
        let start = self.pos;
        let mut has_dot = false;

        while let Some(ch) = self.peek() {
            if ch.is_ascii_digit() {
                self.next_char();
            } else if ch == '.' && !has_dot {
                has_dot = true;
                self.next_char();
            } else {
                break;
            }
        }

        if self.pos == start {
            return None;
        }

        let num_str: String = self.chars[start..self.pos].iter().collect();
        num_str.parse::<f64>().ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_evaluate_math() {
        assert_eq!(evaluate_math("25 * 4"), Some(100.0));
        assert_eq!(evaluate_math("(12 + 8) / 2"), Some(10.0));
        assert_eq!(evaluate_math("2 ^ 3"), Some(8.0));
        assert_eq!(evaluate_math("sqrt(16)"), Some(4.0));
        assert_eq!(evaluate_math("firefox"), None);
    }
}
