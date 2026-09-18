import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.*

data class Summary(
    val id: String,
    val path: String,
    val provider: String,
    val title: String,
    val updated: Long,
)

fun jsonFile(file: File): JsonObject? =
    runCatching { Json.parseToJsonElement(file.readText()).jsonObject }.getOrNull()

fun JsonObject.text(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull.orEmpty()

fun JsonObject.time(key: String): Long =
    (get(key) as? JsonPrimitive)?.let {
        it.longOrNull ?: runCatching { Instant.parse(it.content).toEpochMilli() }.getOrDefault(0)
    } ?: 0

fun catalog(home: File, limit: Int = 20): List<Summary> {
    val codex = HashMap<String, Pair<String, Long>>()
    val claude = HashMap<String, Pair<String, Long>>()
    File(home, ".codex/session_index.jsonl")
        .takeIf { it.exists() }
        ?.forEachLine { line ->
            runCatching { Json.parseToJsonElement(line).jsonObject }
                .getOrNull()
                ?.let { r -> codex[r.text("id")] = r.text("thread_name") to r.time("updated_at") }
        }
    val claudeRoot = File(home, ".claude/projects")
    claudeRoot
        .walkTopDown()
        .filter { it.name == "sessions-index.json" }
        .forEach { file ->
            (jsonFile(file)?.get("entries") as? JsonArray)?.forEach { raw ->
                val r = raw.jsonObject
                val value =
                    r.text("summary").ifEmpty { r.text("firstPrompt") } to
                        maxOf(r.time("modified"), r.time("fileMtime"))
                claude[r.text("fullPath")] = value
                claude[r.text("sessionId")] = value
            }
        }
    val candidates = ArrayList<Pair<Summary, Boolean>>()
    for ((provider, roots) in
        listOf(
            "codex" to
                listOf(File(home, ".codex/sessions"), File(home, ".codex/archived_sessions")),
            "claude" to listOf(claudeRoot),
        )) {
        for (root in roots) for (file in
            root.walkTopDown().filter { it.isFile && it.extension == "jsonl" }) {
            if (
                provider == "claude" &&
                    ("/subagents/" in file.path || file.name.startsWith("agent-"))
            )
                continue
            val id = file.nameWithoutExtension.takeLast(36)
            val meta = if (provider == "codex") codex[id] else claude[file.path] ?: claude[id]
            val time = meta?.second?.takeIf { it > 0 } ?: file.lastModified()
            val fallback =
                provider.replaceFirstChar { it.uppercase() } +
                    " chat — " +
                    DateTimeFormatter.ofPattern("MMM d")
                        .withZone(ZoneId.systemDefault())
                        .format(Instant.ofEpochMilli(time))
            candidates +=
                Summary(
                    "$provider:$id",
                    file.path,
                    provider,
                    meta?.first?.takeIf { it.isNotEmpty() } ?: fallback,
                    time,
                ) to (provider == "claude" || meta != null)
        }
    }
    val seen = HashSet<String>()
    val out = ArrayList<Summary>()
    for ((s, indexed) in
        candidates.sortedWith(
            compareByDescending<Pair<Summary, Boolean>> { it.first.updated }.thenBy { it.first.id }
        )) {
        if (!seen.add(s.id)) continue
        if (!indexed) {
            val subagent =
                runCatching {
                        val bytes = File(s.path).inputStream().use { it.readNBytes(65536) }
                        val end = bytes.indexOf(10).let { if (it < 0) bytes.size else it }
                        JsonRange(bytes, 0, end)["payload"]?.get("source")?.get("subagent") != null
                    }
                    .getOrDefault(false)
            if (subagent) continue
        }
        out += s
        if (out.size == limit) break
    }
    return out
}
