module matn.ui.shell.filepicker.render;

import std.algorithm : min, max, canFind;
import std.conv : to;
import std.path : baseName;

import matn.platform.sdl;
import matn.platform.font : FontEngine;
import matn.ui.grid.cell : Color, CellStyle, CellAttr;
import matn.ui.grid.grid : GlyphGrid;
import matn.ui.grid.renderer;
import matn.ui.shell.filepicker : FilePickerExtension, FilePickerContext, FilePickerMode;

/// Returns visual column width of a UTF-8 string (counting code points)
private int btnW(string s) pure nothrow @nogc
{
    int count = 0;
    foreach (ubyte b; cast(const(ubyte)[]) s)
    {
        if ((b & 0xC0) != 0x80)
            count++;
    }
    return count;
}

void renderFilePicker(FilePickerExtension picker, GlyphGrid grid, FilePickerContext ctx)
{
    with (picker)
    {
        if (!visible) return;

        clickRows = [];
        clickButtons = [];

        // Dimensions: clean spacious dialog
        modalW = min(84, max(56, ctx.gridCols - 4));
        modalH = min(26, max(18, ctx.gridRows - 2));

        modalX = max(0, (ctx.gridCols - modalW) / 2);
        modalY = max(0, (ctx.gridRows - modalH) / 2);

        bool isLight = ctx.isLight || ctx.bg.isLight;
        Color modalBg = ctx.barBg;
        Color headerBg = isLight ? ctx.barBg.darken(6) : ctx.barBg.lighten(6);
        Color searchBg = ctx.bg;
        Color selRowBg = ctx.activeLine;
        Color hoverRowBg = ctx.activeLine.blend(ctx.barBg, 0.45f);
        Color btnBg = ctx.activeLine;
        Color accentBtnBg = ctx.accent;

        // 1. Fill entire modal background
        grid.fillRect(modalX, modalY, modalW, modalH, ' ', CellStyle(ctx.text, modalBg));

        // 2. Header Bar (Row 0 - clean sublabel title like ACTIONS)
        grid.fillRect(modalX, modalY, modalW, 1, ' ', CellStyle(ctx.text, modalBg));

        string title = (mode == FilePickerMode.fuzzyFile)
            ? "FUZZY FILE FINDER"
            : ((mode == FilePickerMode.openFolder)
                ? "OPEN FOLDER"
                : ((mode == FilePickerMode.saveFile) ? "SAVE FILE" : "OPEN FILE"));
        grid.putString(modalX + 2, modalY, to!dstring(title), CellStyle(ctx.muted, modalBg, CellAttr.bold));

        // Current Directory or Project Root Path Breadcrumb
        int titleW = cast(int) title.length + 3;
        int closeCol = modalX + modalW - 3;
        int maxPathW = max(0, (closeCol - 2) - (modalX + titleW));
        if (maxPathW > 6)
        {
            string pathStr;
            if (mode == FilePickerMode.fuzzyFile)
            {
                if (cachedProjectRoot.length > 0)
                    pathStr = "Workspace: " ~ baseName(cachedProjectRoot);
                else
                    pathStr = "Workspace: (No project open)";
            }
            else
            {
                pathStr = formatBreadcrumbs(maxPathW);
            }
            grid.putString(modalX + titleW, modalY, to!dstring(pathStr), CellStyle(ctx.muted, modalBg));
        }

        // Close button [x] at top right without gaps
        grid.putString(closeCol, modalY, "[x]"d, CellStyle(ctx.muted, modalBg));
        clickButtons ~= ClickableButton(1, modalY, closeCol, modalX + modalW);

        // 3. Search / Filter Bar (Row 1)
        int searchY = modalY + 1;
        grid.fillRect(modalX, searchY, modalW, 1, ' ', CellStyle(ctx.text, searchBg));

        grid.putString(modalX + 2, searchY, " ", CellStyle(ctx.muted, searchBg));

        // Right side quick buttons (flush adjacent, zero gap)
        int curBtnRight = modalX + modalW - 1;

        // Hidden toggle button: [ 󰄬 Hidden ]
        string hidText = showHidden ? " 󰄬 Hidden " : " 󰄱 Hidden ";
        int hidW = btnW(hidText);
        int hidCol = curBtnRight - hidW;
        grid.putString(hidCol, searchY, hidText, CellStyle(showHidden ? ctx.accent : ctx.muted, btnBg));
        clickButtons ~= ClickableButton(5, searchY, hidCol, hidCol + hidW);
        curBtnRight = hidCol;

        // Rescan button (fuzzyFile mode only)
        if (mode == FilePickerMode.fuzzyFile)
        {
            string rescanText = " 󰑐 Rescan ";
            int rescanW = btnW(rescanText);
            int rescanCol = curBtnRight - rescanW;
            grid.putString(rescanCol, searchY, rescanText, CellStyle(ctx.muted, btnBg));
            clickButtons ~= ClickableButton(11, searchY, rescanCol, rescanCol + rescanW);
            curBtnRight = rescanCol;
        }

        // Mode switch button: [ 󰉋 Browse ] / [ 󰈞 Fuzzy ]
        if (mode == FilePickerMode.openFile || mode == FilePickerMode.fuzzyFile)
        {
            string modeToggleText = (mode == FilePickerMode.fuzzyFile) ? " 󰉋 Browse " : " 󰈞 Fuzzy ";
            int toggleW = btnW(modeToggleText);
            int toggleCol = curBtnRight - toggleW;
            grid.putString(toggleCol, searchY, modeToggleText, CellStyle(ctx.accent, btnBg));
            clickButtons ~= ClickableButton(10, searchY, toggleCol, toggleCol + toggleW);
            curBtnRight = toggleCol;
        }

        // Search input field
        int inCol = modalX + 5;
        int maxInW = max(4, curBtnRight - inCol - 1);
        if (filterQuery.length > 0)
        {
            grid.putString(inCol, searchY, filterQuery, CellStyle(ctx.text, searchBg, CellAttr.bold), maxInW);
            if (!isEditingFileName)
            {
                int curPos = min(maxInW - 1, cast(int) filterQuery.length);
                int cursorCol = inCol + curPos;
                if (ctx.blink && cursorCol >= 0 && cursorCol < grid.cols && searchY >= 0 && searchY < grid.rows)
                {
                    auto cell = &grid.cells[searchY * grid.cols + cursorCol];
                    cell.style.attrs |= CellAttr.negative;
                }
            }
        }
        else
        {
            string placeholder = (mode == FilePickerMode.fuzzyFile)
                ? "Fuzzy search files by name or path (e.g. app/ren, fpic)..."
                : ((mode == FilePickerMode.openFolder)
                    ? "Filter folders..."
                    : (mode == FilePickerMode.saveFile ? "Filter folders/files (Tab to switch)..." : "Filter files (fuzzy)..."));
            grid.putString(inCol, searchY, placeholder, CellStyle(ctx.muted, searchBg, CellAttr.italic), maxInW);
            if (!isEditingFileName)
            {
                int cursorCol = inCol;
                if (ctx.blink && cursorCol >= 0 && cursorCol < grid.cols && searchY >= 0 && searchY < grid.rows)
                {
                    auto cell = &grid.cells[searchY * grid.cols + cursorCol];
                    cell.style.attrs |= CellAttr.negative;
                }
            }
        }

        // 4. File / Folder Entries List
        listStartY = modalY + 2;
        visibleRowCount = (mode == FilePickerMode.saveFile)
            ? max(1, modalH - 4)
            : max(1, modalH - 3);

        if (mode == FilePickerMode.fuzzyFile && cachedProjectRoot.length == 0)
        {
            int midY = listStartY + max(1, visibleRowCount / 3);
            string msg = "No project folder is currently open.";
            int msgX = max(modalX + 2, modalX + (modalW - cast(int) msg.length) / 2);
            grid.putString(msgX, midY, to!dstring(msg), CellStyle(ctx.muted, modalBg));

            string btnText = "[ 󰉋 Open Folder ]";
            int bW = btnW(btnText);
            int btnX = max(modalX + 2, modalX + (modalW - bW) / 2);
            int btnY = midY + 2;
            grid.putString(btnX, btnY, to!dstring(btnText), CellStyle(Color.black, ctx.accent, CellAttr.bold));
            clickButtons ~= ClickableButton(8, btnY, btnX, btnX + bW);
            return;
        }

        foreach (i; 0 .. visibleRowCount)
        {
            int r = listStartY + i;
            int itemIdx = scrollOffset + i;

            if (itemIdx < filteredEntries.length)
            {
                auto entry = filteredEntries[itemIdx];
                bool isSelected = (itemIdx == selectedIndex);
                bool isHovered = (itemIdx == hoveredIndex);

                Color rowBg = isSelected ? selRowBg : (isHovered ? hoverRowBg : modalBg);
                Color nameFg = isSelected
                    ? ctx.accent
                    : (entry.isDir
                        ? ctx.accent
                        : (entry.name.length > 0 && entry.name[0] == '.' ? ctx.muted : ctx.text));
                ubyte nameAttr = (isSelected || entry.isDir) ? CellAttr.bold : CellAttr.none;

                grid.fillRect(modalX + 1, r, modalW - 2, 1, ' ', CellStyle(nameFg, rowBg));

                // File or Folder Icon
                int iconCol = modalX + 2;
                int nameCol = iconCol;
                if (ctx.showIcons)
                {
                    grid.putString(iconCol, r, entry.icon ~ " ", CellStyle(isSelected ? ctx.accent : entry.iconColor, rowBg));
                    nameCol = iconCol + 2;
                }

                // Right side metadata (folder badge or size)
                string infoStr;
                if (entry.isParent)
                    infoStr = "Parent Directory";
                else if (entry.isDir)
                    infoStr = "Folder";
                else
                    infoStr = entry.formattedSize;

                int infoW = cast(int) infoStr.length;
                int infoCol = modalX + modalW - 3 - infoW;

                // Entry Name (with fuzzy match highlight)
                if (mode == FilePickerMode.fuzzyFile)
                {
                    // In fuzzyFile mode, display filename + directory path with highlighted matched chars
                    string rel = entry.relativePath.length ? entry.relativePath : entry.name;
                    int lastSlash = -1;
                    foreach_reverse (k, ch; rel)
                    {
                        if (ch == '/' || ch == '\\')
                        {
                            lastSlash = cast(int) k;
                            break;
                        }
                    }
                    string dirPart = (lastSlash >= 0) ? rel[0 .. lastSlash + 1] : "";
                    string filePart = (lastSlash >= 0) ? rel[lastSlash + 1 .. $] : rel;

                    // 1. Render filePart
                    int curX = nameCol;
                    foreach (charIdx, dchar ch; to!dstring(filePart))
                    {
                        if (curX >= infoCol - 2) break;
                        int origIdx = (lastSlash >= 0) ? (lastSlash + 1 + cast(int) charIdx) : cast(int) charIdx;
                        bool isMatched = entry.matchIndices.canFind(origIdx);
                        Color chFg = isMatched ? ctx.accent : (isSelected ? ctx.accent : ctx.text);
                        ubyte chAttr = isMatched ? (CellAttr.bold | CellAttr.underline) : (isSelected ? CellAttr.bold : CellAttr.none);
                        grid.putCell(curX, r, ch, CellStyle(chFg, rowBg, chAttr));
                        curX++;
                    }

                    // 2. Render dirPart
                    if (dirPart.length > 0 && curX + 2 < infoCol)
                    {
                        grid.putCell(curX, r, ' ', CellStyle(ctx.muted, rowBg));
                        curX++;
                        foreach (charIdx, dchar ch; to!dstring(dirPart))
                        {
                            if (curX >= infoCol - 1) break;
                            bool isMatched = entry.matchIndices.canFind(cast(int) charIdx);
                            Color chFg = isMatched ? ctx.accent : ctx.muted;
                            ubyte chAttr = isMatched ? (CellAttr.bold | CellAttr.underline) : CellAttr.dim;
                            grid.putCell(curX, r, ch, CellStyle(chFg, rowBg, chAttr));
                            curX++;
                        }
                    }
                }
                else
                {
                    // Browse mode: render entry name with highlighted matched chars
                    string dispName = entry.name ~ (entry.isDir && !entry.isParent ? "/" : "");
                    dstring dname = to!dstring(dispName);
                    int maxNameW = max(0, infoCol - nameCol - 2);

                    int curX = nameCol;
                    foreach (charIdx, dchar ch; dname)
                    {
                        if (curX >= nameCol + maxNameW) break;
                        bool isMatched = entry.matchIndices.canFind(cast(int) charIdx);
                        Color chFg = isMatched ? ctx.accent : nameFg;
                        ubyte chAttr = isMatched ? (CellAttr.bold | CellAttr.underline) : nameAttr;
                        grid.putCell(curX, r, ch, CellStyle(chFg, rowBg, chAttr));
                        curX++;
                    }
                }

                if (infoCol > nameCol + 4)
                {
                    grid.putString(infoCol, r, infoStr, CellStyle(ctx.muted, rowBg));
                }

                clickRows ~= ClickableRow(itemIdx, r, modalX + 1, modalX + modalW - 1);
            }
            else
            {
                grid.fillRect(modalX + 1, r, modalW - 2, 1, ' ', CellStyle(ctx.muted, modalBg));
            }
        }

        // 5. File Name Editor Row (saveFile mode only)
        if (mode == FilePickerMode.saveFile)
        {
            int nameY = modalY + modalH - 2;
            grid.fillRect(modalX, nameY, modalW, 1, ' ', CellStyle(ctx.text, searchBg));

            string nameLabel = ctx.showIcons ? " 󰈔 File Name: " : " File Name: ";
            grid.putString(modalX + 1, nameY, nameLabel, CellStyle(isEditingFileName ? ctx.accent : ctx.muted, searchBg, CellAttr.bold));

            int nameInCol = modalX + 1 + btnW(nameLabel);
            int maxNameInW = max(4, modalW - (nameInCol - modalX) - 2);
            if (saveFileName.length > 0)
            {
                grid.putString(nameInCol, nameY, saveFileName, CellStyle(ctx.text, searchBg, CellAttr.bold), maxNameInW);
                if (isEditingFileName)
                {
                    int curPos = min(maxNameInW - 1, cast(int) saveFileName.length);
                    int cursorCol = nameInCol + curPos;
                    if (ctx.blink && cursorCol >= 0 && cursorCol < grid.cols && nameY >= 0 && nameY < grid.rows)
                    {
                        auto cell = &grid.cells[nameY * grid.cols + cursorCol];
                        cell.style.attrs |= CellAttr.negative;
                    }
                }
            }
            else
            {
                grid.putString(nameInCol, nameY, "Enter file name...", CellStyle(ctx.muted, searchBg, CellAttr.italic), maxNameInW);
                if (isEditingFileName)
                {
                    int cursorCol = nameInCol;
                    if (ctx.blink && cursorCol >= 0 && cursorCol < grid.cols && nameY >= 0 && nameY < grid.rows)
                    {
                        auto cell = &grid.cells[nameY * grid.cols + cursorCol];
                        cell.style.attrs |= CellAttr.negative;
                    }
                }
            }
        }

        // 6. Action Bar (Row modalH - 1)
        int actionY = modalY + modalH - 1;
        grid.fillRect(modalX, actionY, modalW, 1, ' ', CellStyle(ctx.text, headerBg));

        if (mode == FilePickerMode.saveFile)
        {
            string cancelBtn = " Cancel ";
            int cancelW = btnW(cancelBtn);
            int cancelCol = modalX + modalW - 1 - cancelW;
            grid.putString(cancelCol, actionY, cancelBtn, CellStyle(ctx.text, btnBg));
            clickButtons ~= ClickableButton(7, actionY, cancelCol, cancelCol + cancelW);

            string saveBtn = ctx.showIcons ? " 󰆓 Save " : " Save ";
            int saveW = btnW(saveBtn);
            int saveCol = cancelCol - saveW;
            grid.putString(saveCol, actionY, saveBtn, CellStyle(Color.black, accentBtnBg, CellAttr.bold));
            clickButtons ~= ClickableButton(9, actionY, saveCol, saveCol + saveW);

            string curBase = baseName(currentDir);
            if (curBase.length == 0) curBase = currentDir;
            string destPreview = " 󰈔 " ~ curBase ~ "/" ~ (saveFileName.length > 0 ? saveFileName : "untitled.txt");
            int maxPreviewW = max(10, saveCol - modalX - 2);
            dstring dpreview = to!dstring(destPreview);
            if (dpreview.length > maxPreviewW)
                dpreview = (maxPreviewW > 1) ? dpreview[0 .. maxPreviewW - 1] ~ "…"d : dpreview[0 .. maxPreviewW];
            grid.putString(modalX + 1, actionY, dpreview, CellStyle(ctx.text, headerBg, CellAttr.bold));
        }
        else if (mode == FilePickerMode.openFolder)
        {
            string cancelBtn = " Cancel ";
            int cancelW = btnW(cancelBtn);
            int cancelCol = modalX + modalW - 1 - cancelW;
            grid.putString(cancelCol, actionY, cancelBtn, CellStyle(ctx.text, btnBg));
            clickButtons ~= ClickableButton(7, actionY, cancelCol, cancelCol + cancelW);

            string selectBtn = ctx.showIcons ? " 󰉋 Select Folder " : " Select Folder ";
            int selW = btnW(selectBtn);
            int selCol = cancelCol - selW;
            grid.putString(selCol, actionY, selectBtn, CellStyle(Color.black, accentBtnBg, CellAttr.bold));
            clickButtons ~= ClickableButton(6, actionY, selCol, selCol + selW);

            string curBase = baseName(currentDir);
            if (curBase.length == 0) curBase = currentDir;
            string leftText = ctx.showIcons ? (" 󰉋 " ~ curBase) : (" " ~ curBase);
            int maxLeftW = max(10, selCol - modalX - 2);
            dstring dleft = to!dstring(leftText);
            if (dleft.length > maxLeftW)
                dleft = (maxLeftW > 1) ? dleft[0 .. maxLeftW - 1] ~ "…"d : dleft[0 .. maxLeftW];
            grid.putString(modalX + 1, actionY, dleft, CellStyle(ctx.text, headerBg, CellAttr.bold));
        }
        else
        {
            string cancelBtn = " Cancel ";
            int cancelW = btnW(cancelBtn);
            int cancelCol = modalX + modalW - 1 - cancelW;
            grid.putString(cancelCol, actionY, cancelBtn, CellStyle(ctx.text, btnBg));
            clickButtons ~= ClickableButton(7, actionY, cancelCol, cancelCol + cancelW);

            string openBtn = " Open ";
            int openW = btnW(openBtn);
            int openCol = cancelCol - openW;
            grid.putString(openCol, actionY, openBtn, CellStyle(Color.black, accentBtnBg, CellAttr.bold));
            clickButtons ~= ClickableButton(8, actionY, openCol, openCol + openW);

            string selText = "No file selected";
            if (selectedIndex >= 0 && selectedIndex < filteredEntries.length)
            {
                auto ent = filteredEntries[selectedIndex];
                if (mode == FilePickerMode.fuzzyFile)
                {
                    string rel = ent.relativePath.length ? ent.relativePath : ent.name;
                    selText = ctx.showIcons ? (" 󰈔 " ~ rel) : (" " ~ rel);
                }
                else
                {
                    if (ctx.showIcons)
                        selText = ent.isDir ? (" 󰉋 " ~ ent.name ~ "/ (Enter to open)") : (" 󰈔 " ~ ent.name);
                    else
                        selText = ent.isDir ? (ent.name ~ "/ (Enter to open)") : ent.name;
                }
            }
            int maxSelW = max(10, openCol - modalX - 2);
            dstring dsel = to!dstring(selText);
            if (dsel.length > maxSelW)
                dsel = (maxSelW > 1) ? dsel[0 .. maxSelW - 1] ~ "…"d : dsel[0 .. maxSelW];
            grid.putString(modalX + 1, actionY, dsel, CellStyle(ctx.text, headerBg, CellAttr.bold));
        }
    }

    }


void renderFilePickerReal(FilePickerExtension picker, SDL_Renderer* renderer, FontEngine font, FilePickerContext ctx, float padX, float padY)
{
    with (picker)
    {
        if (!visible) return;

        float rx = padX + modalX * font.charWidth;
        float ry = padY + modalY * font.lineHeight;
        float rw = modalW * font.charWidth;
        float rh = modalH * font.lineHeight;

        // Real smooth vector scrollbar
        float trackX = rx + rw - 6.0f;
        float trackY = ry + 2 * font.lineHeight + 2.0f;
        float trackH = visibleRowCount * font.lineHeight - 4.0f;
        drawRealScrollbar(renderer, trackX, trackY, 4.0f, trackH,
                          cast(int) filteredEntries.length, visibleRowCount, scrollOffset,
                          ctx.accent, Color(ctx.border.r, ctx.border.g, ctx.border.b, 60));
    }
}
