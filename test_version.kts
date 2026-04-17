// Test script to simulate what our Gradle build does
import java.util.Properties

val localProperties = Properties()
val localPropertiesFile = File("android/local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        localProperties.load(stream)
    }
}

val flutterVersionCode: Int = localProperties.getProperty("flutter.versionCode")?.toInt() ?: 58
val flutterVersionName: String = localProperties.getProperty("flutter.versionName") ?: "2.0.0"

println("Version Code: $flutterVersionCode")
println("Version Name: $flutterVersionName")