import kotlin.test.*

class DocumentTest {
    @Test
    fun validatesIgnoredValuesWithoutBuildingTheirTrees() {
        for (source in listOf(
            """{"skip":[1,]}""", """{"skip":"\q"}""", """{"skip":01}""",
            """{"skip":[true}}""", """{"skip":"unterminated}""", "{} {}"
        )) {
            val bytes = source.toByteArray()
            assertFalse(JsonRange(bytes, 0, bytes.size).valid(), source)
        }
        val source = """{"z":"a\nb","a":[true,{"unused":"\u263a"}]}""".toByteArray()
        val value = JsonRange(source, 0, source.size)
        assertTrue(value.valid())
        assertEquals(listOf("z", "a"), value.entries().keys.toList())
        assertEquals("a\nb", value["z"]!!.string())
    }

    @Test
    fun codexParity() {
        val d = openDocument("codex", "packages/chat-history/tests/fixtures/codex.jsonl")
        assertEquals(14, d.recordCount)
        assertEquals(2, d.warnings)
        assertEquals(listOf("user", "tool", "assistant", "files"), d.rows.map { it.kind })
        assertEquals("ea203684aeae72fb", contentDigest(d.rows))
    }

    @Test
    fun claudeParity() {
        val d = openDocument("claude", "packages/chat-history/tests/fixtures/claude.jsonl")
        assertEquals(8, d.recordCount)
        assertEquals(1, d.warnings)
        assertEquals("4cb20d4c68d78408", contentDigest(d.rows))
    }

    @Test
    fun responseUser() {
        val d =
            openDocument("codex", "packages/chat-history/tests/fixtures/codex-response-user.jsonl")
        assertEquals(listOf("user", "assistant"), d.rows.map { it.kind })
    }

    @Test
    fun lazyEscapesAndUtf8() {
        val source =
            "{\"text\":\"hello \\u263a \\n 🌍\",\"nested\":{\"skip\":\"} ] \\\"\"},\"next\":true}"
                .toByteArray()
        val json = JsonRange(source, 0, source.size)
        assertEquals("hello ☺ \n 🌍", json["text"]!!.text().value)
        assertTrue(json["next"]!!.boolean())
    }
}
