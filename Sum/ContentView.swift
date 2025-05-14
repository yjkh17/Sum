import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ScanRecord]
    @StateObject private var scanVM = ScannerViewModel()
    @StateObject private var navVM  = NavigationViewModel()
    @State private var liveCrop: CGRect? = nil        // live-OCR crop rectangle
    @State private var liveHighlights: [CGRect] = []  // rects from Live OCR
    @State private var liveConfs: [Float] = []        // confidences
    @State private var isCropMode = false             // crop-drawing toggle
    /// iPhone = .compact  /  iPad = .regular
    @Environment(\.horizontalSizeClass) private var hSize

    // MARK: - Re-usable state & helpers (kept)
    // MARK: - Unified toolbar for iPhone & iPad
    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        // leading buttons
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { navVM.isShowingScanner = true } label: {
                Label("Scan", systemImage: "camera.viewfinder")
            }
            Button { navVM.isShowingPhotoPicker = true } label: {
                Label("Photo", systemImage: "photo.on.rectangle")
            }
        }
        // trailing buttons / menu
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if #available(iOS 17.0, *) {
                Button {
                    scanVM.startLiveScan()
                    navVM.isShowingLiveScanner = true
                } label: {
                    Label("Live", systemImage: "eye")
                }
            }
            Menu {
                Picker("Digits", selection: $scanVM.storedSystem) {
                    Text("Western 0-9").tag(NumberSystem.western)
                    Text("Eastern ٠-٩").tag(NumberSystem.eastern)
                }
            } label: {
                Image(systemName: "textformat.123").symbolVariant(.circle)
            }
            EditButton()
        }
    }

    // MARK: - Master & Detail builders
    private var masterList: some View {
        List {
            ForEach(records) { rec in
                NavigationLink {
                    RecordDetailView(record: rec,
                                     image: imageFor(record: rec))
                } label: {
                    HStack {
                        Text(rec.date, format: .dateTime.hour().minute().second())
                        Spacer()
                        Text(rec.total, format: .number)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteRecords)
        }                                     // ← END List
    }

    private var detailPane: some View {
        Group {
            if scanVM.numbers.isEmpty {
                Text("Select an item")
                    .foregroundStyle(.secondary)
            } else {
                ResultCardView(sum: scanVM.sum, numbers: scanVM.numbers)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hSize == .compact {              // iPhone
                    masterList
                        .navigationTitle("History")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { rootToolbar }
                } else {                            // iPad / wide
                    NavigationSplitView {
                        masterList
                    } detail: {
                        detailPane
                    }
                    .toolbar { rootToolbar }
                }
            }
        }
        .sheet(isPresented: $navVM.isShowingScanner) {
            DocumentScannerView { nums in
                scanVM.handleScanCompleted(nums)
            }
        }
        .fullScreenCover(isPresented: $navVM.isShowingPhotoPicker) {
            NavigationStack {                    // gives us a nav-bar if needed
                PhotoPickerView { img in           // now SwiftUI picker
                    scanVM.handlePickedImage(img)
                    navVM.isShowingPhotoPicker = false
                    navVM.isShowingCropper     = true
                }
                .navigationTitle("Choose a Photo")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .fullScreenCover(isPresented: $navVM.isShowingLiveScanner) {
            if #available(iOS 17.0, *) {
                NavigationStack {
                    LiveScannerView(
                        numberSystem:  $scanVM.storedSystem,
                        onNumbersUpdate: { nums in
                            scanVM.handleLiveNumbers(nums)
                        },
                        highlights:      $liveHighlights,
                        highlightConfs:  $liveConfs,
                        cropRect:        $liveCrop
                    )
                    .overlay(                              // 1) live total label (no hit‑test)
                        LiveOverlayView(numbers: scanVM.liveNumbers)
                            .allowsHitTesting(false)       // let gestures pass through
                    )
                    .overlay(
                        LiveHighlightOverlay(rects: liveHighlights,
                                             rectConfs: liveConfs)
                    )
                    .overlay {
                        if isCropMode {
                            LiveCropOverlay(crop: $liveCrop)
                        }
                    }
                    .ignoresSafeArea()                     // fill whole screen
                    .toolbar {
                        // “Done” button to exit live OCR (also clears any crop)
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                navVM.isShowingLiveScanner = false
                                liveCrop = nil             // clear crop on exit
                            }
                        }
                        // Crop / clear-crop toggle (only in Live-OCR screen)
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                liveCrop = nil             // clear current crop
                            } label: {
                                Image(systemName: liveCrop == nil
                                                  ? "scissors"
                                                  : "scissors.badge.minus")
                            }
                            .accessibilityLabel("Clear crop")
                        }
                    }
                }
            } else {
                Text("Live OCR requires iOS 17 or later.")
            }
        }
        .fullScreenCover(isPresented: $navVM.isShowingCropper) {
            if let uiImage = scanVM.pickedImage {
                // Wrap in NavigationStack so the toolbar (Done/Cancel) is visible
                NavigationStack {
                    ImageCropperView(image: uiImage) { cropImage, obs, fixes in
                        scanVM.handleCroppedNumbers(obs.map(\.value), fixes: fixes)
                        scanVM.receiveCroppedResult(image: cropImage,
                                                    observations: obs)
                        navVM.isShowingCropper = false
                        navVM.isShowingResult  = true
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .fullScreenCover(isPresented: $navVM.isShowingResult) {
            if let img = scanVM.croppedImage,
               let obs = scanVM.croppedObservations {
                CroppedResultView(image: img, observations: obs)
                    .onTapGesture { navVM.isShowingResult = false } // tap to dismiss
            }
        }
        .sheet(isPresented: $scanVM.isShowingFixSheet) {
            FixDigitSheet(fixes: $scanVM.pendingFixes) {
                scanVM.finishFixes()
            }
        }
        .alert("Total", isPresented: $scanVM.showSumAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanVM.lastSum, format: .number)
        }
    }

    private func deleteRecords(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(records[index])
            }
        }
    }

    /// Load the cropped image (if any) from Documents
    private func imageFor(record: ScanRecord) -> UIImage? {
        guard let name = record.imagePath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(name)
        return UIImage(contentsOfFile: url.path)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
