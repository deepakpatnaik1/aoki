//
//  StitchingManager.swift
//  Aoki
//

import AppKit
import Vision

class StitchingManager {
    // MARK: - Properties
    private var runningStitchedImage: NSImage?
    private var previousImage: NSImage? // The most recent screenshot to use for comparison.
    private let stitchingQueue = DispatchQueue(label: "com.scrollsnap.stitching", qos: .userInitiated)
    
    // MARK: - Public API
    
    func startStitching(with initialImage: NSImage) {
        runningStitchedImage = initialImage
        previousImage = initialImage // On start, the initial image is also the previous one.
    }
    
    func addImage(_ image: NSImage) {
        stitchingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure we have a base stitched image and a previous image to compare against.
            guard let baseStitchedImage = self.runningStitchedImage,
                  let prevImage = self.previousImage else {
                // This case should ideally not be hit after startStitching is called.
                self.runningStitchedImage = image
                self.previousImage = image
                return
            }
            
            // Calculate the offset by comparing the new image with the *previous* one.
            // This supports both downward scrolling (positive offset) and upward scrolling (negative offset).
            guard let offsetInPoints = self.calculateOffset(from: image, to: prevImage) else {
                // If we fail to find an offset, update previousImage and wait for the next one.
                self.previousImage = image
                return
            }

            if offsetInPoints > 0 {
                // Downward scroll: composite the new image onto the bottom of the stitched image.
                guard let newStitchedImage = self.composite(baseImage: baseStitchedImage, newImage: image, offset: offsetInPoints) else {
                    return
                }

                self.runningStitchedImage = newStitchedImage
                self.previousImage = image

            } else if offsetInPoints < 0 {
                // Upward scroll: crop from the bottom of the stitched image.
                let cropAmount = abs(offsetInPoints)

                // Validate crop amount is reasonable.
                guard cropAmount <= baseStitchedImage.size.height,
                      let croppedImage = self.cropBottomRegion(of: baseStitchedImage, byAmount: cropAmount) else {
                    self.previousImage = image
                    return
                }

                self.runningStitchedImage = croppedImage
                self.previousImage = image

            } else {
                // No scroll detected, skip this frame.
                self.previousImage = image
            }
        }
    }
    
    func stopStitching() async -> NSImage? {
        return await withCheckedContinuation { continuation in
            // Enqueue a task to run after all previous tasks on the serial queue.
            // This task will then resume the continuation with the final image.
            stitchingQueue.async { [weak self] in
                continuation.resume(returning: self?.runningStitchedImage)
            }
        }
    }
    
    // MARK: - Private Stitching Methods
    
    private func calculateOffset(from currentImage: NSImage, to previousImage: NSImage) -> CGFloat? {
        // Crop both top and bottom of images before comparing.
        // This excludes sticky headers AND footers from Vision's alignment calculation.
        let topMargin: CGFloat = 200    // points to crop from visual top
        let bottomMargin: CGFloat = 100 // points to crop from visual bottom

        guard let croppedCurrent = cropVerticalMargins(of: currentImage, top: topMargin, bottom: bottomMargin),
              let croppedPrevious = cropVerticalMargins(of: previousImage, top: topMargin, bottom: bottomMargin) else {
            return nil
        }

        guard let currentCG = croppedCurrent.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let previousCG = croppedPrevious.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        guard let verticalOffsetInPixels = findVerticalOffset(from: currentCG, to: previousCG) else {
            return nil
        }

        // Convert the pixel-based offset from Vision to a point-based offset for AppKit drawing.
        guard croppedCurrent.size.height > 0 else { return nil }
        let scale = CGFloat(currentCG.height) / croppedCurrent.size.height
        return verticalOffsetInPixels / (scale > 0 ? scale : 1.0)
    }

    private func cropVerticalMargins(of image: NSImage, top: CGFloat, bottom: CGFloat) -> NSImage? {
        let originalSize = image.size
        let totalCrop = top + bottom
        guard totalCrop < originalSize.height else { return image }

        let newHeight = originalSize.height - totalCrop
        let newSize = NSSize(width: originalSize.width, height: newHeight)

        let croppedImage = NSImage(size: newSize)
        croppedImage.lockFocus()

        // NSImage uses bottom-left origin (y=0 at bottom).
        // Visual TOP of image = high y values in NSImage coords.
        // Visual BOTTOM of image = low y values (near 0).
        //
        // To remove visual top: skip the highest y values
        // To remove visual bottom: skip the lowest y values (start at y=bottom)
        //
        // Source rect: start at y=bottom, take newHeight pixels
        let sourceRect = NSRect(x: 0, y: bottom, width: originalSize.width, height: newHeight)
        let destRect = NSRect(origin: .zero, size: newSize)

        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)

        croppedImage.unlockFocus()
        return croppedImage
    }
    
    private func findVerticalOffset(from image1: CGImage, to image2: CGImage) -> CGFloat? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: image2)
        let handler = VNImageRequestHandler(cgImage: image1, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        // For a downward scroll, the new image (image1) is below the old one (image2).
        // To align image1 with image2, it must be shifted UP, resulting in a positive 'ty' value.
        // For an upward scroll, ty will be negative.
        return observation.alignmentTransform.ty
    }
    
    private func composite(baseImage: NSImage, newImage: NSImage, offset: CGFloat) -> NSImage? {
        // Strategy: Draw new image first, then base on top.
        // The base covers the overlap region, hiding sticky headers from the new image.

        guard let newCG = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let baseCG = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scale = CGFloat(newCG.height) / newImage.size.height
        let offsetInPixels = Int(offset * scale)

        // Total height = base height + offset (the new non-overlapping content)
        let totalHeight = baseCG.height + offsetInPixels
        let width = baseCG.width

        guard let colorSpace = baseCG.colorSpace,
              let context = CGContext(
                data: nil,
                width: width,
                height: totalHeight,
                bitsPerComponent: baseCG.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: baseCG.bitmapInfo.rawValue
              ) else {
            return nil
        }

        // CGContext: y=0 at bottom.
        // 1. Draw new image at the bottom of canvas (y=0)
        context.draw(newCG, in: CGRect(x: 0, y: 0, width: width, height: newCG.height))

        // 2. Draw base image on top, starting at y=offsetInPixels
        //    This covers the overlap region (where sticky elements would duplicate)
        context.draw(baseCG, in: CGRect(x: 0, y: offsetInPixels, width: width, height: baseCG.height))

        guard let outputCG = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: outputCG, size: NSSize(width: baseImage.size.width, height: baseImage.size.height + offset))
    }

    private func cropBottomRegion(of image: NSImage, byAmount amount: CGFloat) -> NSImage? {
        let originalSize = image.size
        guard amount > 0, amount < originalSize.height else { return image }

        let newHeight = originalSize.height - amount
        let newSize = NSSize(width: originalSize.width, height: newHeight)

        let croppedImage = NSImage(size: newSize)
        croppedImage.lockFocus()

        // Keep the top content, crop from the bottom.
        let sourceRect = NSRect(x: 0, y: amount, width: originalSize.width, height: newHeight)
        let destRect = NSRect(origin: .zero, size: newSize)

        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)

        croppedImage.unlockFocus()
        return croppedImage
    }
}
