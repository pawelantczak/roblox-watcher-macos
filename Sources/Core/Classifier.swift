import Foundation
import CoreGraphics

// MARK: - Classification & Filtering

public struct WatcherClassifier {
    
    /// Returns true if the text matches any non-fatal phrase that must be ignored.
    public static func isIgnored(text: String, ignorePhrases: [String]) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return ignorePhrases.contains { p in
            let cl = p.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !cl.isEmpty && lower.contains(cl)
        }
    }
    
    /// Returns true if the text indicates a fatal disconnect requiring action.
    public static func isFatalDisconnect(text: String, disconnectKeywords: [String], ignorePhrases: [String]) -> Bool {
        if isIgnored(text: text, ignorePhrases: ignorePhrases) { return false }
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return disconnectKeywords.contains { kw in
            let k = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !k.isEmpty && lower.contains(k)
        }
    }
    
    /// Scans detected text items for the reconnect button, honoring ignore phrases.
    public static func findReconnectButton(
        in items: [DetectedText],
        buttonText: String,
        ignorePhrases: [String]
    ) -> DetectedText? {
        let target = buttonText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        
        for item in items {
            if isIgnored(text: item.text, ignorePhrases: ignorePhrases) {
                continue
            }
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.caseInsensitiveCompare(buttonText) == .orderedSame || trimmed.lowercased() == target {
                return item
            }
        }
        return nil
    }
    
    /// Levenshtein edit distance between two strings.
    public static func editDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1)
                }
            }
        }
        return dist[a.count][b.count]
    }
    
    /// Fuzzy word matcher accounting for font OCR misreadings (e.g. Turkcy, Hung, Hun?).
    public static func wordMatches(ocrWord: String, targetToken: String) -> Bool {
        let ocr = ocrWord.lowercased().filter { $0.isLetter || $0.isNumber }
        let target = targetToken.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !ocr.isEmpty && !target.isEmpty else { return false }
        if ocr == target { return true }
        
        let normOcr = ocr.replacingOccurrences(of: "c", with: "e").replacingOccurrences(of: "g", with: "t")
        let normTarget = target.replacingOccurrences(of: "c", with: "e").replacingOccurrences(of: "g", with: "t")
        if normOcr == normTarget { return true }
        
        let dist = editDistance(normOcr, normTarget)
        if target.count <= 3 {
            return dist == 0
        } else if target.count <= 5 {
            return dist <= 1
        } else {
            return dist <= 2
        }
    }
    
    private struct KeywordTarget {
        let tokens: [String]
        let requiresAll: Bool
    }
    
    private static func parseKeywordTargets(_ keywords: [String]) -> [KeywordTarget] {
        keywords.flatMap { kw -> [KeywordTarget] in
            let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return [] }
            let hasComma = trimmed.contains(",")
            let parts = hasComma ? trimmed.components(separatedBy: ",") : [trimmed]
            return parts.compactMap { p in
                let tok = p.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                return tok.isEmpty ? nil : KeywordTarget(tokens: tok, requiresAll: !hasComma && tok.count > 1)
            }
        }
    }
    
    /// Identifies event icons on the left UI panel (origin.x < maxNormalizedX).
    /// If keywords contain no commas, the string is treated as a single unified phrase requiring all tokens.
    public static func findEventTarget(
        in items: [DetectedText],
        keywords: [String],
        maxNormalizedX: CGFloat = 0.35
    ) -> DetectedText? {
        let targets = parseKeywordTargets(keywords)
        guard !targets.isEmpty else { return nil }
        
        let candidateItems = items.filter { $0.boundingBox.origin.x < maxNormalizedX }
        guard !candidateItems.isEmpty else { return nil }
        
        // Group candidate lines into vertically stacked button clusters
        var clusters: [[DetectedText]] = []
        var used = Set<Int>()
        let sortedCandidates = candidateItems.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        for i in 0..<sortedCandidates.count where !used.contains(i) {
            var cluster = [sortedCandidates[i]]
            used.insert(i)
            for j in (i + 1)..<sortedCandidates.count where !used.contains(j) {
                let top = cluster.last!
                let bottom = sortedCandidates[j]
                let alignedX = abs(top.boundingBox.midX - bottom.boundingBox.midX) < 0.05
                let verticalGap = top.boundingBox.minY - bottom.boundingBox.maxY
                if alignedX && verticalGap >= -0.02 && verticalGap < 0.05 {
                    cluster.append(bottom)
                    used.insert(j)
                    break
                }
            }
            clusters.append(cluster)
        }
        
        var matches: [DetectedText] = []
        for target in targets {
            for cluster in clusters {
                let clusterWords = cluster.flatMap { item in
                    !item.wordBoxes.isEmpty ? item.wordBoxes.map { $0.word } :
                        item.text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:\"'!?()[]{}"))).filter { !$0.isEmpty }
                }
                let matchedTokens = target.tokens.filter { tok in
                    clusterWords.contains { w in wordMatches(ocrWord: w, targetToken: tok) }
                }
                guard target.requiresAll ? (matchedTokens.count == target.tokens.count) : (!matchedTokens.isEmpty) else { continue }
                
                if cluster.count == 1 && !cluster[0].wordBoxes.isEmpty {
                    let matchingWords = cluster[0].wordBoxes.filter { wb in
                        target.tokens.contains { tok in wordMatches(ocrWord: wb.word, targetToken: tok) }
                    }
                    if !matchingWords.isEmpty {
                        let minX = matchingWords.map { $0.boundingBox.minX }.min() ?? cluster[0].boundingBox.minX
                        let maxX = matchingWords.map { $0.boundingBox.maxX }.max() ?? cluster[0].boundingBox.maxX
                        let minY = matchingWords.map { $0.boundingBox.minY }.min() ?? cluster[0].boundingBox.minY
                        let maxY = matchingWords.map { $0.boundingBox.maxY }.max() ?? cluster[0].boundingBox.maxY
                        let isolatedBox = CGRect(x: minX, y: minY, width: max(0.001, maxX - minX), height: max(0.001, maxY - minY))
                        let isolatedText = matchingWords.map { $0.word }.joined(separator: " ")
                        matches = [DetectedText(text: isolatedText, boundingBox: isolatedBox, wordBoxes: matchingWords)]
                        break
                    }
                }
                matches = cluster
                break
            }
            if !matches.isEmpty { break }
        }
        
        guard !matches.isEmpty else { return nil }
        
        // Sort lines top-to-bottom (higher y in Vision space = higher on screen)
        let sorted = matches.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let firstLine = sorted[0]
        
        let bottomY = sorted.map { $0.boundingBox.minY }.min() ?? firstLine.boundingBox.minY
        let minX = sorted.map { $0.boundingBox.minX }.min() ?? firstLine.boundingBox.minX
        let maxX = sorted.map { $0.boundingBox.maxX }.max() ?? firstLine.boundingBox.maxX
        let totalLabelHeight = max(0.005, firstLine.boundingBox.maxY - bottomY)
        
        // Dynamic Icon Center: The icon graphic container sits directly above the top line of text.
        // For single-line labels (Turkey Hunt), offset is 1.25x label height.
        // For multi-line stacked labels (Pumpkin Tycoon), offset is 1.0x total label height.
        let isMultiLine = sorted.count > 1
        let iconGraphicHeight = isMultiLine ? totalLabelHeight * 2.0 : totalLabelHeight * 2.5
        let iconCenterY = isMultiLine ? (firstLine.boundingBox.maxY + totalLabelHeight * 1.0) : (firstLine.boundingBox.maxY + totalLabelHeight * 1.25)
        let iconCenterX = firstLine.boundingBox.midX
        let clickTarget = CGPoint(x: iconCenterX, y: iconCenterY)
        
        let wholeIconWidth = max(maxX - minX, iconGraphicHeight)
        let wholeIconX = iconCenterX - (wholeIconWidth * 0.5)
        let wholeIconHeight = (firstLine.boundingBox.maxY + iconGraphicHeight) - bottomY
        let wholeIconBox = CGRect(x: wholeIconX, y: bottomY, width: max(0.001, wholeIconWidth), height: max(0.001, wholeIconHeight))
        
        if matches.count == 1 {
            return DetectedText(
                text: matches[0].text,
                boundingBox: matches[0].boundingBox,
                targetPoint: clickTarget,
                wholeIconBox: wholeIconBox,
                wordBoxes: matches[0].wordBoxes
            )
        }
        
        let combinedBox = CGRect(x: minX, y: bottomY, width: max(0.001, maxX - minX), height: max(0.001, firstLine.boundingBox.maxY - bottomY))
        let combinedText = sorted.map { $0.text }.joined(separator: " ")
        return DetectedText(
            text: combinedText,
            boundingBox: combinedBox,
            targetPoint: clickTarget,
            wholeIconBox: wholeIconBox,
            wordBoxes: sorted.flatMap { $0.wordBoxes }
        )
    }
}

// MARK: - Legacy / Convenience Utilities

public struct WatcherUtils {
    public static func parsePlaceId(from commandLine: String) -> String? {
        WindowService.parsePlaceId(from: commandLine)
    }
    
    public static func formatCountdown(seconds: Int) -> String {
        if seconds <= 0 { return "Clicking..." }
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "in \(m)m \(s < 10 ? "0" : "")\(s)s" : "in \(s)s"
    }
    
    public static func acquireKernelLock(lockFilePath: String) -> Int32? {
        LockManager.acquireLock(lockFilePath: lockFilePath)
    }
}

