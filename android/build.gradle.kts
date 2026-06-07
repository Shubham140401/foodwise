allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force all Android library subprojects to compileSdk 36 so they satisfy
// flutter_plugin_android_lifecycle's minCompileSdk requirement.
gradle.afterProject {
    val ext = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
    if (ext != null && ext.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 36 < 36) {
        ext.compileSdkVersion(36)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
