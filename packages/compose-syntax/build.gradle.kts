plugins { kotlin("jvm") }

kotlin { jvmToolchain(21) }

dependencies {
    implementation("dev.snipme:highlights:1.1.0")
    implementation("com.fifesoft:rsyntaxtextarea:3.6.0")
}

tasks.register<Copy>("exportPack") {
    dependsOn(tasks.jar)
    from(tasks.jar)
    from(configurations.runtimeClasspath) { exclude("kotlin-stdlib*.jar", "annotations-*.jar") }
    into(
        rootProject.layout.projectDirectory.dir(
            "../../.build/chat-history-benchmarks/grammar-packs/v1/compose-syntax"
        )
    )
}
