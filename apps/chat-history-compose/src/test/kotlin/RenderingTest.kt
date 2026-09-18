import java.io.File
import kotlin.test.*
import kotlinx.serialization.json.*
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.node.*

class RenderingTest {
    @Test
    fun codeCacheSurvivesRevisitsButIsOwnedByTheDocumentRow() {
        val cache = MarkdownCache(MarkdownEngine.parser.parse("```swift\nlet x = 1\n```"))
        val block = cache.node.firstChild
        val first = cache.highlighted(block)
        assertSame(first, cache.highlighted(block))
        val nextDocument = MarkdownCache(MarkdownEngine.parser.parse("```swift\nlet x = 1\n```"))
        assertNotSame(first, nextDocument.highlighted(nextDocument.node.firstChild))
        assertEquals(first, nextDocument.highlighted(nextDocument.node.firstChild))
    }

    @Test
    fun everySharedLanguageAndAliasHighlightsWithoutChangingText() {
        val fixtures =
            Json.parseToJsonElement(
                    File("benchmarks/chat-history/syntax-highlighting-fixtures.json").readText()
                )
                .jsonArray
        for (fixture in fixtures) {
            val language = fixture.jsonObject["language"]!!.jsonPrimitive.content
            val source = fixture.jsonObject["source"]!!.jsonPrimitive.content
            val result = SyntaxEngine.highlight(source, language)
            assertEquals(source.trimEnd('\r', '\n'), result.text, language)
            assertTrue(result.spanStyles.isNotEmpty(), "No syntax tokens for $language")
        }
    }

    @Test
    fun unknownAndOversizedCodeFallsBackWithoutRemovingSpaces() {
        for ((code, lang) in
            listOf(
                "  keep\t\n\n space \n" to "unknown",
                "x".repeat(51201) to "javascript",
                "x\n".repeat(2001) to "swift",
            )) {
            val result = SyntaxEngine.highlight(code, lang)
            assertEquals(code.trimEnd('\r', '\n'), result.text)
            assertTrue(result.spanStyles.isEmpty())
        }
    }

    @Test
    fun richMarkdownIsParsedAsStructure() {
        val node =
            MarkdownEngine.parser.parse(
                "# Heading\n\n**bold** *italic* ~~strike~~ [link](https://example.com)\n\n- [x] task\n\n> quote\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet x = 1\n```"
            )
        assertTrue(node.children().any { it is Heading })
        assertTrue(node.children().any { it is TableBlock })
        assertTrue(node.children().any { it is BlockQuote })
        assertTrue(node.children().any { it is FencedCodeBlock })
        assertTrue(node.children().any { it is BulletList })
    }
}
