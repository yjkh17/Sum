import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ScanRecord]
    @StateObject private var scanVM = ScannerViewModel()
    @StateObject private var navVM  = NavigationViewModel()
    @State private var liveCrop: CGRect? = nil        // live-OCR crop rectangle
    /// iPhone = .compact  /  iPad = .regular
    @Environment(\.horizontalSizeClass) private var hSize

    // MARK: - Re-usable toolbar
    @ToolbarContentBuilder
    private var toolBarContent: some ToolbarContent {
        // Consolidated leading buttons with SF-Symbol icons
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Spacer().frame(width: 8)          // فراغ أوضح مع حافة الشاشة
            Button {
                navVM.isShowingScanner = true
            } label: {
                Label("Scan", systemImage: "camera.viewfinder")
            }
            Button {
                navVM.isShowingPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo.on.rectangle")
            }
        }
        // Live-OCR + Crop buttons + digit picker grouped on trailing side
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if #available(iOS 17.0, *) {
                Button {
                    scanVM.startLiveScan()
                    navVM.isShowingLiveScanner = true
                } label: {
                    Label("Live", systemImage: "eye")
                }
                // Crop / clear-crop toggle (visible only while live scanner shown)
                if navVM.isShowingLiveScanner {
                    Button {
                        liveCrop = nil        // clear existing crop
                    } label: {
                        Image(systemName: liveCrop == nil
                                      ? "scissors"
                                      : "scissors.badge.minus")
                    }
                    .accessibilityLabel("Clear crop")
                }
            }
            // — existing digits menu —
            Menu {
                Picker("Digits", selection: $scanVM.storedSystem) {
                    Label("Western 0-9",  systemImage: "character")
                        .tag(NumberSystem.western)
                    Label("Eastern ٠-٩",  systemImage: "character")
                        .tag(NumberSystem.eastern)
                }
            } label: {
                Label { Text("") } icon: {
                    Image(systemName: "textformat.123").symbolVariant(.circle)
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Digit style")
                .accessibilityHint("Choose Western or Eastern numbers")
            }
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
        }
        }
        // Duplicate toolbar removed; root view already adds it.

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
        Group {
            if hSize == .compact {          // iPhone
                NavigationStack {
                    masterList
                }
            } else {                        // iPad / wide
                NavigationSplitView {
                    masterList
                } detail: {
                    detailPane
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
                .toolbar(content: {              // explicit builder removes ambiguity
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            navVM.isShowingPhotoPicker = false
                        }
                    }
                })
            }
        }
        .fullScreenCover(isPresented: $navVM.isShowingLiveScanner) {
            if #available(iOS 17.0, *) {
                NavigationStack {
                    LiveScannerView(numberSystem: $scanVM.storedSystem,
                                    cropRect: $liveCrop) { nums in
                        scanVM.handleLiveNumbers(nums)
                    }
                    .overlay(
                        LiveOverlayView(numbers: scanVM.liveNumbers)
                            .overlay(
                                LiveCropOverlay(crop: $liveCrop)  // drawing layer
                            )
                    )
                    .ignoresSafeArea()          // fill entire screen
                    .toolbar {
                        // “Done” button to exit live OCR
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                navVM.isShowingLiveScanner = false
                            }
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
