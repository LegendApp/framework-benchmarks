import java.nio.file.Files
import kotlin.test.*

class CatalogTest {
    @Test
    fun benchmarkSamplesAreListedAlongsideMachineHistory() {
        val home = Files.createTempDirectory("compose-sample-catalog-test").toFile()
        try {
            val sessions = home.resolve(".codex/sessions").apply { mkdirs() }
            sessions.resolve("local.jsonl").writeText("{}\n")
            val config = home.resolve("benchmark.json")
            config.writeText(
                """{"samples":[{"id":"codex:sample","path":"${home.resolve("sample.jsonl").path}","provider":"codex","title":"Synthetic sample","updatedAt":4000000000000}]}"""
            )
            val result = catalog(home, benchmarkConfigPath = config.path)
            assertEquals(listOf("codex:sample", "codex:local"), result.map { it.id })
            assertEquals("Synthetic sample", result.first().title)
        } finally {
            home.deleteRecursively()
        }
    }

    @Test
    fun indexedDiscoveryExcludesSubagentsWithoutParsingTranscripts() {
        val home = Files.createTempDirectory("compose-catalog-test").toFile()
        try {
            val sessions = home.resolve(".codex/sessions").apply { mkdirs() }
            val a = "11111111-1111-1111-1111-111111111111"
            val b = "22222222-2222-2222-2222-222222222222"
            sessions.resolve("rollout-$a.jsonl").writeText("catalog must not parse this body")
            sessions
                .resolve("rollout-$b.jsonl")
                .writeText("""{"payload":{"source":{"subagent":{}}}}""")
            home
                .resolve(".codex/session_index.jsonl")
                .writeText(
                    """{"id":"$a","thread_name":"Indexed chat","updated_at":"2026-01-01T00:00:00Z"}"""
                )
            val result = catalog(home)
            assertEquals(listOf("codex:$a"), result.map { it.id })
            assertEquals("Indexed chat", result.single().title)
        } finally {
            home.deleteRecursively()
        }
    }
}
