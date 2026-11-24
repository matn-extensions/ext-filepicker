module matn.ui.shell.filepicker.icons;

import std.string : toLower;
import matn.ui.grid.cell : Color;

string resolveFileIcon(string filename) pure
{
    string lower = filename.toLower();
    string bName = lower;
    foreach_reverse (idx, char c; lower)
    {
        if (c == '/' || c == '\\')
        {
            bName = lower[idx + 1 .. $];
            break;
        }
    }

    if (bName == "androidmanifest.xml") return "";
    if (bName == "gradlew" || bName == "gradlew.bat") return "";
    if (bName == "build.gradle" || bName == "settings.gradle") return "";
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".d") return "";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".di") return "";
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".c") return "";
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".h") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".cpp") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".hpp") return "";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".py") return "";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".json") return "";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".md") return "";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".js") return "";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".ts") return "";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".java") return "";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".kt") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".kts") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".xml") return "";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".axml") return "";
    if (lower.length >= 7 && lower[$ - 7 .. $] == ".gradle") return "";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".toml") return "";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".yaml") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".yml") return "";
    if (lower.length >= 11 && lower[$ - 11 .. $] == ".properties") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".pro") return "󰒥";
    if ((lower.length >= 5 && lower[$ - 5 .. $] == ".html") ||
        (lower.length >= 4 && lower[$ - 4 .. $] == ".htm") ||
        (lower.length >= 5 && lower[$ - 5 .. $] == ".htmx")) return "󰌝";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".qml") return "";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".css") return "󰌝";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".sh") return "";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".bash") return "";
    if (filename == "dub.json" || filename == "dub.sdl") return "";
    if (filename == "justfile" || filename == "Makefile") return "󰑮";
    if (filename == ".gitignore") return "";
    return "󰈔";
}

Color resolveFileIconColor(string filename) pure
{
    string lower = filename.toLower();
    string bName = lower;
    foreach_reverse (idx, char c; lower)
    {
        if (c == '/' || c == '\\')
        {
            bName = lower[idx + 1 .. $];
            break;
        }
    }

    if (bName == "androidmanifest.xml") return Color(164, 198, 57, 255); // Android Green #a4c639
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".d") return Color(180, 50, 50, 255);
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".c") return Color(80, 140, 220, 255);
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".cpp") return Color(80, 140, 220, 255);
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".py") return Color(240, 210, 80, 255);
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".json") return Color(240, 180, 50, 255);
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".md") return Color(100, 180, 240, 255);
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".js") return Color(240, 220, 80, 255);
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".ts") return Color(80, 160, 240, 255);
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".java") return Color(240, 120, 50, 255);
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".kt" || (lower.length >= 4 && lower[$ - 4 .. $] == ".kts")) return Color(160, 100, 240, 255);
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".xml" || (lower.length >= 5 && lower[$ - 5 .. $] == ".axml")) return Color(230, 100, 60, 255);
    if (lower.length >= 7 && lower[$ - 7 .. $] == ".gradle" || bName == "build.gradle" || bName == "settings.gradle") return Color(30, 160, 200, 255);
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".toml") return Color(180, 140, 90, 255);
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".yaml" || (lower.length >= 4 && lower[$ - 4 .. $] == ".yml")) return Color(203, 75, 22, 255); // YAML Red-Orange
    if (lower.length >= 11 && lower[$ - 11 .. $] == ".properties") return Color(160, 180, 190, 255);
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".pro") return Color(210, 150, 70, 255);
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".sh") return Color(120, 220, 100, 255);
    if ((lower.length >= 5 && lower[$ - 5 .. $] == ".html") ||
        (lower.length >= 4 && lower[$ - 4 .. $] == ".htm") ||
        (lower.length >= 5 && lower[$ - 5 .. $] == ".htmx")) return Color(228, 77, 38, 255); // HTML5 Brand Orange
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".qml") return Color(65, 205, 82, 255); // Qt Green
    return Color(160, 170, 200, 255);
}

string resolveFileType(string filename) pure
{
    string lower = filename.toLower();
    string bName = lower;
    foreach_reverse (idx, char c; lower)
    {
        if (c == '/' || c == '\\')
        {
            bName = lower[idx + 1 .. $];
            break;
        }
    }

    if (bName == "androidmanifest.xml") return "Android Manifest";
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".d") return "D Source";
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".c") return "C Source";
    if (lower.length >= 2 && lower[$ - 2 .. $] == ".h") return "C Header";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".cpp") return "C++ Source";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".py") return "Python Script";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".json") return "JSON Data";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".md") return "Markdown Doc";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".js") return "JavaScript";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".ts") return "TypeScript";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".java") return "Java Source";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".kt") return "Kotlin Source";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".kts") return "Kotlin Script";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".xml") return "XML Document";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".axml") return "Android XML";
    if (lower.length >= 7 && lower[$ - 7 .. $] == ".gradle") return "Gradle Script";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".toml") return "TOML Document";
    if (lower.length >= 5 && lower[$ - 5 .. $] == ".yaml") return "YAML Document";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".yml") return "YAML Document";
    if (lower.length >= 11 && lower[$ - 11 .. $] == ".properties") return "Properties";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".pro") return "ProGuard Rules";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".txt") return "Text Document";
    if (lower.length >= 3 && lower[$ - 3 .. $] == ".sh") return "Shell Script";
    if ((lower.length >= 5 && lower[$ - 5 .. $] == ".html") ||
        (lower.length >= 4 && lower[$ - 4 .. $] == ".htm") ||
        (lower.length >= 5 && lower[$ - 5 .. $] == ".htmx")) return "HTML Document";
    if (lower.length >= 4 && lower[$ - 4 .. $] == ".qml") return "QML Document";
    return "File";
}

unittest
{
    assert(resolveFileIcon("AndroidManifest.xml") == "");
    assert(resolveFileType("AndroidManifest.xml") == "Android Manifest");

    assert(resolveFileIcon("build.gradle") == "");
    assert(resolveFileType("build.gradle") == "Gradle Script");

    assert(resolveFileIcon("config.yaml") == "");
    assert(resolveFileType("config.yaml") == "YAML Document");
    assert(resolveFileIcon("docker-compose.yml") == "");
    assert(resolveFileType("docker-compose.yml") == "YAML Document");

    assert(resolveFileIcon("settings.gradle") == "");
    assert(resolveFileIcon("gradlew") == "");

    assert(resolveFileIcon("libs.versions.toml") == "");
    assert(resolveFileType("libs.versions.toml") == "TOML Document");

    assert(resolveFileIcon("gradle.properties") == "");
    assert(resolveFileType("gradle.properties") == "Properties");

    assert(resolveFileIcon("proguard-rules.pro") == "󰒥");
    assert(resolveFileType("proguard-rules.pro") == "ProGuard Rules");

    assert(resolveFileIcon("activity_main.xml") == "");
    assert(resolveFileType("activity_main.xml") == "XML Document");

    assert(resolveFileIcon("MainActivity.java") == "");
    assert(resolveFileType("MainActivity.java") == "Java Source");

    assert(resolveFileIcon("MainActivity.kt") == "");
    assert(resolveFileType("MainActivity.kt") == "Kotlin Source");
}
