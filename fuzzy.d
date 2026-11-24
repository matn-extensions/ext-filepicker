module matn.ui.shell.filepicker.fuzzy;

import std.algorithm : canFind, countUntil, max;
import std.ascii : isLower, isUpper;
import std.string : toLower;

/// Result of fuzzy matching a target string against a query pattern
struct FuzzyResult
{
    bool matched;
    int score;
    int[] indices; // Matched character indices in the target string
}

/// Computes a fuzzy match of query against target, returning whether it matched,
/// a relevance score, and the matched character indices.
FuzzyResult fuzzyMatch(string target, string query)
{
    if (query.length == 0)
        return FuzzyResult(true, 0, []);
    if (query.length > target.length)
        return FuzzyResult(false, 0, []);

    string lt = toLower(target);
    string lq = toLower(query);

    // Find last separator for filename detection
    int lastSlash = -1;
    foreach_reverse (i, ch; target)
    {
        if (ch == '/' || ch == '\\')
        {
            lastSlash = cast(int) i;
            break;
        }
    }
    int fnStart = lastSlash + 1;

    // 1. Check for exact substring match (prefer in filename)
    ptrdiff_t fnSubIdx = (fnStart < lt.length) ? lt[fnStart .. $].countUntil(lq) : -1;
    if (fnSubIdx >= 0)
    {
        int start = fnStart + cast(int) fnSubIdx;
        int score = 3000;
        if (start == fnStart)
            score += 800; // filename starts with query!
        if (start == fnStart && start + lq.length == target.length)
            score += 1000; // exact filename match!
        score += cast(int)(lq.length * 30);
        score -= cast(int)(target.length);

        int[] indices = new int[lq.length];
        foreach (i; 0 .. lq.length)
            indices[i] = start + cast(int) i;
        return FuzzyResult(true, score, indices);
    }

    ptrdiff_t subIdx = lt.countUntil(lq);
    if (subIdx >= 0)
    {
        int start = cast(int) subIdx;
        int score = 2000;
        score += 400; // in directory path
        score += cast(int)(lq.length * 30);
        score -= cast(int)(target.length);

        int[] indices = new int[lq.length];
        foreach (i; 0 .. lq.length)
            indices[i] = start + cast(int) i;
        return FuzzyResult(true, score, indices);
    }

    // 2. Multi-pass fuzzy match: evaluate boundary forward, simple forward, and backward
    int[] bestIndices;
    int bestScore = int.min;
    bool anyMatched = false;

    int[] candIndices;

    // A. Boundary-preferring forward pass
    if (findBoundaryForward(lt, lq, target, candIndices))
    {
        anyMatched = true;
        int sc = scoreIndices(target, candIndices, fnStart);
        if (sc > bestScore)
        {
            bestScore = sc;
            bestIndices = candIndices;
        }
    }

    // B. Backward pass (tends to match in filename when characters are repeated)
    if (findBackward(lt, lq, candIndices))
    {
        anyMatched = true;
        int sc = scoreIndices(target, candIndices, fnStart);
        if (sc > bestScore)
        {
            bestScore = sc;
            bestIndices = candIndices;
        }
    }

    // C. Simple forward pass
    if (findForward(lt, lq, candIndices))
    {
        anyMatched = true;
        int sc = scoreIndices(target, candIndices, fnStart);
        if (sc > bestScore)
        {
            bestScore = sc;
            bestIndices = candIndices;
        }
    }

    if (anyMatched)
    {
        return FuzzyResult(true, bestScore, bestIndices);
    }

    return FuzzyResult(false, 0, []);
}

private bool findForward(string lt, string lq, out int[] indices)
{
    indices = new int[lq.length];
    int tIdx = 0;
    foreach (qIdx, qChar; lq)
    {
        while (tIdx < lt.length && lt[tIdx] != qChar)
            tIdx++;
        if (tIdx >= lt.length)
            return false;
        indices[qIdx] = tIdx;
        tIdx++;
    }
    return true;
}

private bool findBackward(string lt, string lq, out int[] indices)
{
    indices = new int[lq.length];
    int tIdx = cast(int) lt.length - 1;
    foreach_reverse (qIdx, qChar; lq)
    {
        while (tIdx >= 0 && lt[tIdx] != qChar)
            tIdx--;
        if (tIdx < 0)
            return false;
        indices[qIdx] = tIdx;
        tIdx--;
    }
    return true;
}

private bool findBoundaryForward(string lt, string lq, string original, out int[] indices)
{
    indices = new int[lq.length];
    int tIdx = 0;
    foreach (qIdx, qChar; lq)
    {
        int found = -1;
        int check = tIdx;
        while (check < lt.length)
        {
            if (lt[check] == qChar)
            {
                bool isB = isBoundaryChar(original, check);
                if (isB && canMatchFrom(lt, check + 1, lq[qIdx + 1 .. $]))
                {
                    found = check;
                    break;
                }
            }
            check++;
        }

        if (found < 0)
        {
            while (tIdx < lt.length && lt[tIdx] != qChar)
                tIdx++;
            if (tIdx >= lt.length)
                return false;
            found = tIdx;
        }

        indices[qIdx] = found;
        tIdx = found + 1;
    }
    return true;
}

private bool canMatchFrom(string lt, int start, string remainingQ)
{
    int pos = start;
    foreach (ch; remainingQ)
    {
        while (pos < lt.length && lt[pos] != ch)
            pos++;
        if (pos >= lt.length)
            return false;
        pos++;
    }
    return true;
}

private bool isBoundaryChar(string target, int idx)
{
    if (idx == 0) return true;
    char prev = target[idx - 1];
    if (prev == '/' || prev == '\\' || prev == '_' || prev == '-' || prev == '.')
        return true;
    if (isLower(prev) && isUpper(target[idx]))
        return true;
    return false;
}

private int scoreIndices(string target, const int[] indices, int fnStart)
{
    if (indices.length == 0) return 0;

    int score = 200;
    int consecutive = 0;

    foreach (i, idx; indices)
    {
        // 1. Boundary bonus
        if (idx == 0)
        {
            score += 90;
        }
        else
        {
            char prev = target[idx - 1];
            if (prev == '/' || prev == '\\')
            {
                score += (idx >= fnStart) ? 140 : 80;
            }
            else if (prev == '_' || prev == '-' || prev == '.')
            {
                score += 70;
            }
            else if (isLower(prev) && isUpper(target[idx]))
            {
                score += 60; // camelCase
            }
        }

        // 2. Filename bonus
        if (idx >= fnStart)
        {
            score += 40;
        }

        // 3. Consecutive bonus
        if (i > 0 && idx == indices[i - 1] + 1)
        {
            consecutive++;
            score += 40 + (consecutive * 15);
        }
        else
        {
            consecutive = 0;
        }
    }

    // 4. Compactness penalty: span between first and last index
    int span = indices[$ - 1] - indices[0] + 1;
    score -= span * 2;

    // 5. Target length penalty
    score -= cast(int) target.length;

    return score;
}

unittest
{
    // Empty query matches everything with score 0
    auto r1 = fuzzyMatch("some/path/file.d", "");
    assert(r1.matched);
    assert(r1.score == 0);

    // Non-match
    auto r2 = fuzzyMatch("abc", "xyz");
    assert(!r2.matched);

    // Exact match in filename
    auto r3 = fuzzyMatch("tui/source/render.d", "render");
    assert(r3.matched);
    assert(r3.indices == [11, 12, 13, 14, 15, 16]);

    // Exact filename should outrank directory match
    auto rDir = fuzzyMatch("source/render/file.d", "render");
    assert(r3.score > rDir.score, "Filename exact match should outrank directory exact match");

    // Acronym / boundary match
    auto rAcronym = fuzzyMatch("tui/source/matn/extension/filepicker/package.d", "tsmefp");
    assert(rAcronym.matched);
    assert(rAcronym.indices.length == 6);

    // Fuzzy matching letters in filename
    auto rFuzzy = fuzzyMatch("source/matn/app/render.d", "rend");
    assert(rFuzzy.matched);
    assert(rFuzzy.indices.length == 4);

    // Filename matching preferred over ancestor directory matching
    auto rFuzzyFn = fuzzyMatch("test/renderer/render.d", "ren");
    assert(rFuzzyFn.matched);
    // Should match in filename 'render.d' rather than directory 'renderer'
    assert(rFuzzyFn.indices[0] == 14);
}
