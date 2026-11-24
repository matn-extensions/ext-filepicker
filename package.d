module matn.ui.shell.filepicker;

import std.algorithm : max, min, clamp, sort, canFind, startsWith, endsWith;
import std.conv : to;
import std.file : exists, isDir, isFile, dirEntries, SpanMode, getSize, timeLastModified, getcwd;
import std.path : baseName, dirName, buildPath, buildNormalizedPath, absolutePath, expandTilde, relativePath;
import std.string : toLower, strip;
import std.utf : toUTF8;

import matn.platform.sdl;
import matn.platform.font;
import matn.ui.grid.cell;
import matn.ui.grid.grid;
import matn.ui.grid.renderer;
import matn.extension.base;
public import matn.ui.shell.filepicker.fuzzy;
public import matn.ui.shell.filepicker.icons;
public import matn.ui.shell.filepicker.render;

/// Mode for the file picker
enum FilePickerMode
{
    openFile,
    openFolder,
    saveFile,
    fuzzyFile
}

/// An entry in the directory or project file list
struct FilePickerEntry
{
    string name;
    string fullPath;
    string relativePath; // Relative path in workspace for fuzzy project search
    bool isDir;
    bool isParent;
    ulong size;
    long mtime;
    string icon;
    Color iconColor;
    string formattedSize;
    string fileType;
    int matchScore;
    int[] matchIndices;
}

/// Styling and rendering context for FilePicker
struct FilePickerContext
{
    int gridCols;
    int gridRows;
    Color bg;
    Color barBg;
    Color text;
    Color muted;
    Color accent;
    Color border;
    Color activeLine;
    bool isLight = false;
    bool showIcons = true;
    bool blink = true;
}

/// Full interactive visual file & folder picker dialog
class FilePickerExtension : Extension
{
    bool visible = false;
    FilePickerMode mode = FilePickerMode.openFile;

    string currentDir = "";
    string filterQuery = "";
    bool showHidden = false;

    string saveFileName = "";
    bool isEditingFileName = true;

    FilePickerEntry[] allEntries;
    FilePickerEntry[] filteredEntries;
    FilePickerEntry[] projectEntries;
    string cachedProjectRoot = "";
    bool isProjectScanned = false;

    int selectedIndex = 0;
    int scrollOffset = 0;
    int hoveredIndex = -1;

    // Callbacks for confirmed selections
    void delegate(string filePath) onFileSelected;
    void delegate(string folderPath) onFolderSelected;
    void delegate(string destinationPath) onFileSaved;
    void delegate() onClose;

    // Modal layout geometry for hit testing
    int modalX = 0;
    int modalY = 0;
    int modalW = 0;
    int modalH = 0;
    int listStartY = 0;
    int visibleRowCount = 0;

    // Hit-testing clickable regions
    struct ClickableRow
    {
        int index;
        int row;
        int leftCol;
        int rightCol;
    }
    package ClickableRow[] clickRows;

    struct ClickableButton
    {
        int id; // 1: close, 4: up, 5: hidden, 6: selectCurrent, 7: cancel, 8: open
        int row;
        int leftCol;
        int rightCol;
    }
    package ClickableButton[] clickButtons;

    // Double-click detection
    private ulong lastClickTime = 0;
    private int lastClickIndex = -1;

    this()
    {
        super(ExtensionManifest(
            "matn.filepicker",
            "File Picker",
            "1.0.0",
            "Matn Core",
            "Interactive visual file and directory browser with live filtering and project folder selection",
            true
        ));
    }

    override protected void onActivate()
    {
        if (_context)
        {
            _context.registerCommand(ExtensionCommand(
                _manifest.id ~ ".openFile",
                "Open File...",
                "File",
                "Ctrl+O",
                { openFilePicker(); }
            ));
            _context.registerCommand(ExtensionCommand(
                _manifest.id ~ ".fuzzyFind",
                "Quick Open / Fuzzy File Finder",
                "File",
                "Ctrl+P",
                { openFuzzyFinder(); }
            ));
            _context.registerCommand(ExtensionCommand(
                _manifest.id ~ ".openFolder",
                "Open Folder / Project...",
                "File",
                "Ctrl+Shift+O",
                { openFolderPicker(); }
            ));
            _context.registerCommand(ExtensionCommand(
                _manifest.id ~ ".close",
                "Close File Picker",
                "View",
                "Esc",
                { close(); }
            ));
        }
    }

    /// Open in "Open File" mode
    void openFilePicker(string startDir = "")
    {
        mode = FilePickerMode.openFile;
        isEditingFileName = false;
        initDir(startDir);
        visible = true;
    }

    /// Toggle visibility
    void toggle()
    {
        if (visible) close();
        else openFilePicker();
    }

    /// Open in "Open Folder" mode
    void openFolderPicker(string startDir = "")
    {
        mode = FilePickerMode.openFolder;
        isEditingFileName = false;
        initDir(startDir);
        visible = true;
    }

    /// Open in "Save File" mode with folder picker and file name editor
    void openSavePicker(string defaultFileName = "untitled.txt", string startDir = "")
    {
        mode = FilePickerMode.saveFile;
        saveFileName = (defaultFileName.length > 0) ? defaultFileName : "untitled.txt";
        isEditingFileName = true;
        initDir(startDir);
        visible = true;
    }

    /// Returns the project workspace root path if available and project is open
    string getProjectRoot()
    {
        if (_context && _context.hasProject())
        {
            try
            {
                string p = _context.projectRoot();
                if (p.length > 0 && exists(p) && isDir(p))
                    return buildNormalizedPath(absolutePath(p));
            }
            catch (Exception) {}
        }
        return "";
    }

    override void onProjectOpened(string rootPath)
    {
        cachedProjectRoot = rootPath;
        isProjectScanned = false;
        projectEntries = [];
        if (visible && mode == FilePickerMode.fuzzyFile)
            scanProjectEntries(true);
    }

    override void onProjectClosed()
    {
        cachedProjectRoot = "";
        isProjectScanned = false;
        projectEntries = [];
        if (mode == FilePickerMode.fuzzyFile)
        {
            allEntries = [];
            filteredEntries = [];
        }
    }

    /// Open in "Fuzzy File Finder" mode across project workspace
    void openFuzzyFinder(string startRoot = "")
    {
        mode = FilePickerMode.fuzzyFile;
        isEditingFileName = false;
        filterQuery = "";
        selectedIndex = 0;
        scrollOffset = 0;
        hoveredIndex = -1;

        if (startRoot.length > 0 && exists(startRoot) && isDir(startRoot))
        {
            currentDir = buildNormalizedPath(absolutePath(startRoot));
            cachedProjectRoot = currentDir;
        }
        else
        {
            currentDir = getProjectRoot();
            cachedProjectRoot = currentDir;
        }

        scanProjectEntries(false);
        visible = true;
    }

    /// Toggle between directory browsing and project-wide fuzzy finder
    void toggleFuzzyMode()
    {
        if (mode == FilePickerMode.fuzzyFile)
        {
            mode = FilePickerMode.openFile;
            filterQuery = "";
            refreshEntries();
        }
        else
        {
            openFuzzyFinder();
        }
    }

    /// Recursively scan project files for fast fuzzy indexing
    void scanProjectEntries(bool forceRescan = false)
    {
        string root = (cachedProjectRoot.length > 0 && exists(cachedProjectRoot) && isDir(cachedProjectRoot))
            ? cachedProjectRoot
            : getProjectRoot();
        cachedProjectRoot = root;

        if (!forceRescan && isProjectScanned && projectEntries.length > 0)
        {
            allEntries = projectEntries;
            updateFilter();
            return;
        }

        projectEntries = [];
        isProjectScanned = true;

        if (root.length == 0 || !exists(root) || !isDir(root))
        {
            allEntries = [];
            filteredEntries = [];
            return;
        }

        int maxFiles = 25000;
        string[] stack = [root];

        while (stack.length > 0 && projectEntries.length < maxFiles)
        {
            string dir = stack[$ - 1];
            stack = stack[0 .. $ - 1];

            try
            {
                foreach (entry; dirEntries(dir, SpanMode.shallow))
                {
                    string bName = baseName(entry.name);
                    bool d = entry.isDir;

                    if (d)
                    {
                        if (!showHidden && bName.length > 0 && bName[0] == '.')
                            continue;
                        if (bName == ".git" || bName == ".dub" || bName == "node_modules" ||
                            bName == ".cache" || bName == "build" || bName == "target" ||
                            bName == ".vscode" || bName == ".idea" || bName == "bin" || bName == "obj")
                            continue;

                        stack ~= entry.name;
                    }
                    else
                    {
                        if (!showHidden && bName.length > 0 && bName[0] == '.')
                            continue;

                        if (bName.endsWith(".o") || bName.endsWith(".a") || bName.endsWith(".so") ||
                            bName.endsWith(".dylib") || bName.endsWith(".dll") || bName.endsWith(".class"))
                            continue;

                        string full = buildNormalizedPath(absolutePath(entry.name));
                        string rel = relativePath(full, root);

                        FilePickerEntry item;
                        item.name = bName;
                        item.fullPath = full;
                        item.relativePath = rel;
                        item.isDir = false;
                        item.isParent = false;
                        try
                        {
                            item.size = getSize(entry.name);
                            item.formattedSize = formatBytes(item.size);
                        }
                        catch (Exception)
                        {
                            item.size = 0;
                            item.formattedSize = "-";
                        }
                        item.icon = resolveFileIcon(bName);
                        item.iconColor = resolveFileIconColor(bName);
                        item.fileType = resolveFileType(bName);
                        projectEntries ~= item;

                        if (projectEntries.length >= maxFiles)
                            break;
                    }
                }
            }
            catch (Exception) {}
        }

        projectEntries.sort!((a, b) => a.relativePath.toLower() < b.relativePath.toLower());
        allEntries = projectEntries;
        updateFilter();
    }

    /// Close modal
    void close()
    {
        visible = false;
        filterQuery = "";
        saveFileName = "";
        isEditingFileName = true;
        allEntries = [];
        filteredEntries = [];
        selectedIndex = 0;
        scrollOffset = 0;
        hoveredIndex = -1;
        if (onClose) onClose();
    }

    private void initDir(string startDir)
    {
        filterQuery = "";
        scrollOffset = 0;
        selectedIndex = 0;
        hoveredIndex = -1;

        if (startDir.length > 0 && exists(startDir) && isDir(startDir))
        {
            currentDir = buildNormalizedPath(absolutePath(startDir));
        }
        else if (currentDir.length == 0 || !exists(currentDir) || !isDir(currentDir))
        {
            try
            {
                currentDir = buildNormalizedPath(absolutePath(getcwd()));
            }
            catch (Exception)
            {
                currentDir = expandTilde("~");
            }
        }

        refreshEntries();
    }

    /// Navigate into directory
    void cd(string targetDir)
    {
        if (targetDir.length == 0 || !exists(targetDir) || !isDir(targetDir))
            return;

        currentDir = buildNormalizedPath(absolutePath(targetDir));
        filterQuery = "";
        selectedIndex = 0;
        scrollOffset = 0;
        hoveredIndex = -1;
        refreshEntries();
    }

    /// Navigate to parent directory
    void goUp()
    {
        string p = dirName(currentDir);
        if (p.length > 0 && p != currentDir && exists(p) && isDir(p))
        {
            cd(p);
        }
    }

    /// Reload entries in current directory or project
    void refreshEntries()
    {
        if (mode == FilePickerMode.fuzzyFile)
        {
            scanProjectEntries(true);
            return;
        }

        allEntries = [];
        filteredEntries = [];

        if (currentDir.length == 0 || !exists(currentDir) || !isDir(currentDir))
            return;

        // Add parent directory entry if not at filesystem root
        string p = dirName(currentDir);
        if (p.length > 0 && p != currentDir)
        {
            FilePickerEntry parent;
            parent.name = "..";
            parent.fullPath = p;
            parent.isDir = true;
            parent.isParent = true;
            parent.icon = "";
            parent.iconColor = Color(140, 160, 200, 255);
            parent.formattedSize = "";
            parent.fileType = "Parent Directory";
            allEntries ~= parent;
        }

        try
        {
            FilePickerEntry[] dirs;
            FilePickerEntry[] files;

            foreach (entry; dirEntries(currentDir, SpanMode.shallow))
            {
                string bName = baseName(entry.name);

                // Hidden files filter
                if (!showHidden && bName.length > 1 && bName[0] == '.')
                    continue;

                bool d = entry.isDir;
                FilePickerEntry item;
                item.name = bName;
                item.fullPath = buildNormalizedPath(absolutePath(entry.name));
                item.isDir = d;
                item.isParent = false;

                if (d)
                {
                    item.icon = "󰉋";
                    item.iconColor = Color(230, 185, 80, 255); // Amber folder
                    item.formattedSize = "";
                    item.fileType = "Folder";
                    dirs ~= item;
                }
                else
                {
                    try
                    {
                        item.size = getSize(entry.name);
                        item.formattedSize = formatBytes(item.size);
                    }
                    catch (Exception)
                    {
                        item.size = 0;
                        item.formattedSize = "-";
                    }

                    item.icon = resolveFileIcon(bName);
                    item.iconColor = resolveFileIconColor(bName);
                    item.fileType = resolveFileType(bName);
                    files ~= item;
                }
            }

            // Directories first, then files, sorted case-insensitively
            dirs.sort!((a, b) => a.name.toLower() < b.name.toLower());
            files.sort!((a, b) => a.name.toLower() < b.name.toLower());

            allEntries ~= dirs;
            allEntries ~= files;
        }
        catch (Exception)
        {
        }

        updateFilter();
    }

    /// Filter entries based on query string using fuzzy search
    void updateFilter()
    {
        filteredEntries = [];
        string q = filterQuery.strip();

        if (mode == FilePickerMode.fuzzyFile)
        {
            if (q.length == 0)
            {
                filteredEntries = allEntries.dup;
            }
            else
            {
                foreach (ref entry; allEntries)
                {
                    string matchTarget = entry.relativePath.length ? entry.relativePath : entry.name;
                    auto res = fuzzyMatch(matchTarget, q);
                    if (res.matched)
                    {
                        entry.matchScore = res.score;
                        entry.matchIndices = res.indices;
                        filteredEntries ~= entry;
                    }
                }

                // Sort by matchScore descending, then by relative path
                filteredEntries.sort!((a, b) => (a.matchScore != b.matchScore)
                    ? (a.matchScore > b.matchScore)
                    : (a.relativePath.toLower() < b.relativePath.toLower()));
            }
        }
        else
        {
            if (q.length == 0)
            {
                filteredEntries = allEntries.dup;
            }
            else
            {
                foreach (ref entry; allEntries)
                {
                    if (entry.isParent)
                    {
                        if (q == ".." || q == ".")
                            filteredEntries ~= entry;
                        continue;
                    }

                    auto res = fuzzyMatch(entry.name, q);
                    if (res.matched)
                    {
                        entry.matchScore = res.score;
                        entry.matchIndices = res.indices;
                        filteredEntries ~= entry;
                    }
                }

                // Sort by: dirs first if same score, highest matchScore, then name
                filteredEntries.sort!((a, b) => (a.isDir != b.isDir)
                    ? a.isDir
                    : ((a.matchScore != b.matchScore)
                        ? (a.matchScore > b.matchScore)
                        : (a.name.toLower() < b.name.toLower())));
            }
        }

        selectedIndex = clamp(selectedIndex, 0, max(0, cast(int) filteredEntries.length - 1));
        ensureValidScroll();
    }

    private void ensureValidScroll()
    {
        if (visibleRowCount <= 0) visibleRowCount = 14;
        if (selectedIndex < scrollOffset)
            scrollOffset = selectedIndex;
        else if (selectedIndex >= scrollOffset + visibleRowCount)
            scrollOffset = max(0, selectedIndex - visibleRowCount + 1);
    }

    /// Confirm selection and invoke callback
    void confirmSelection()
    {
        // Check if filterQuery itself is an explicit directory or file path
        string q = filterQuery.strip();
        if (q.startsWith("~"))
            q = expandTilde(q);

        if (q.length > 0 && exists(q))
        {
            if (isDir(q))
            {
                cd(q);
                return;
            }
            else if (isFile(q) && mode == FilePickerMode.openFile)
            {
                string target = buildNormalizedPath(absolutePath(q));
                close();
                if (onFileSelected)
                    onFileSelected(target);
                return;
            }
        }

        if (mode == FilePickerMode.fuzzyFile)
        {
            if (cachedProjectRoot.length == 0)
            {
                openFolderPicker();
                return;
            }
            if (selectedIndex >= 0 && selectedIndex < filteredEntries.length)
            {
                string target = filteredEntries[selectedIndex].fullPath;
                close();
                if (onFileSelected)
                    onFileSelected(target);
                return;
            }
            return;
        }

        if (selectedIndex >= 0 && selectedIndex < filteredEntries.length)
        {
            auto entry = filteredEntries[selectedIndex];
            if (entry.isParent)
            {
                goUp();
                return;
            }
            if (entry.isDir)
            {
                // Enter directory in both folder and file mode
                cd(entry.fullPath);
                return;
            }

            // It's a file
            if (mode == FilePickerMode.openFile)
            {
                string target = entry.fullPath;
                close();
                if (onFileSelected)
                    onFileSelected(target);
                return;
            }
        }

        // If in save mode, confirm the save file path
        if (mode == FilePickerMode.saveFile)
        {
            if (!isEditingFileName && selectedIndex >= 0 && selectedIndex < filteredEntries.length)
            {
                auto entry = filteredEntries[selectedIndex];
                if (entry.isParent)
                {
                    goUp();
                    return;
                }
                if (entry.isDir)
                {
                    cd(entry.fullPath);
                    return;
                }
                saveFileName = entry.name;
                isEditingFileName = true;
                return;
            }
            confirmSave();
            return;
        }

        // If in folder mode and not entering a subfolder, select currentDir
        if (mode == FilePickerMode.openFolder)
        {
            pickCurrentFolder();
        }
    }

    /// Explicitly commit the current folder as selected project
    void pickCurrentFolder()
    {
        if (currentDir.length > 0 && exists(currentDir) && isDir(currentDir))
        {
            string target = currentDir;
            close();
            if (onFolderSelected)
                onFolderSelected(target);
        }
    }

    /// Explicitly commit saving the file in current folder
    void confirmSave()
    {
        string name = saveFileName.strip();
        if (name.length == 0)
            name = "untitled.txt";
        string target = buildNormalizedPath(absolutePath(buildPath(currentDir, name)));
        close();
        if (onFileSaved)
            onFileSaved(target);
    }

    /// Move selection by delta items
    void moveSelection(int delta)
    {
        if (filteredEntries.length == 0) return;
        selectedIndex = clamp(selectedIndex + delta, 0, cast(int) filteredEntries.length - 1);
        ensureValidScroll();
    }

    bool handleTextInput(string text)
    {
        if (!visible || text.length == 0) return false;
        if (mode == FilePickerMode.saveFile && isEditingFileName)
        {
            saveFileName ~= text;
            return true;
        }
        filterQuery ~= text;
        updateFilter();
        return true;
    }

    bool handleMouseMove(int col, int row)
    {
        if (!visible) return false;

        int oldHover = hoveredIndex;
        hoveredIndex = -1;

        foreach (ref cr; clickRows)
        {
            if (row == cr.row && col >= cr.leftCol && col < cr.rightCol)
            {
                hoveredIndex = cr.index;
                break;
            }
        }

        return (oldHover != hoveredIndex);
    }

    bool handleMouseDown(int col, int row, FilePickerContext ctx)
    {
        if (!visible) return false;

        // Click outside closes modal
        if (col < modalX || col >= modalX + modalW || row < modalY || row >= modalY + modalH)
        {
            close();
            return true;
        }

        // Click on File Name row vs Search/Filter row in saveFile mode
        int searchY = modalY + 1;
        int nameY = (mode == FilePickerMode.saveFile) ? (modalY + modalH - 2) : -1;
        if (row == nameY && col >= modalX && col < modalX + modalW)
        {
            isEditingFileName = true;
            return true;
        }
        if (row == searchY && col >= modalX && col < modalX + modalW)
        {
            isEditingFileName = false;
        }

        // Check button clicks
        foreach (ref cb; clickButtons)
        {
            if (row == cb.row && col >= cb.leftCol && col < cb.rightCol)
            {
                switch (cb.id)
                {
                case 1: // Close
                    close();
                    return true;
                case 4: // Up
                    goUp();
                    return true;
                case 5: // Toggle Hidden
                    showHidden = !showHidden;
                    refreshEntries();
                    return true;
                case 6: // Select Current Folder
                    pickCurrentFolder();
                    return true;
                case 7: // Cancel
                    close();
                    return true;
                case 8: // Open
                    confirmSelection();
                    return true;
                case 9: // Save
                    confirmSave();
                    return true;
                case 10: // Toggle mode between fuzzy project and browse
                    toggleFuzzyMode();
                    return true;
                case 11: // Rescan project files in fuzzy mode
                    if (mode == FilePickerMode.fuzzyFile)
                        scanProjectEntries(true);
                    return true;
                default:
                    break;
                }
            }
        }

        // Check row clicks
        foreach (ref cr; clickRows)
        {
            if (row == cr.row && col >= cr.leftCol && col < cr.rightCol)
            {
                ulong now = SDL_GetTicks();
                bool isDoubleClick = (lastClickIndex == cr.index && (now - lastClickTime) < 450);
                lastClickTime = now;
                lastClickIndex = cr.index;

                selectedIndex = cr.index;

                if (mode == FilePickerMode.saveFile)
                {
                    if (cr.index >= 0 && cr.index < filteredEntries.length)
                    {
                        auto ent = filteredEntries[cr.index];
                        if (ent.isDir || ent.isParent)
                        {
                            isEditingFileName = false;
                            if (isDoubleClick)
                            {
                                if (ent.isParent) goUp();
                                else cd(ent.fullPath);
                                return true;
                            }
                        }
                        else
                        {
                            saveFileName = ent.name;
                            isEditingFileName = true;
                            if (isDoubleClick)
                            {
                                confirmSave();
                                return true;
                            }
                        }
                    }
                    return true;
                }

                if (isDoubleClick)
                {
                    confirmSelection();
                }
                return true;
            }
        }

        return true;
    }

    bool handleMouseWheel(int wheelY)
    {
        if (!visible) return false;
        if (wheelY > 0)
            moveSelection(-3);
        else if (wheelY < 0)
            moveSelection(3);
        return true;
    }

    bool handleKeyDown(uint key, uint mod, FilePickerContext ctx)
    {
        if (!visible) return false;

        bool isCtrl = (mod & SDL_KMOD_CTRL) != 0;
        bool isAlt = (mod & SDL_KMOD_ALT) != 0;

        if (key == SDLK_ESCAPE)
        {
            close();
            return true;
        }
        else if (isCtrl && (key == 'p' || key == 'P'))
        {
            toggleFuzzyMode();
            return true;
        }
        else if (isCtrl && (key == 'o' || key == 'O'))
        {
            if (mode == FilePickerMode.fuzzyFile)
            {
                openFilePicker(currentDir);
                return true;
            }
        }
        else if (isCtrl && (key == 'r' || key == 'R'))
        {
            if (mode == FilePickerMode.fuzzyFile)
            {
                scanProjectEntries(true);
                return true;
            }
        }
        else if (key == SDLK_TAB)
        {
            if (mode == FilePickerMode.saveFile)
            {
                isEditingFileName = !isEditingFileName;
                return true;
            }
        }
        else if (isCtrl && (key == 'h' || key == 'H'))
        {
            showHidden = !showHidden;
            refreshEntries();
            return true;
        }
        else if (isCtrl && (key == 'u' || key == 'U'))
        {
            if (mode == FilePickerMode.saveFile && isEditingFileName)
            {
                saveFileName = "";
                return true;
            }
            filterQuery = "";
            updateFilter();
            return true;
        }
        else if (isCtrl && (key == SDLK_RETURN || key == 0x40000058))
        {
            if (mode == FilePickerMode.openFolder)
            {
                pickCurrentFolder();
                return true;
            }
            else if (mode == FilePickerMode.saveFile)
            {
                confirmSave();
                return true;
            }
        }
        else if (key == SDLK_RETURN || key == 0x40000058)
        {
            confirmSelection();
            return true;
        }
        else if (key == SDLK_UP)
        {
            moveSelection(-1);
            return true;
        }
        else if (key == SDLK_DOWN)
        {
            moveSelection(1);
            return true;
        }
        else if (key == 0x4000004b) // PageUp
        {
            moveSelection(-6);
            return true;
        }
        else if (key == 0x4000004e) // PageDown
        {
            moveSelection(6);
            return true;
        }
        else if (key == 0x4000004a) // Home
        {
            selectedIndex = 0;
            ensureValidScroll();
            return true;
        }
        else if (key == 0x4000004d) // End
        {
            selectedIndex = max(0, cast(int) filteredEntries.length - 1);
            ensureValidScroll();
            return true;
        }
        else if ((isAlt && (key == SDLK_LEFT || key == SDLK_UP)) || (isCtrl && key == SDLK_UP))
        {
            goUp();
            return true;
        }
        else if (key == 0x8) // SDLK_BACKSPACE
        {
            if (mode == FilePickerMode.saveFile && isEditingFileName)
            {
                if (saveFileName.length > 0)
                    saveFileName = saveFileName[0 .. $ - 1];
                return true;
            }
            if (filterQuery.length > 0)
            {
                filterQuery = filterQuery[0 .. $ - 1];
                updateFilter();
            }
            return true;
        }

        return false;
    }

    package string formatBreadcrumbs(int maxW)
    {
        string home = expandTilde("~");
        string p = currentDir;
        if (p.startsWith(home))
            p = "~" ~ p[home.length .. $];

        if (p.length <= maxW)
            return p;

        if (maxW > 5)
            return "…" ~ p[$ - (maxW - 1) .. $];
        return p[0 .. min($, maxW)];
    }

    void render(GlyphGrid grid, FilePickerContext ctx)
    {
        renderFilePicker(this, grid, ctx);
    }

    void renderReal(SDL_Renderer* renderer, FontEngine font, FilePickerContext ctx, float padX, float padY)
    {
        renderFilePickerReal(this, renderer, font, ctx, padX, padY);
    }


    private static string formatBytes(ulong bytes) pure
    {
        if (bytes < 1024)
            return to!string(bytes) ~ " B";
        else if (bytes < 1024 * 1024)
            return to!string(bytes / 1024) ~ " KB";
        else
            return to!string(bytes / (1024 * 1024)) ~ " MB";
    }

    public static alias resolveFileIcon = matn.ui.shell.filepicker.icons.resolveFileIcon;
    public static alias resolveFileIconColor = matn.ui.shell.filepicker.icons.resolveFileIconColor;
    public static alias resolveFileType = matn.ui.shell.filepicker.icons.resolveFileType;
}

unittest
{
    import std.file : write, mkdir, rmdirRecurse;

    string tmpDir = buildNormalizedPath(absolutePath("/tmp/matn_filepicker_unittest"));
    if (exists(tmpDir)) rmdirRecurse(tmpDir);
    mkdir(tmpDir);
    scope (exit) { if (exists(tmpDir)) rmdirRecurse(tmpDir); }

    string subDir = buildPath(tmpDir, "subfolder");
    mkdir(subDir);
    write(buildPath(tmpDir, "hello.d"), "void main() {}");
    write(buildPath(tmpDir, "readme.md"), "# Readme");
    write(buildPath(tmpDir, ".hidden.txt"), "hidden content");

    auto picker = new FilePickerExtension();
    assert(!picker.visible);

    // Open file picker in test directory
    picker.openFilePicker(tmpDir);
    assert(picker.visible);
    assert(picker.mode == FilePickerMode.openFile);
    assert(picker.currentDir == tmpDir);

    // Check discovered entries
    assert(picker.allEntries.length >= 3); // .., subfolder, hello.d, readme.md (.hidden.txt skipped by default)

    // Verify hidden files toggle
    picker.showHidden = true;
    picker.refreshEntries();
    bool foundHidden = false;
    foreach (ref e; picker.allEntries)
    {
        if (e.name == ".hidden.txt") foundHidden = true;
    }
    assert(foundHidden, "Hidden file should be discovered when showHidden is true");

    // Verify filter
    picker.filterQuery = "hello";
    picker.updateFilter();
    assert(picker.filteredEntries.length >= 1);
    assert(picker.filteredEntries[$ - 1].name == "hello.d");

    // Test selection callback in openFile mode
    string selectedFile = "";
    picker.onFileSelected = (path) { selectedFile = path; };
    picker.selectedIndex = cast(int) picker.filteredEntries.length - 1;
    picker.confirmSelection();
    assert(selectedFile == buildPath(tmpDir, "hello.d"));
    assert(!picker.visible);

    // Test openFolder mode
    string selectedFolder = "";
    picker.openFolderPicker(tmpDir);
    picker.onFolderSelected = (path) { selectedFolder = path; };

    // Verify typing letters like 'h', 'j', 'k', 'l' does NOT trigger navigation or change dir
    FilePickerContext testCtx;
    bool handledH = picker.handleKeyDown('h', 0, testCtx);
    assert(!handledH, "Letter 'h' should not be intercepted by handleKeyDown");
    assert(picker.currentDir == tmpDir, "Typing 'h' should never navigate away to parent or ~");

    // Verify handleTextInput appends text without navigating
    picker.handleTextInput("h");
    picker.handleTextInput("ello");
    assert(picker.filterQuery == "hello");
    assert(picker.currentDir == tmpDir);

    // Verify backspace deletes filter character and does not go up when empty
    picker.handleKeyDown(0x8, 0, testCtx); // deletes 'o'
    assert(picker.filterQuery == "hell");
    picker.filterQuery = "";
    picker.handleKeyDown(0x8, 0, testCtx); // backspace on empty
    assert(picker.currentDir == tmpDir, "Backspace on empty filter should not go up to parent or ~");

    picker.pickCurrentFolder();
    assert(selectedFolder == tmpDir);
    assert(!picker.visible);

    // Test saveFile mode
    string savedTarget = "";
    picker.openSavePicker("new_test_file.d", tmpDir);
    assert(picker.visible);
    assert(picker.mode == FilePickerMode.saveFile);
    assert(picker.saveFileName == "new_test_file.d");
    assert(picker.isEditingFileName);
    picker.onFileSaved = (path) { savedTarget = path; };

    // Test typing in file name editor
    picker.handleTextInput("_v2");
    assert(picker.saveFileName == "new_test_file.d_v2");

    // Test backspace in file name editor
    picker.handleKeyDown(0x8, 0, testCtx); // removes '2'
    picker.handleKeyDown(0x8, 0, testCtx); // removes 'v'
    picker.handleKeyDown(0x8, 0, testCtx); // removes '_'
    assert(picker.saveFileName == "new_test_file.d");

    // Confirm save
    picker.confirmSave();
    assert(savedTarget == buildPath(tmpDir, "new_test_file.d"));
    assert(!picker.visible);

    // Test fuzzyFile mode
    string fuzzySelected = "";
    picker.openFuzzyFinder(tmpDir);
    assert(picker.visible);
    assert(picker.mode == FilePickerMode.fuzzyFile);
    assert(picker.allEntries.length >= 2); // hello.d, readme.md
    picker.onFileSelected = (path) { fuzzySelected = path; };

    // Test fuzzy query
    picker.filterQuery = "hl";
    picker.updateFilter();
    assert(picker.filteredEntries.length >= 1);
    assert(picker.filteredEntries[0].name == "hello.d");
    assert(picker.filteredEntries[0].matchIndices.length == 2);

    // Confirm selection in fuzzy mode
    picker.confirmSelection();
    assert(fuzzySelected == buildPath(tmpDir, "hello.d"));
    assert(!picker.visible);

    // Test toggle between modes
    picker.openFilePicker(tmpDir);
    assert(picker.mode == FilePickerMode.openFile);
    picker.toggleFuzzyMode();
    assert(picker.mode == FilePickerMode.fuzzyFile);
    picker.toggleFuzzyMode();
    assert(picker.mode == FilePickerMode.openFile);
    picker.close();
}
