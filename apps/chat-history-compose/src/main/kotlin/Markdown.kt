import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.*
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.*
import java.io.File
import java.net.URLClassLoader
import kotlinx.serialization.json.*
import org.commonmark.ext.gfm.strikethrough.*
import org.commonmark.ext.gfm.tables.*
import org.commonmark.ext.task.list.items.*
import org.commonmark.node.*
import org.commonmark.parser.Parser

object MarkdownEngine {
    val parser =
        Parser.builder()
            .extensions(
                listOf(
                    TablesExtension.create(),
                    StrikethroughExtension.create(),
                    TaskListItemsExtension.create(),
                )
            )
            .build()
}

// Owned by one visited message in the current document; survives lazy-row disposal.
class MarkdownCache(val node: Node) {
    private val code = java.util.IdentityHashMap<Node, AnnotatedString>()

    fun highlighted(block: Node): AnnotatedString = code.getOrPut(block) {
        when (block) {
            is FencedCodeBlock -> SyntaxEngine.highlight(block.literal, block.info)
            is IndentedCodeBlock -> SyntaxEngine.highlight(block.literal, "")
            else -> error("Expected code block")
        }
    }
}

fun Node.children(): List<Node> = generateSequence(firstChild) { it.next }.toList()

object SyntaxEngine {
    private val directory by lazy {
        val root =
            System.getenv("BENCHMARK_GRAMMAR_ROOT")
                ?: System.getProperty("jpackage.app-path")?.let {
                    File(it)
                        .parentFile
                        .parentFile
                        .parentFile
                        .parentFile
                        .resolve("grammar-packs/v1")
                        .path
                }
                ?: File(".build/chat-history-benchmarks/grammar-packs/v1").absolutePath
        File(root, "compose-syntax").also {
            require(it.isDirectory) {
                "Missing Compose syntax pack: $it. Run benchmark:build --app compose."
            }
        }
    }
    private val policy by lazy {
        Json.parseToJsonElement(File(directory, "policy.json").readText()).jsonObject
    }
    private val instance by lazy {
        val jars =
            directory
                .listFiles()!!
                .filter { it.extension == "jar" }
                .map { it.toURI().toURL() }
                .toTypedArray()
        URLClassLoader(jars, javaClass.classLoader)
            .loadClass("benchmark.syntax.SyntaxPack")
            .getConstructor()
            .newInstance()
    }

    fun highlight(source: String, info: String): AnnotatedString {
        val code = source.trimEnd('\r', '\n')
        val lang =
            policy["languages"]!!
                .jsonObject[info.trim().split(Regex("\\s+")).first().lowercase()]
                ?.jsonPrimitive
                ?.content
        if (
            lang == null ||
                code.toByteArray().size > policy["maxBytes"]!!.jsonPrimitive.int ||
                code.count { it == '\n' } + 1 > policy["maxLines"]!!.jsonPrimitive.int
        )
            return AnnotatedString(code)
        @Suppress("UNCHECKED_CAST")
        val spans =
            instance.javaClass
                .getMethod("highlight", String::class.java, String::class.java)
                .invoke(instance, code, lang) as List<IntArray>
        return buildAnnotatedString {
            append(code)
            for (s in spans) if (s[0] >= 0 && s[1] <= code.length && s[1] > s[0])
                addStyle(SpanStyle(color = Color(0xff000000 or s[2].toLong())), s[0], s[1])
        }
    }
}

fun inline(node: Node, dark: Boolean): AnnotatedString = buildAnnotatedString {
    fun visit(n: Node) {
        val style =
            when (n) {
                is StrongEmphasis -> SpanStyle(fontWeight = FontWeight.Bold)
                is Emphasis -> SpanStyle(fontStyle = FontStyle.Italic)
                is Strikethrough -> SpanStyle(textDecoration = TextDecoration.LineThrough)
                is Code ->
                    SpanStyle(
                        fontFamily = FontFamily.Monospace,
                        color = if (dark) Color(0xffeb5757) else Color(0xff111827),
                        background = if (dark) Color(0xff2d2e30) else Color(0xffe5e7eb),
                    )
                is Link ->
                    SpanStyle(color = Color(0xff60a5fa), textDecoration = TextDecoration.Underline)
                else -> SpanStyle()
            }
        pushStyle(style)
        if (n is Link) pushStringAnnotation("URL", n.destination)
        when (n) {
            is org.commonmark.node.Text -> append(n.literal)
            is Code -> append(n.literal)
            is SoftLineBreak -> append(" ")
            is HardLineBreak -> append("\n")
            is HtmlInline -> append(n.literal)
            is Image -> append("Image or attachment omitted")
            is TaskListItemMarker -> append(if (n.isChecked) "☑ " else "☐ ")
            else -> n.children().forEach(::visit)
        }
        if (n is Link) pop()
        pop()
    }
    visit(node)
}

@Composable
fun Markdown(node: Node, dark: Boolean, cache: MarkdownCache) {
    val color = if (dark) Color(0xfff5f5f5) else Color(0xff111827)
    val border = if (dark) Color(0xff3e4042) else Color(0xffd1d5db)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (child in node.children()) when (child) {
            is org.commonmark.node.Paragraph,
            is Heading -> {
                val text = remember(child, dark) { inline(child, dark) }
                val size =
                    if (child is Heading) listOf(28, 24, 21, 18, 16, 15)[child.level - 1] else 15
                androidx.compose.foundation.text.ClickableText(
                    text,
                    style =
                        TextStyle(
                            color = color,
                            fontSize = size.sp,
                            lineHeight = (size * 1.5).sp,
                            fontWeight =
                                if (child is Heading) FontWeight.Bold else FontWeight.Normal,
                        ),
                    onClick = { at ->
                        text.getStringAnnotations("URL", at, at).firstOrNull()?.let {
                            runCatching {
                                java.awt.Desktop.getDesktop().browse(java.net.URI(it.item))
                            }
                        }
                    },
                )
            }
            is FencedCodeBlock -> CodePane(child, child.info, cache)
            is IndentedCodeBlock -> CodePane(child, "", cache)
            is BlockQuote ->
                Row(
                    Modifier.background(if (dark) Color(0xff202122) else Color(0xfff8fafc))
                        .padding(12.dp)
                ) {
                    Box(Modifier.width(3.dp).height(24.dp).background(border))
                    Box(Modifier.padding(start = 12.dp)) { Markdown(child, dark, cache) }
                }
            is BulletList,
            is OrderedList ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    child.children().forEachIndexed { index, item ->
                        Row {
                            Text(
                                item
                                    .children()
                                    .filterIsInstance<TaskListItemMarker>()
                                    .firstOrNull()
                                    ?.let { if (it.isChecked) "☑ " else "☐ " }
                                    ?: if (child is OrderedList)
                                        "${child.markerStartNumber + index}. "
                                    else "• ",
                                color = color,
                                modifier = Modifier.width(28.dp),
                            )
                            Box(Modifier.weight(1f)) { Markdown(item, dark, cache) }
                        }
                    }
                }
            is TableBlock ->
                Column(Modifier.fillMaxWidth().border(1.dp, border)) {
                    for (group in child.children()) for ((index, row) in
                        group.children().withIndex()) Row(
                        Modifier.fillMaxWidth()
                            .background(
                                if (group is TableHead || index % 2 == 1) border.copy(alpha = .3f)
                                else Color.Transparent
                            )
                    ) {
                        for (cell in row.children()) Text(
                            inline(cell, dark),
                            color = color,
                            fontSize = 15.sp,
                            modifier = Modifier.weight(1f).border(.5.dp, border).padding(8.dp),
                            fontWeight =
                                if (group is TableHead) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            is ThematicBreak -> Box(Modifier.fillMaxWidth().height(1.dp).background(border))
            is HtmlBlock -> Text(child.literal, color = color, fontSize = 15.sp)
            else -> Markdown(child, dark, cache)
        }
    }
}

@Composable
private fun CodePane(block: Node, info: String, cache: MarkdownCache) {
    val text = remember(block, cache) { cache.highlighted(block) }
    Column(Modifier.fillMaxWidth().background(Color(0xff111213), RoundedCornerShape(8.dp))) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(info.ifEmpty { "Code" }, color = Color(0xffa3a3a3), fontSize = 12.sp)
            Text(
                "Copy",
                color = Color(0xffa3a3a3),
                fontSize = 12.sp,
                modifier =
                    Modifier.clickable {
                        java.awt.Toolkit.getDefaultToolkit()
                            .systemClipboard
                            .setContents(java.awt.datatransfer.StringSelection(text.text), null)
                    },
            )
        }
        Text(
            text,
            color = Color(0xfff5f5f5),
            fontSize = 13.sp,
            lineHeight = 20.sp,
            fontFamily = FontFamily.Monospace,
            softWrap = false,
            modifier = Modifier.horizontalScroll(rememberScrollState()).padding(12.dp),
        )
    }
}
