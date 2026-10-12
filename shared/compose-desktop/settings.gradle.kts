pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "desktop-comparison"

include(":hello", ":chat", ":syntax")

project(":hello").projectDir = file("../../apps/hello-world-compose")

project(":chat").projectDir = file("../../apps/chat-history-compose")

project(":syntax").projectDir = file("../compose-syntax")
