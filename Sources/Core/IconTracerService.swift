import Foundation
import CoreGraphics

// MARK: - Icon Border Tracer

public struct IconTracerService {
    
    /// Traces the dark cartoon border (Roblox UIStroke, luminance < 48) of an icon graphic
    /// located directly above a detected text bounding box.
    /// Returns the exact bounding box and center point in normalized Vision coordinates (0..1, bottom-left origin).
    public static func traceIconBounds(
        in image: CGImage,
        textBoundingBox: CGRect
    ) -> (bounds: CGRect, center: CGPoint)? {
        let imgW = Double(image.width)
        let imgH = Double(image.height)
        guard imgW > 50 && imgH > 50 else { return nil }
        
        // Convert Vision text box (bottom-left 0..1) to CGImage pixel coordinates (top-left 0..px)
        let textPixelX = textBoundingBox.minX * imgW
        let textPixelW = textBoundingBox.width * imgW
        let textPixelTopY = (1.0 - textBoundingBox.maxY) * imgH
        let textPixelH = textBoundingBox.height * imgH
        let textMidX = textPixelX + (textPixelW * 0.5)
        
        // Define Region of Interest (ROI) directly above the text label
        let roiW = max(textPixelW * 1.6, textPixelH * 3.5)
        let roiH = textPixelH * 3.4
        let roiX = max(0, textMidX - (roiW * 0.5))
        let roiY = max(0, textPixelTopY - roiH)
        let roiActualW = min(imgW - roiX, roiW)
        let roiActualH = min(imgH - roiY, roiH + (textPixelH * 0.25))
        
        let roiRect = CGRect(x: roiX, y: roiY, width: roiActualW, height: roiActualH)
        guard let cropped = image.cropping(to: roiRect),
              let data = cropped.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        
        let w = cropped.width
        let h = cropped.height
        let bpr = cropped.bytesPerRow
        let bpp = cropped.bitsPerPixel / 8
        guard bpp >= 3 && w >= 15 && h >= 15 else { return nil }
        
        // Threshold for black/dark cartoon stroke (UIStroke in Pet Simulator 99)
        let darkCutoff = 48
        let textCutoffY = max(0, Int(Double(h) - (textPixelH * 0.30)))
        
        var darkPoints: [(x: Int, y: Int)] = []
        var colDarkCounts = [Int](repeating: 0, count: w)
        
        for y in 0..<textCutoffY {
            let rowOffset = y * bpr
            for x in 0..<w {
                let offset = rowOffset + (x * bpp)
                let r = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let b = Int(ptr[offset + 2])
                let lum = (r * 299 + g * 587 + b * 114) / 1000
                if lum < darkCutoff {
                    darkPoints.append((x: x, y: y))
                    colDarkCounts[x] += 1
                }
            }
        }
        
        guard darkPoints.count >= 20 else { return nil }
        
        // Column gap isolation: isolate target button border from adjacent buttons (e.g. Leagues)
        let localMidX = max(0, min(w - 1, Int(textMidX - roiX)))
        guard let (minColX, maxColX) = isolateColumnBounds(colCounts: colDarkCounts, localMidX: localMidX, width: w) else {
            return nil
        }
        
        // Filter dark points to the isolated column region
        let iconDark = darkPoints.filter { $0.x >= minColX && $0.x <= maxColX }
        guard iconDark.count >= 20 else { return nil }
        
        let minY = iconDark.map { $0.y }.min() ?? 0
        let maxY = iconDark.map { $0.y }.max() ?? textCutoffY
        let minX = minColX
        let maxX = maxColX
        
        let iconPixelW = Double(maxX - minX)
        let iconPixelH = Double(maxY - minY)
        guard iconPixelW >= 8 && iconPixelH >= 8 else { return nil }
        
        // Exact geometric centroid of the traced border
        let iconLocalMidX = Double(minX + maxX) * 0.5
        let iconLocalMidY = Double(minY + maxY) * 0.5
        
        // Map back to absolute image coordinates
        let absCenterX = roiX + iconLocalMidX
        let absCenterY = roiY + iconLocalMidY
        
        // Convert to Vision coordinates (0..1, bottom-left origin)
        let visionCenterX = absCenterX / imgW
        let visionCenterY = 1.0 - (absCenterY / imgH)
        
        let visionBoxX = (roiX + Double(minX)) / imgW
        let visionBoxY = 1.0 - ((roiY + Double(maxY)) / imgH)
        let visionBoxW = iconPixelW / imgW
        let visionBoxH = iconPixelH / imgH
        let visionBox = CGRect(x: visionBoxX, y: visionBoxY, width: visionBoxW, height: visionBoxH)
        
        return (bounds: visionBox, center: CGPoint(x: visionCenterX, y: visionCenterY))
    }
    
    /// Isolates horizontal bounds of the central icon by scanning left/right from text center
    /// until hitting zero-dark-pixel column gaps that separate adjacent UI buttons.
    private static func isolateColumnBounds(colCounts: [Int], localMidX: Int, width: Int) -> (Int, Int)? {
        guard localMidX >= 0 && localMidX < width else { return nil }
        
        // Scan left from center until hitting an empty column gap
        var leftX = localMidX
        while leftX > 0 {
            if colCounts[leftX] == 0 && colCounts[max(0, leftX - 1)] == 0 {
                break
            }
            leftX -= 1
        }
        while leftX < localMidX && colCounts[leftX] == 0 {
            leftX += 1
        }
        
        // Scan right from center until hitting an empty column gap
        var rightX = localMidX
        while rightX < width - 1 {
            if colCounts[rightX] == 0 && colCounts[min(width - 1, rightX + 1)] == 0 {
                break
            }
            rightX += 1
        }
        while rightX > localMidX && colCounts[rightX] == 0 {
            rightX -= 1
        }
        
        guard rightX - leftX >= 8 else { return nil }
        return (leftX, rightX)
    }
    
    /// Refines a detected event target by tracing its black cartoon border.
    /// Falls back gracefully to the original proportional coordinates if border tracing fails.
    public static func refineTarget(_ target: DetectedText, in image: CGImage) -> DetectedText {
        guard let traced = traceIconBounds(in: image, textBoundingBox: target.boundingBox) else {
            return target
        }
        return DetectedText(
            text: target.text,
            boundingBox: target.boundingBox,
            targetPoint: traced.center,
            wholeIconBox: traced.bounds,
            wordBoxes: target.wordBoxes
        )
    }
}
