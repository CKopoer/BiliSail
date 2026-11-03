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

apply(from = "patches/media_kit/apply.gradle")
apply(from = "patches/media_kit/first-frame.gradle")

subprojects {
    project.evaluationDependsOn(":app")
}

apply(from = "patches/audio_service/apply.gradle")

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
