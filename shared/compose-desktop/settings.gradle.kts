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

project(":hello").projectDir = file("../../HelloWorld/apps/hello-world-compose")

project(":chat").projectDir = file("../../ChatHistory/apps/chat-history-compose")

project(":syntax").projectDir = file("../../ChatHistory/packages/compose-syntax")
