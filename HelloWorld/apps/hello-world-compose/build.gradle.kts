plugins {
    kotlin("jvm")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin { jvmToolchain(21) }

dependencies {
    implementation(compose.desktop.currentOs)
    implementation(compose.material)
}

compose.desktop {
    application {
        mainClass = "HelloKt"
        nativeDistributions {
            packageName = "HelloWorldCompose"
            packageVersion = "1.0.0"
            modules("java.desktop", "jdk.unsupported")
            macOS { bundleID = "so.legend.helloworld.compose" }
        }
        buildTypes.release.proguard {
            isEnabled.set(true)
            obfuscate.set(false)
        }
    }
}
