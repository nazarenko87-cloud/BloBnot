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

// Some plugins (e.g. desktop_drop) hardcode compileSdk 33, which AGP rejects
// once a transitive dependency (annotation-experimental) requires >= 34. Bump
// every Android subproject to 36 in afterEvaluate so it runs AFTER the plugin's
// own script body sets 33. This must be registered before the
// evaluationDependsOn(":app") block below — otherwise :app is already
// evaluated when this runs and afterEvaluate() throws.
subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
