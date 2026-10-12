use std::{ops::Range, sync::LazyLock};
use syntect::{
    easy::HighlightLines,
    highlighting::{Color, StyleModifier, Theme, ThemeItem},
    parsing::SyntaxSet,
    util::LinesWithEndings,
};

#[derive(Clone, Debug, PartialEq)]
pub struct CodeToken {
    pub range: Range<usize>,
    pub color: u32,
}

static SYNTAXES: LazyLock<SyntaxSet> = LazyLock::new(|| {
    let root = std::env::var_os("BENCHMARK_GRAMMAR_ROOT").map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            let executable = std::env::current_exe().expect("executable path");
            let app = executable.ancestors().find(|path| path.extension().is_some_and(|ext| ext == "app"));
            app.and_then(|path| path.parent()).map(|parent| parent.join("grammar-packs/v1"))
                .unwrap_or_else(|| std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../.build/chat-history-benchmarks/grammar-packs/v1"))
        });
    syntect::dumps::from_dump_file(root.join("syntect/syntaxes.pack"))
        .expect("Missing or invalid external syntect grammar pack; build benchmark assets first")
});
static THEME: LazyLock<Theme> = LazyLock::new(|| {
    let mut theme = Theme::default();
    theme.settings.foreground = Some(color(0xf5f5f5));
    for (scope, rgb) in [
        ("keyword, storage", 0xff7b72),
        ("string", 0xa5d6ff),
        (
            "constant.numeric, constant.language, variable.other.member",
            0x79c0ff,
        ),
        ("comment", 0x8b949e),
        ("entity.name.function, support.function", 0xd2a8ff),
        ("entity.name.type, support.type, support.class", 0xffa657),
        ("entity.name.tag", 0x7ee787),
        ("markup.heading", 0xd2a8ff),
        ("markup.raw", 0xa5d6ff),
        ("entity.other.attribute-name", 0x79c0ff),
    ] {
        theme.scopes.push(ThemeItem {
            scope: scope.parse().unwrap(),
            style: StyleModifier {
                foreground: Some(color(rgb)),
                ..Default::default()
            },
        });
    }
    theme
});
fn color(rgb: u32) -> Color {
    Color {
        r: (rgb >> 16) as u8,
        g: (rgb >> 8) as u8,
        b: rgb as u8,
        a: 255,
    }
}
fn extension(fence: &str) -> Option<&'static str> {
    Some(match fence.to_ascii_lowercase().as_str() {
        "bash" => "sh",
        "c" => "c",
        "cc" => "cpp",
        "cpp" => "cpp",
        "cs" => "cs",
        "csharp" => "cs",
        "css" => "css",
        "cxx" => "cpp",
        "go" => "go",
        "golang" => "go",
        "html" => "html",
        "java" => "java",
        "javascript" => "js",
        "js" => "js",
        "json" => "json",
        "jsx" => "js",
        "markdown" => "md",
        "md" => "md",
        "php" => "php",
        "py" => "py",
        "python" => "py",
        "rb" => "rb",
        "rs" => "rs",
        "ruby" => "rb",
        "rust" => "rs",
        "sh" => "sh",
        "shell" => "sh",
        "swift" => "swift",
        "ts" => "ts",
        "tsx" => "tsx",
        "typescript" => "ts",
        "yaml" => "yaml",
        "yml" => "yaml",
        "zsh" => "sh",
        _ => return None,
    })
}

// Called once while parsing a visible row; the row's Markdown cache owns tokens.
pub fn highlight(source: &str, fence: &str) -> Vec<CodeToken> {
    let Some(extension) = extension(fence) else {
        return vec![];
    };
    if source.len() > 51_200 || source.bytes().filter(|b| *b == b'\n').count() + 1 > 2_000 {
        return vec![];
    }
    let Some(syntax) = SYNTAXES.find_syntax_by_extension(extension) else {
        return vec![];
    };
    let mut highlighter = HighlightLines::new(syntax, &THEME);
    let mut result = Vec::new();
    let mut offset = 0;
    for line in LinesWithEndings::from(source) {
        let Ok(runs) = highlighter.highlight_line(line, &SYNTAXES) else {
            return vec![];
        };
        for (style, text) in runs {
            let c = style.foreground;
            let color = ((c.r as u32) << 16) | ((c.g as u32) << 8) | c.b as u32;
            result.push(CodeToken {
                range: offset..offset + text.len(),
                color,
            });
            offset += text.len();
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_languages_preserve_unicode_and_produce_colors() {
        let fixtures: serde_json::Value = serde_json::from_str(include_str!(
            "../../../benchmark/syntax-highlighting-fixtures.json"
        ))
        .unwrap();
        for fixture in fixtures.as_array().unwrap() {
            let source = fixture["source"].as_str().unwrap();
            let language = fixture["language"].as_str().unwrap();
            let runs = highlight(source, language);
            assert!(
                runs.iter().any(|r| r.color != 0xf5f5f5),
                "no colors for {language}"
            );
            let rebuilt = runs
                .iter()
                .map(|r| &source[r.range.clone()])
                .collect::<String>();
            assert_eq!(rebuilt, source, "{language}");
        }
    }
    #[test]
    fn same_whole_block_fallback_limits_as_rn() {
        for source in ["😀".repeat(12801), "a".repeat(51201), "\n".repeat(2000)] {
            assert!(highlight(&source, "js").is_empty());
        }
        assert!(highlight("const x = 42;", "unknown").is_empty());
    }
}
