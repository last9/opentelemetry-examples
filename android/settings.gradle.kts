pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Prefer locally published SDK when testing unreleased rum-sdk changes:
        //   cd ~/Projects/browser/packages/android && ./gradlew :rum:publishToMavenLocal
        mavenLocal()
        google()
        mavenCentral()
        maven { url = uri("https://cdn.last9.io/rum-sdk/android/maven/") }
    }
}

rootProject.name = "rum-android-example"
include(":app")
