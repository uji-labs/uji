pub(crate) fn text(source: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return source.lines().map(str::to_string).collect();
    }
    let mut out = Vec::new();
    for line in source.lines() {
        if line.chars().count() <= width {
            out.push(line.to_string());
            continue;
        }
        let mut current = String::new();
        for word in line.split_whitespace() {
            let word_len = word.chars().count();
            if word_len > width {
                if !current.is_empty() {
                    out.push(std::mem::take(&mut current));
                }
                for ch in word.chars() {
                    if current.chars().count() == width {
                        out.push(std::mem::take(&mut current));
                    }
                    current.push(ch);
                }
                continue;
            }
            if current.chars().count() + 1 + word_len > width {
                out.push(std::mem::take(&mut current));
            } else if !current.is_empty() {
                current.push(' ');
            }
            current.push_str(word);
        }
        if !current.is_empty() {
            out.push(current);
        }
    }
    out
}

pub(crate) fn ranges(chars: &[char], width: usize) -> Vec<(usize, usize)> {
    if width == 0 || chars.is_empty() {
        return vec![(0, chars.len())];
    }
    let mut rows = Vec::new();
    let mut start = 0;
    while start < chars.len() {
        let hard_end = (start + width).min(chars.len());
        if hard_end == chars.len() {
            rows.push((start, hard_end));
            break;
        }
        let end = (start..hard_end)
            .rev()
            .find(|index| chars[*index] == ' ')
            .map_or(hard_end, |index| index + 1);
        rows.push((start, end));
        start = end;
    }
    rows
}
