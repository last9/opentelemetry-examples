val last9RumVersion = providers.environmentVariable("LAST9_RUM_ANDROID_VERSION").orElse("0.9.0")

configurations {
    create("last9Rum")
}

dependencies {
    add("last9Rum", "io.last9:rum-android:${last9RumVersion.get()}@aar")
}

tasks.register("resolveLast9Rum") {
    group = "verification"
    description = "Resolves io.last9:rum-android from the Last9 CDN Maven repository."

    doLast {
        val files = configurations.getByName("last9Rum").resolve()
        files.forEach { println(it.name) }
    }
}
