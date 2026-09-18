package benchmark.syntax

import dev.snipme.highlights.Highlights
import dev.snipme.highlights.model.*
import javax.swing.text.Segment
import org.fife.ui.rsyntaxtextarea.*

// This entire module and its lexer dependencies live in the external pack.
// The app receives only UTF-16 ranges and RGB foreground colors.
class SyntaxPack {
    fun highlight(code: String, language: String): List<IntArray> {
        val other =
            mapOf(
                "css" to SyntaxConstants.SYNTAX_STYLE_CSS,
                "json" to SyntaxConstants.SYNTAX_STYLE_JSON,
                "xml" to SyntaxConstants.SYNTAX_STYLE_XML,
                "yaml" to SyntaxConstants.SYNTAX_STYLE_YAML,
                "markdown" to SyntaxConstants.SYNTAX_STYLE_MARKDOWN,
            )
        val style = other[language]
        if (style != null) {
            val maker = TokenMakerFactory.getDefaultInstance().getTokenMaker(style)
            val result = ArrayList<IntArray>()
            var state = Token.NULL
            var offset = 0
            for (line in code.split('\n')) {
                val chars = line.toCharArray()
                val segment = Segment(chars, 0, chars.size)
                var token: Token? = maker.getTokenList(segment, state, offset)
                while (token != null && token.isPaintable) {
                    val color =
                        when (token.type) {
                            Token.COMMENT_EOL,
                            Token.COMMENT_MULTILINE,
                            Token.COMMENT_DOCUMENTATION -> 0x7f848e
                            Token.LITERAL_STRING_DOUBLE_QUOTE,
                            Token.LITERAL_CHAR,
                            Token.MARKUP_TAG_ATTRIBUTE_VALUE -> 0x98c379
                            Token.RESERVED_WORD,
                            Token.RESERVED_WORD_2,
                            Token.DATA_TYPE -> 0xc678dd
                            Token.LITERAL_NUMBER_DECIMAL_INT,
                            Token.LITERAL_NUMBER_FLOAT,
                            Token.LITERAL_NUMBER_HEXADECIMAL,
                            Token.LITERAL_BOOLEAN -> 0xd19a66
                            Token.MARKUP_TAG_NAME,
                            Token.MARKUP_TAG_ATTRIBUTE,
                            Token.FUNCTION -> 0x61afef
                            else -> 0xabb2bf
                        }
                    result += intArrayOf(token.offset, token.offset + token.length(), color)
                    token = token.nextToken
                }
                state = maker.getLastTokenTypeOnLine(segment, state)
                offset += line.length + 1
            }
            return result
        }
        val lang =
            if (language == "bash") SyntaxLanguage.SHELL
            else SyntaxLanguage.valueOf(language.uppercase())
        return Highlights.Builder()
            .code(code)
            .language(lang)
            .theme(SyntaxThemes.atom(darkMode = true))
            .build()
            .getHighlights()
            .filterIsInstance<ColorHighlight>()
            .map { intArrayOf(it.location.start, it.location.end, it.rgb) }
    }
}
