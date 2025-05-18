# Sum

Sum is an iOS utility that extracts numbers from documents or photos and quickly totals them. It leverages Vision and CoreML to recognize digits and keeps a history of your scans.

## Main Features
- Scan paper receipts or documents using the built‑in document camera.
- Pick an image from your photo library and crop the area of interest.
- Live OCR mode (iOS 17+) shows a running total while the camera is active.
- Interactive digit correction for improved accuracy.
- Stores past scans with their totals for later review.

## Prerequisites
- **Xcode 16.3 or later.** The project’s `LastUpgradeCheck` is `1630`.
- **iOS 18.4 or newer** deployment target.
- Live OCR requires iOS 17+ and a device that supports `DataScanner`.

## Build & Run
1. Clone this repository.
2. Open `Sum.xcodeproj` in Xcode.
3. Select the **Sum** scheme and choose a device or simulator running iOS 18.4 or later.
4. Build and run.

The app requests camera and photo library permissions on first launch so it can scan documents and import images.
