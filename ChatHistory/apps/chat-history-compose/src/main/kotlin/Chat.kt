import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.awt.ComposeWindow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.*
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*

class Benchmark {
    val config = System.getenv("CHAT_HISTORY_BENCHMARK_CONFIG")?.let { jsonFile(File(it)) }
    val enabled = config != null
    val targets = (config?.get("targets") as? JsonArray)?.map { it.jsonObject.text("id") }.orEmpty()

    init {
        if (enabled)
            require(config!!["version"]?.jsonPrimitive?.int == 2 && targets.size == 2) {
                "Unsupported benchmark manifest"
            }
    }

    val home =
        File(
            if (enabled)
                System.getenv("CHAT_HISTORY_BENCHMARK_HOME") ?: System.getProperty("user.home")
            else System.getProperty("user.home")
        )

    fun delay(name: String, fallback: Long) =
        config?.get(name)?.jsonPrimitive?.longOrNull ?: fallback

    @Synchronized
    fun emit(name: String, values: Map<String, Any?> = emptyMap()) {
        val path = System.getenv("CHAT_HISTORY_BENCHMARK_EVENTS") ?: return
        fun json(v: Any?): JsonElement =
            when (v) {
                null -> JsonNull
                is String -> JsonPrimitive(v)
                is Number -> JsonPrimitive(v)
                is Boolean -> JsonPrimitive(v)
                is Map<*, *> ->
                    JsonObject(v.entries.associate { it.key.toString() to json(it.value) })
                else -> error("Unsupported event value")
            }
        File(path)
            .appendText(
                JsonObject(
                        (values +
                                mapOf("name" to name, "timestampMs" to System.currentTimeMillis()))
                            .mapValues { json(it.value) }
                    )
                    .toString() + "\n"
            )
    }
}

private val settingsFile =
    File(
        System.getProperty("user.home"),
        "Library/Application Support/Legend Chat History Compose/settings.json",
    )

fun main(args: Array<String>) {
    if (args.firstOrNull() == "--verify-parser") {
        require(args.size == 3) { "--verify-parser <codex|claude> <path>" }
        val d = openDocument(args[1], args[2])
        println(
            buildJsonObject {
                put("rows", d.rows.size)
                put("records", d.recordCount)
                put("digest", contentDigest(d.rows))
                put("warnings", d.warnings)
            }
        )
        return
    }
    val benchmark = Benchmark()
    val initialAppearance = benchmark.config?.text("appearance")?.ifEmpty { "system" }
        ?: jsonFile(settingsFile)?.text("appearance")?.ifEmpty { "system" }
        ?: "system"
    // AWT otherwise defaults to Aqua even when the Compose content is dark.
    System.setProperty("apple.awt.application.appearance", when (initialAppearance) {
        "dark" -> "NSAppearanceNameDarkAqua"
        "light" -> "NSAppearanceNameAqua"
        else -> "system"
    })
    application {
        Window(
            onCloseRequest = ::exitApplication,
            title = "Chat History — Compose Multiplatform",
            state = rememberWindowState(width = 1280.dp, height = 720.dp),
        ) {
            LaunchedEffect(Unit) { benchmark.emit("windowShown") }
            ChatApp(benchmark, window)
        }
    }
}

@Composable
fun ChatApp(benchmark: Benchmark, window: ComposeWindow) {
    val scope = rememberCoroutineScope()
    val saved = remember { if (benchmark.enabled) null else jsonFile(settingsFile) }
    var appearance by remember {
        mutableStateOf(
            benchmark.config?.text("appearance")?.ifEmpty { "system" }
                ?: saved?.text("appearance")?.ifEmpty { "system" }
                ?: "system"
        )
    }
    val dark =
        when (appearance) {
            "dark" -> true
            "light" -> false
            else -> isSystemInDarkTheme()
        }
    val fg = if (dark) Color(0xfff5f5f5) else Color(0xff111827)
    val bg = if (dark) Color(0xff191a1b) else Color(0xfff5f6f8)
    SideEffect {
        // Keep native window controls and dragging, while matching the content theme.
        window.rootPane.putClientProperty("apple.awt.transparentTitleBar", true)
        window.rootPane.putClientProperty("apple.awt.windowTitleVisible", false)
        window.background = java.awt.Color(bg.toArgb(), true)
    }
    val muted = if (dark) Color(0xffa3a3a3) else Color(0xff6b7280)
    val border = if (dark) Color(0xff3e4042) else Color(0xffd1d5db)
    var summaries by remember { mutableStateOf(emptyList<Summary>()) }
    var selected by remember { mutableStateOf<Summary?>(null) }
    var document by remember { mutableStateOf<Document?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var settings by remember { mutableStateOf(false) }
    var generation by remember { mutableIntStateOf(0) }
    var phase by remember { mutableStateOf<String?>(null) }
    var started by remember { mutableLongStateOf(0) }
    var discoveryMs by remember { mutableDoubleStateOf(0.0) }
    val list = rememberLazyListState()
    var job by remember { mutableStateOf<Job?>(null) }
    fun save() {
        if (!benchmark.enabled) {
            settingsFile.parentFile.mkdirs()
            settingsFile.writeText(
                buildJsonObject {
                        put("appearance", appearance)
                        put("selectedId", selected?.id)
                    }
                    .toString()
            )
        }
    }
    fun select(summary: Summary, nextPhase: String?) {
        job?.cancel()
        generation++
        selected = summary
        loading = true
        error = null
        document = null
        phase = nextPhase
        started = System.nanoTime()
        save()
        job =
            scope.launch {
                try {
                    val d =
                        withContext(Dispatchers.IO) { openDocument(summary.provider, summary.path) }
                    list.requestScrollToItem(maxOf(0, d.rows.lastIndex))
                    document = d
                    loading = false
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    error = e.message
                    loading = false
                    benchmark.emit("error", mapOf("message" to e.toString()))
                }
            }
    }
    LaunchedEffect(Unit) {
        try {
            val begin = System.nanoTime()
            val all =
                withContext(Dispatchers.IO) {
                    val recent = catalog(benchmark.home)
                    if (benchmark.targets.any { id -> recent.none { it.id == id } })
                        catalog(benchmark.home, 50000)
                    else recent
                }
            discoveryMs = elapsed(begin)
            val visible = all.take(20).toMutableList()
            for (id in benchmark.targets) {
                val target = all.find { it.id == id } ?: error("Benchmark target not found: $id")
                if (visible.none { it.id == id }) visible += target
            }
            summaries = visible
            val initial =
                if (benchmark.enabled) visible.find { it.id == benchmark.targets.first() }
                else visible.find { it.id == saved?.text("selectedId") } ?: visible.firstOrNull()
            if (initial != null) select(initial, if (benchmark.enabled) "initial" else null)
            else loading = false
        } catch (e: Exception) {
            error = e.message
            loading = false
        }
    }
    LaunchedEffect(document, generation) {
        val d = document ?: return@LaunchedEffect
        val p = phase
        if (d.rows.isNotEmpty()) {
            snapshotFlow { list.layoutInfo }
                .first { info ->
                    info.totalItemsCount == d.rows.size &&
                        info.visibleItemsInfo.any { it.index == d.rows.lastIndex }
                }
        }
        // LazyColumn positions at the last row, then clamps its bottom to the
        // viewport even when that row is taller than the window.
        list.scrollBy(
            (list.layoutInfo.visibleItemsInfo.lastOrNull()?.size ?: 0).toFloat() +
                list.layoutInfo.afterContentPadding
        )
        withFrameNanos {}
        withFrameNanos {}
        delay(50)
        if (p == null) return@LaunchedEffect
        benchmark.emit(
            "contentReady",
            mapOf(
                "phase" to p,
                "path" to d.path,
                "durationMs" to elapsed(started),
                "discoveryMs" to if (p == "initial") discoveryMs else null,
                "recordCount" to d.recordCount,
                "rowCount" to d.rows.size,
                "sourceBytes" to d.sourceBytes,
                "timing" to
                    mapOf(
                        "loadMs" to d.loadMs,
                        "scanMs" to d.scanMs,
                        "parseMs" to d.parseMs,
                        "nativeTotalMs" to d.loadMs + d.scanMs + d.parseMs,
                    ),
            ),
        )
        launch(Dispatchers.Default) {
            benchmark.emit(
                "contentDigest",
                mapOf("phase" to p, "path" to d.path, "contentDigest" to contentDigest(d.rows)),
            )
        }
        if (p == "initial") {
            delay(benchmark.delay("topDelayMs", 3000))
            val top = System.nanoTime()
            if (d.rows.isNotEmpty()) list.scrollToItem(0)
            withFrameNanos {}
            withFrameNanos {}
            delay(50)
            benchmark.emit(
                "viewportReady",
                mapOf("phase" to "top", "path" to d.path, "durationMs" to elapsed(top)),
            )
            delay(benchmark.delay("switchDelayMs", 3000))
            summaries.find { it.id == benchmark.targets[1] }?.let { select(it, "switch") }
        }
    }
    val markdownCache =
        remember(document) { java.util.IdentityHashMap<ChatRow, MarkdownCache>() }
    MaterialTheme(
        colors =
            if (dark) darkColors(background = bg, surface = bg, onSurface = fg)
            else lightColors(background = bg, surface = bg, onSurface = fg)
    ) {
        Row(Modifier.fillMaxSize().background(bg)) {
            Column(
                Modifier.width(260.dp)
                    .fillMaxHeight()
                    .background(if (dark) Color(0xff242526) else Color.White)
                    .padding(12.dp)
            ) {
                Text(
                    "Chat History",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = fg,
                    modifier = Modifier.padding(8.dp, 16.dp),
                )
                Text(
                    "Recent conversations",
                    color = muted,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(8.dp),
                )
                LazyColumn(Modifier.weight(1f)) {
                    items(summaries, key = { it.id }) { s ->
                        Column(
                            Modifier.fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (selected?.id == s.id) border else Color.Transparent)
                                .clickable { select(s, null) }
                                .padding(10.dp)
                        ) {
                            Text(
                                s.title,
                                color = fg,
                                fontSize = 14.sp,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                s.provider.replaceFirstChar { it.uppercase() },
                                color = muted,
                                fontSize = 12.sp,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                    }
                }
                Text(
                    "Settings",
                    color = muted,
                    modifier =
                        Modifier.fillMaxWidth().clickable { settings = !settings }.padding(12.dp),
                )
            }
            Box(Modifier.width(1.dp).fillMaxHeight().background(border))
            Box(Modifier.weight(1f).fillMaxHeight()) {
                val layer = rememberGraphicsLayer()
                val density = LocalDensity.current
                val composerBlur = remember(density) {
                    val sigma = with(density) { 10.dp.toPx() }
                    // Compose BlurEffect takes a radius and reduces it to sigma.
                    // Use the same Gaussian sigma as Flutter and CSS backdrop blur.
                    org.jetbrains.skia.ImageFilter.makeBlur(
                        sigma, sigma, org.jetbrains.skia.FilterTileMode.CLAMP
                    ).asComposeRenderEffect()
                }
                var composerOffset by remember { mutableStateOf(Offset.Zero) }
                var transcriptOffset by remember { mutableStateOf(Offset.Zero) }
                Box(
                    Modifier.fillMaxSize()
                        .onGloballyPositioned { transcriptOffset = it.positionInRoot() }
                        .drawWithContent {
                            layer.record {
                                drawRect(bg)
                                this@drawWithContent.drawContent()
                            }
                            drawLayer(layer)
                        }
                ) {
                    val d = document
                    if (d != null)
                        key(d) {
                            // Bottom-aligned initial viewport, retaining Compose's normal lazy
                            // prefetch.
                            LazyColumn(
                                state = list,
                                modifier = Modifier.fillMaxSize(),
                                contentPadding =
                                    PaddingValues(
                                        start = 32.dp,
                                        end = 32.dp,
                                        top = 88.dp,
                                        bottom = 104.dp,
                                    ),
                                verticalArrangement = Arrangement.spacedBy(20.dp),
                            ) {
                                items(d.rows.size, key = { it }, contentType = { d.rows[it].kind }) { index ->
                                    val row = d.rows[index]
                                    Box(
                                        Modifier.fillMaxWidth(),
                                        contentAlignment = Alignment.TopCenter,
                                    ) {
                                        Box(
                                            Modifier.widthIn(max = 900.dp).fillMaxWidth(),
                                            contentAlignment = if (row.kind == "user") Alignment.TopEnd else Alignment.TopStart,
                                        ) {
                                            TranscriptRow(row, dark, markdownCache, benchmark.config?.get("loadImages")?.jsonPrimitive?.booleanOrNull ?: true)
                                        }
                                    }
                                }
                            }
                        }
                }
                Column(
                    Modifier.align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .background(bg.copy(alpha = .96f))
                        .padding(24.dp, 16.dp)
                ) {
                    Text(
                        selected?.title ?: "Chat History",
                        color = fg,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        selected?.provider?.replaceFirstChar { it.uppercase() }.orEmpty(),
                        color = muted,
                        fontSize = 12.sp,
                    )
                }
                if (loading)
                    Text("Loading…", color = muted, modifier = Modifier.align(Alignment.Center))
                error?.let {
                    Text(
                        it,
                        color = Color.Red,
                        modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    )
                }
                if (!settings)
                    Box(
                        Modifier.align(Alignment.BottomCenter)
                            .padding(start = 24.dp, end = 24.dp, bottom = 20.dp)
                            .widthIn(max = 860.dp)
                            .fillMaxWidth()
                            .height(60.dp)
                            .clip(RoundedCornerShape(26.dp))
                            .onGloballyPositioned { composerOffset = it.positionInRoot() }
                    ) {
                        Canvas(
                            Modifier.matchParentSize().graphicsLayer {
                                renderEffect = composerBlur
                            }
                        ) {
                            val delta = transcriptOffset - composerOffset
                            withTransform({ translate(delta.x, delta.y) }) { drawLayer(layer) }
                        }
                        Row(
                            Modifier.fillMaxSize()
                                .background(
                                    if (dark) Color(0xff202124).copy(alpha = .4f)
                                    else Color(0xfff5f5f7).copy(alpha = .44f)
                                )
                                .border(1.dp, border, RoundedCornerShape(26.dp))
                                .padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                "Send a test message that doesn't actually do anything",
                                color = muted,
                                fontSize = 15.sp,
                                modifier = Modifier.weight(1f),
                                maxLines = 1,
                            )
                            Box(
                                Modifier.size(36.dp)
                                    .background(
                                        Color(0xff60a5fa).copy(alpha = .3f),
                                        RoundedCornerShape(18.dp),
                                    ),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("↑", color = Color.White, fontSize = 24.sp)
                            }
                        }
                    }
                if (settings)
                    Column(
                        Modifier.fillMaxSize().background(bg).padding(32.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Text("Settings", color = fg, fontSize = 24.sp)
                        Text("Appearance", color = fg)
                        Row {
                            for (mode in listOf("system", "light", "dark")) TextButton(
                                onClick = {
                                    appearance = mode
                                    save()
                                }
                            ) {
                                Text(mode)
                            }
                        }
                        Text("Images are omitted in this text-only benchmark.", color = muted)
                        Button(onClick = { settings = false }) { Text("Done") }
                    }
            }
        }
    }
}

@Composable
private fun TranscriptRow(
    row: ChatRow,
    dark: Boolean,
    cache: java.util.IdentityHashMap<ChatRow, MarkdownCache>,
    loadImages: Boolean,
) {
    val fg = if (dark) Color(0xfff5f5f5) else Color(0xff111827)
    val muted = if (dark) Color(0xffa3a3a3) else Color(0xff6b7280)
    var expanded by remember { mutableStateOf(false) }
    if (row.kind == "tool") {
        Column {
            Text(
                "${if (expanded) "⌄" else "›"} ${row.toolName}",
                color = muted,
                fontSize = 13.sp,
                modifier = Modifier.clickable { expanded = !expanded },
            )
            if (expanded)
                Text(
                    row.toolPreview.value,
                    color = muted,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(12.dp),
                )
        }
    } else if (row.kind == "files") {
        Column {
            Text(
                "${if (expanded) "⌄" else "›"} ${row.files.size} files changed",
                color = muted,
                fontSize = 13.sp,
                modifier = Modifier.clickable { expanded = !expanded },
            )
            if (expanded)
                row.files.forEach {
                    Text(
                        "${it.path}  +${it.additions} −${it.deletions}",
                        color = fg,
                        fontSize = 13.sp,
                    )
                }
        }
    } else {
        val node =
            remember(row) {
                cache.getOrPut(row) { MarkdownCache(MarkdownEngine.parser.parse(row.markdown.value)) }
            }
        Column(
            Modifier
                .then(if (row.kind == "user" && loadImages && row.images.isNotEmpty()) Modifier.widthIn(max = 332.dp) else Modifier)
                .fillMaxWidth()
                .then(
                    if (row.kind == "user")
                        Modifier.background(
                                if (dark) Color(0xff2d2e30) else Color(0xfff3f4f6),
                                RoundedCornerShape(12.dp),
                            )
                            .padding(16.dp)
                    else Modifier
                )
        ) {
            if (loadImages) row.images.forEach { source -> InlineAttachment(source) }
            Markdown(node.node, dark, node)
            if (row.image || (!loadImages && row.images.isNotEmpty()))
                Text("Image or attachment omitted", color = muted, fontSize = 13.sp)
        }
    }
}

@Composable
private fun InlineAttachment(source: String) {
    val bitmap by produceState<ImageBitmap?>(null, source) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                val file = if (source.startsWith("file:")) File(java.net.URI(source)) else File(source)
                org.jetbrains.skia.Image.makeFromEncoded(file.readBytes()).toComposeImageBitmap()
            }.getOrNull()
        }
    }
    bitmap?.let {
        Image(it, "Attached image", Modifier.widthIn(max = 300.dp).width(300.dp)
            .aspectRatio(it.width.toFloat() / it.height).clip(RoundedCornerShape(12.dp)),
            contentScale = ContentScale.Fit)
        Spacer(Modifier.height(8.dp))
    }
}
