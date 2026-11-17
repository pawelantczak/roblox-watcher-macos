import Foundation
import AppKit
import CoreGraphics
import Vision
import ImageIO

// MARK: - Screen Capture & Vision OCR Service

public struct VisionService {
    
    public static func captureRobloxWindow(savePath: String) -> (image: CGImage, bounds: CGRect)? {
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        
        var windowBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        if let win = WindowService.findRobloxWindow() {
            task.arguments = ["-x", "-o", "-l", "\(win.windowId)", savePath]
            windowBounds = win.bounds
        } else {
            // Attempt to restore window if Roblox is running but minimized in Dock
            WindowService.unminimizeRobloxIfNeeded()
            if let win = WindowService.findRobloxWindow() {
                task.arguments = ["-x", "-o", "-l", "\(win.windowId)", savePath]
                windowBounds = win.bounds
            } else {
                // Safety: Never capture the user's primary monitor to prevent OCR false-positives
                return nil
            }
        }
        
        try? task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }
        let url = URL(fileURLWithPath: savePath) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return (cgImage, windowBounds)
    }
    
    public static func scanScreenForText(image: CGImage) -> (detected: [DetectedText], durationMs: Double) {
        let startTime = DispatchTime.now()
        var detected: [DetectedText] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                if let topCandidate = obs.topCandidates(1).first {
                    detected.append(DetectedText(text: topCandidate.string, boundingBox: obs.boundingBox))
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        
        let endTime = DispatchTime.now()
        let elapsedNano = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Double(elapsedNano) / 1_000_000.0
        return (detected, durationMs)
    }
    
    public static func createThumbnailBase64(from imageURL: URL, maxDimension: CGFloat = 960) -> String? {
        guard FileManager.default.fileExists(atPath: imageURL.path),
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: thumbnail)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.65]) else { return nil }
        return jpegData.base64EncodedString()
    }
}
