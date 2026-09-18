plugins {
    kotlin("jvm")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin { jvmToolchain(21) }

dependencies {
    implementation(compose.desktop.currentOs)
    implementation(compose.material)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    implementation("org.commonmark:commonmark:0.24.0")
    implementation("org.commonmark:commonmark-ext-gfm-tables:0.24.0")
    implementation("org.commonmark:commonmark-ext-gfm-strikethrough:0.24.0")
    implementation("org.commonmark:commonmark-ext-task-list-items:0.24.0")
    testImplementation(kotlin("test"))
}

tasks.test { workingDir = rootProject.projectDir.parentFile.parentFile }

compose.desktop {
    application {
        mainClass = "ChatKt"
        nativeDistributions {
            packageName = "ChatHistoryCompose"
            packageVersion = "1.0.0"
            modules("java.desktop", "java.logging", "jdk.unsupported")
            macOS { bundleID = "so.legend.chathistory.compose" }
        }
        buildTypes.release.proguard {
            isEnabled.set(true)
            obfuscate.set(false)
            configurationFiles.from("proguard-rules.pro")
        }
    }
}

val testPolicy by
    tasks.registering(Copy::class) {
        from(rootProject.file("../../benchmarks/chat-history/syntax-highlighting-policy.json"))
        into(
            rootProject.file("../../.build/chat-history-benchmarks/grammar-packs/v1/compose-syntax")
        )
        rename { "policy.json" }
    }

tasks.test { dependsOn(":syntax:exportPack", testPolicy) }
