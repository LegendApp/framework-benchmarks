import java.io.File
import java.time.Instant
import kotlinx.serialization.json.*

// Keep the UTF-8 document once. Object/array indexing skips string contents;
// large message and tool strings are decoded only when a row is requested.
class JsonRange(val bytes: ByteArray, val start: Int, val end: Int) {
    val kind: Char
        get() = bytes[start].toInt().toChar()

    fun string(): String =
        if (kind == '"')
            Json.parseToJsonElement(bytes.decodeToString(start, end)).jsonPrimitive.content
        else ""

    fun text(): DeferredText = DeferredText(kind == '"' && end - start > 2) { string() }

    fun boolean() = bytes.decodeToString(start, end) == "true"

    fun timestamp(): Long =
        if (kind == '"') runCatching { Instant.parse(string()).toEpochMilli() }.getOrDefault(0)
        else bytes.decodeToString(start, end).toDoubleOrNull()?.toLong() ?: 0

    private var fields: Map<String, JsonRange>? = null

    operator fun get(key: String): JsonRange? {
        if (kind != '{') return null
        if (fields == null) {
            val result = LinkedHashMap<String, JsonRange>()
            var i = space(start + 1)
            while (i < end && bytes[i] != '}'.code.toByte()) {
                val kEnd = skip(i)
                val name = JsonRange(bytes, i, kEnd).string()
                i = space(kEnd)
                require(bytes[i] == ':'.code.toByte())
                i = space(i + 1)
                val next = skip(i)
                result[name] = JsonRange(bytes, i, next)
                i = space(next)
                if (i < end && bytes[i] == ','.code.toByte()) i = space(i + 1) else break
            }
            fields = result
        }
        return fields!![key]
    }

    fun entries(): Map<String, JsonRange> {
        get("")
        return fields.orEmpty()
    }

    fun array(): List<JsonRange> {
        if (kind != '[') return emptyList()
        val out = ArrayList<JsonRange>()
        var i = space(start + 1)
        while (i < end && bytes[i] != ']'.code.toByte()) {
            val next = skip(i)
            out += JsonRange(bytes, i, next)
            i = space(next)
            if (i < end && bytes[i] == ','.code.toByte()) i = space(i + 1) else break
        }
        return out
    }

    fun valid() = runCatching { kind == '{' && skip(start) == end }.getOrDefault(false)

    private fun space(from: Int): Int {
        var i = from
        while (
            i < end &&
                (bytes[i] == 32.toByte() ||
                    bytes[i] == 9.toByte() ||
                    bytes[i] == 10.toByte() ||
                    bytes[i] == 13.toByte())
        ) i++
        return i
    }

    private fun skip(from: Int): Int {
        var i = from
        var depth = 0
        while (i < end) {
            when (bytes[i].toInt().toChar()) {
                '"' -> {
                    i++
                    while (i < end) {
                        if (bytes[i] == '\\'.code.toByte()) i += 2
                        else if (bytes[i++] == '"'.code.toByte()) break
                    }
                    if (depth == 0) return i
                    continue
                }
                '{',
                '[' -> depth++
                '}',
                ']' -> {
                    if (depth == 0) return i
                    depth--
                    if (depth == 0) return i + 1
                }
                ',',
                ':',
                ' ',
                '\r',
                '\n',
                '\t' -> if (depth == 0) return i
            }
            i++
        }
        require(depth == 0) { "Truncated JSON value" }
        return i
    }
}

private fun JsonRange?.s() = this?.string().orEmpty()

class DeferredText(val nonempty: Boolean = false, val decode: () -> String = { "" }) {
    val value by lazy(LazyThreadSafetyMode.PUBLICATION, decode)
}

fun literal(s: String) = DeferredText(s.isNotEmpty()) { s }

private fun joined(parts: List<DeferredText>) =
    DeferredText(parts.any { it.nonempty }) {
        parts.filter { it.nonempty }.joinToString("\n\n") { it.decode() }
    }

data class FileChange(val path: String, var additions: Int, var deletions: Int)

data class ChatRow(
    val kind: String,
    var markdown: DeferredText = DeferredText(),
    var toolName: String = "",
    var toolPreview: DeferredText = DeferredText(),
    var toolStatus: String = "",
    var image: Boolean = false,
    val images: List<String> = emptyList(),
    val files: List<FileChange> = emptyList(),
    val started: Long = 0,
    var ended: Long = started,
)

data class Document(
    val path: String,
    val rows: List<ChatRow>,
    val recordCount: Int,
    val sourceBytes: Int,
    val warnings: Int,
    val loadMs: Double,
    val scanMs: Double,
    val parseMs: Double,
)

fun elapsed(start: Long) = (System.nanoTime() - start) / 1e6

fun openDocument(provider: String, path: String): Document {
    val start = System.nanoTime()
    val bytes = File(path).readBytes()
    val load = elapsed(start)
    val scan = System.nanoTime()
    val records = ArrayList<JsonRange>()
    var line = 0
    for (i in 0..bytes.size) if (i == bytes.size || bytes[i] == 10.toByte()) {
        var begin = line
        var end = i
        while (begin < end && bytes[begin] <= 32 && bytes[begin] >= 0) begin++
        while (end > begin && bytes[end - 1] <= 32 && bytes[end - 1] >= 0) end--
        if (end > begin) records += JsonRange(bytes, begin, end)
        line = i + 1
    }
    val scanMs = elapsed(scan)
    val parse = System.nanoTime()
    val parser = DocumentParser()
    val rows = parser.parse(provider, records)
    return Document(
        path,
        rows,
        records.size,
        bytes.size,
        parser.warnings,
        load,
        scanMs,
        elapsed(parse),
    )
}

private class DocumentParser {
    var warnings = 0
    val rows = ArrayList<ChatRow>()
    val tools = HashMap<String, ChatRow>()

    fun message(
        kind: String,
        parts: List<DeferredText>,
        time: Long,
        images: List<String> = emptyList(),
        image: Boolean = false,
    ) {
        val text = joined(parts)
        if (text.nonempty || images.isNotEmpty() || image)
            rows += ChatRow(kind, text, image = image, images = images, started = time)
    }

    fun tool(id: String, name: String, preview: DeferredText, time: Long): ChatRow {
        val row =
            ChatRow(
                "tool",
                toolName = name.ifEmpty { "Tool" },
                toolPreview = preview,
                toolStatus = "unknown",
                started = time,
            )
        rows += row
        if (id.isNotEmpty()) tools[id] = row
        return row
    }

    fun result(id: String, preview: DeferredText, failed: Boolean, time: Long): ChatRow {
        val row = tools[id] ?: tool(id, "Tool", DeferredText(), time)
        row.toolStatus = if (failed) "failed" else "completed"
        row.ended = maxOf(row.ended, time)
        if (preview.nonempty) row.toolPreview = preview
        return row
    }

    fun parse(provider: String, records: List<JsonRange>): List<ChatRow> {
        require(provider == "codex" || provider == "claude")
        val valid = records.filter { it.valid().also { ok -> if (!ok) warnings++ } }
        if (provider == "codex") codex(valid) else claude(valid)
        return displayRows(rows)
    }

    fun codex(records: List<JsonRange>) {
        var cwd = ""
        var sawUser = false
        var turn = ""
        var files = ArrayList<FileChange>()
        fun flush() {
            if (files.isNotEmpty()) {
                rows += ChatRow("files", files = files)
                files = ArrayList()
            }
        }
        for (root in records) try {
            val type = root["type"].s()
            val p = root["payload"]
            val time = root["timestamp"]?.timestamp() ?: 0
            if (type.isEmpty() || p == null) {
                warnings++
                continue
            }
            if (type == "compacted") continue
            if (type == "session_meta" || type == "turn_context") {
                p["cwd"].s().takeIf { it.isNotEmpty() }?.let { cwd = it }
                continue
            }
            val t = p["type"].s()
            if (type == "event_msg") {
                if (t == "user_message") {
                    sawUser = true
                    flush()
                    turn = ""
                    val text = p["message"]?.text() ?: DeferredText()
                    if (!text.nonempty) warnings++
                    val images =
                        p["local_images"]?.array().orEmpty().map { it.string() }.toMutableList()
                    var placeholder = false
                    for (im in p["images"]?.array().orEmpty()) {
                        val s = im.string()
                        if (s.isEmpty() || s.length > 8192) placeholder = true else images += s
                    }
                    message("user", listOf(text), time, images, placeholder)
                } else if (t == "patch_apply_end" && p["success"]?.boolean() == true) {
                    val next = p["turn_id"].s()
                    if (turn.isNotEmpty() && next.isNotEmpty() && turn != next) flush()
                    turn = next
                    for ((path, change) in p["changes"]?.entries().orEmpty()) {
                        var add = 0
                        var del = 0
                        when (change["type"].s()) {
                            "update" -> {
                                var hunk = false
                                for (l in change["unified_diff"].s().lineSequence()) {
                                    if (l.startsWith("@@")) hunk = true
                                    else if (hunk && l.startsWith('+')) add++
                                    else if (hunk && l.startsWith('-')) del++
                                }
                            }
                            "add",
                            "delete" -> {
                                val c = change["content"].s()
                                val n =
                                    c.count { it == '\n' } +
                                        if (c.isNotEmpty() && !c.endsWith('\n')) 1 else 0
                                if (change["type"].s() == "add") add = n else del = n
                            }
                            else -> {
                                warnings++
                                continue
                            }
                        }
                        val relative = path.removePrefix("$cwd/")
                        val old = files.find { it.path == relative }
                        if (old == null) files += FileChange(relative, add, del)
                        else {
                            old.additions += add
                            old.deletions += del
                        }
                    }
                }
                continue
            }
            if (type != "response_item") continue
            when (t) {
                "message" -> {
                    val role = p["role"].s()
                    if (role == "assistant" || (role == "user" && !sawUser)) {
                        val parts = ArrayList<DeferredText>()
                        var image = false
                        val content = p["content"]
                        if (content?.kind == '"') parts += content.text()
                        else
                            for (b in content?.array().orEmpty()) when (b["type"].s()) {
                                "input_text",
                                "output_text",
                                "text" -> parts += b["text"]?.text() ?: DeferredText()
                                "input_image",
                                "image" -> image = true
                                "" -> Unit
                                else -> warnings++
                            }
                        message(role, parts, time, image = image)
                    }
                }
                "function_call",
                "custom_tool_call",
                "local_shell_call" ->
                    tool(
                        p["call_id"].s(),
                        p["name"].s(),
                        p[if (t == "custom_tool_call") "input" else "arguments"]?.text()
                            ?: DeferredText(),
                        time,
                    )
                "function_call_output",
                "custom_tool_call_output" ->
                    result(p["call_id"].s(), p["output"]?.text() ?: DeferredText(), false, time)
                "image_generation_call" -> {
                    val row =
                        tools[p["id"].s()]
                            ?: tool(p["id"].s(), "Image generation", DeferredText(), time)
                    val hasResult = p["result"]?.text()?.nonempty == true
                    row.toolStatus =
                        if (p["status"].s() == "failed") "failed"
                        else if (hasResult) "completed" else "unknown"
                    row.image = row.image || hasResult
                    row.ended = maxOf(row.ended, time)
                }
                "reasoning",
                "" -> Unit
                else -> warnings++
            }
        } catch (_: Exception) {
            warnings++
        }
        flush()
    }

    fun claude(records: List<JsonRange>) {
        val parent = HashMap<String, String>()
        var leaf = ""
        val valid =
            records.filter { root ->
                runCatching { root.kind == '{' && root["type"] != null }
                    .getOrDefault(false)
                    .also { if (!it) warnings++ }
            }
        for (r in valid) if (r["uuid"].s().isNotEmpty() && r["isSidechain"]?.boolean() != true) {
            leaf = r["uuid"].s()
            parent[leaf] = r["parentUuid"].s()
        }
        val chain = HashSet<String>()
        while (leaf.isNotEmpty() && chain.add(leaf)) {
            val p = parent[leaf]
            if (p == null) {
                warnings++
                break
            }
            leaf = p
        }
        for (r in valid) {
            val role = r["type"].s()
            if (
                r["isSidechain"]?.boolean() == true ||
                    r["uuid"].s() !in chain ||
                    role !in listOf("user", "assistant")
            )
                continue
            val time = r["timestamp"]?.timestamp() ?: 0
            val content = r["message"]?.get("content")
            if (content == null) {
                warnings++
                continue
            }
            if (content.kind == '"') {
                message(role, listOf(content.text()), time)
                continue
            }
            val parts = ArrayList<DeferredText>()
            var image = false
            val deferred = ArrayList<() -> Unit>()
            for (b in content.array()) when (b["type"].s()) {
                "text" -> parts += b["text"]?.text() ?: DeferredText()
                "image",
                "document" -> image = true
                "tool_use" -> deferred += {
                        tool(b["id"].s(), b["name"].s(), DeferredText(), time)
                        Unit
                    }
                "tool_result" -> {
                    val previews = ArrayList<DeferredText>()
                    var im = false
                    val value = b["content"]
                    if (value?.kind == '"') previews += value.text()
                    else
                        for (v in value?.array().orEmpty()) {
                            if (v.kind == '"') previews += v.text()
                            else
                                when (v["type"].s()) {
                                    "text" -> previews += v["text"]?.text() ?: DeferredText()
                                    "image" -> im = true
                                    else -> warnings++
                                }
                        }
                    deferred += {
                        val row =
                            result(
                                b["tool_use_id"].s(),
                                joined(previews),
                                b["is_error"]?.boolean() == true,
                                time,
                            )
                        row.image = row.image || im
                    }
                }
                "thinking" -> Unit
                else -> warnings++
            }
            message(role, parts, time, image = image)
            deferred.forEach { it() }
        }
    }
}

private fun visible(row: ChatRow): String {
    var s = row.markdown.decode()
    if (row.kind == "user" && (row.image || row.images.isNotEmpty())) {
        val t = s.trimStart('\r', '\n')
        val heading = "## My request for Codex:"
        if (t.startsWith("# Files mentioned by the user:") && heading in t)
            s = t.substringAfter(heading).trimStart('\r', '\n')
    }
    if (row.kind != "assistant") return s
    var fence = false
    var citation = false
    val out = ArrayList<String>()
    for (line in s.lineSequence()) {
        val t = line.trim()
        if (citation || (!fence && t.startsWith("<oai-mem-citation>")))
            citation = !t.contains("</oai-mem-citation>")
        else if (
            fence ||
                listOf(
                        "git-stage",
                        "git-commit",
                        "git-create-branch",
                        "git-push",
                        "git-create-pr",
                        "created-thread",
                        "code-comment",
                    )
                    .none { t.startsWith("::$it{") }
        )
            out += line
        if (!citation && (t.startsWith("```") || t.startsWith("~~~"))) fence = !fence
    }
    return out.joinToString("\n").trimEnd('\r', '\n')
}

private fun activity(row: ChatRow): String {
    val n = row.toolName.lowercase()
    val label =
        when {
            listOf("exec", "shell", "command", "bash").any { it in n } -> "Ran a command"
            "agent" in n -> "Worked with an agent"
            listOf("patch", "write", "edit").any { it in n } -> "Edited files"
            listOf("read", "open", "find", "glob", "grep").any { it in n } -> "Read files"
            listOf("web", "search", "browser").any { it in n } -> "Searched the web"
            "image" in n -> "Created an image"
            n.isEmpty() -> "Used a tool"
            else -> "Used ${n.replace('_', ' ').replace('-', ' ')}"
        }
    return label + if (row.toolStatus == "failed") " (failed)" else ""
}

private fun workLabel(rows: List<ChatRow>): String {
    val start = rows.map { it.started }.filter { it > 0 }.minOrNull() ?: return "Worked"
    val end = rows.map { it.ended }.filter { it > 0 }.maxOrNull() ?: return "Worked"
    val sec = maxOf(1, ((end - start) / 1000.0 + .5).toInt())
    val h = sec / 3600
    val m = sec % 3600 / 60
    val s = sec % 60
    return "Worked for " +
        if (h > 0) "${h}h" + if (m > 0) " ${m}m" else ""
        else if (m > 0) "${m}m" + if (s > 0) " ${s}s" else "" else "${s}s"
}

private fun displayRows(rows: List<ChatRow>): List<ChatRow> {
    val out = ArrayList<ChatRow>()
    var i = 0
    fun add(row: ChatRow) {
        out += row.copy(markdown = DeferredText(row.markdown.nonempty) { visible(row) })
    }
    while (i < rows.size) {
        if (rows[i].kind == "user") {
            add(rows[i++])
            continue
        }
        var end = i
        var lastTool = -1
        while (end < rows.size && rows[end].kind != "user") {
            if (rows[end].kind == "tool") lastTool = end
            end++
        }
        if (lastTool < 0) {
            add(rows[i++])
            continue
        }
        val group = rows.subList(i, lastTool + 1).toList()
        val preview =
            DeferredText(true) {
                val parts = ArrayList<String>()
                val activities = LinkedHashSet<String>()
                fun flush() {
                    if (activities.isNotEmpty()) {
                        parts +=
                            activities
                                .mapIndexed { j, a ->
                                    if (j == 0) a else a.replaceFirstChar { it.lowercase() }
                                }
                                .joinToString(", ")
                        activities.clear()
                    }
                }
                for (row in group) if (row.kind == "tool") activities += activity(row)
                else {
                    flush()
                    if (row.markdown.nonempty) parts += row.markdown.decode().take(4096)
                    if (row.image) parts += "Image or attachment omitted"
                }
                flush()
                parts.joinToString("\n\n").take(65536)
            }
        add(
            ChatRow(
                "tool",
                toolName = workLabel(group),
                toolPreview = preview,
                toolStatus =
                    if (group.any { it.kind == "tool" && it.toolStatus == "failed" }) "failed"
                    else if (group.any { it.kind == "tool" && it.toolStatus != "completed" })
                        "unknown"
                    else "completed",
            )
        )
        i = lastTool + 1
    }
    return out
}

fun contentDigest(rows: List<ChatRow>): String {
    var hash = 0xcbf29ce484222325UL
    fun field(s: String) {
        val b = s.toByteArray()
        for (v in ("${b.size}:".toByteArray() + b + byteArrayOf(59))) hash =
            (hash xor v.toUByte().toULong()) * 0x100000001b3UL
    }
    field(rows.size.toString())
    for (r in rows) {
        field(r.kind)
        field(r.markdown.decode())
        field(r.toolName)
        field(r.toolPreview.decode())
        field(r.toolStatus)
        field(if (r.image) "1" else "0")
        field(r.images.size.toString())
        r.images.forEach(::field)
        field(r.files.size.toString())
        r.files.forEach {
            field(it.path)
            field(it.additions.toString())
            field(it.deletions.toString())
        }
    }
    return hash.toString(16).padStart(16, '0')
}
