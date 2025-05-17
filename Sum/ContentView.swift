import SwiftUI
import SwiftData

// MARK: - History List Item
private struct HistoryRow: View {
    let date: Date
    let total: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Text(date, format: .dateTime.hour().minute())
                .monospacedDigit()
            
            Spacer()
            
            Text(total, format: .number)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ScanRecord]

    @StateObject private var scanVM = ScannerViewModel()
    @StateObject private var navVM  = NavigationViewModel()

    // Live-OCR state
    @State private var liveCrop: CGRect? = nil
    @State private var liveHighlights: [CGRect] = []
    @State private var liveConfs: [Float] = []
    @State private var liveScannerCoord: LiveScannerView.Coordinator? = nil

    @Environment(\.horizontalSizeClass) private var hSize

    // MARK: - List & detail helpers
    private var masterList: some View {
        List {
            ForEach(records) { rec in
                NavigationLink {
                    RecordDetailView(record: rec,
                                     image: imageFor(record: rec))
                } label: {
                    HistoryRow(date: rec.date, total: rec.total)
                }
            }
            .onDelete(perform: deleteRecords)
        }
        .listStyle(.plain)
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Scanned numbers will appear here")
                )
            }
        }
    }

    private var detailPane: some View {
        Group {
            if scanVM.numbers.isEmpty {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select an item from history")
                )
                .opacity(0.7)
            } else {
                ResultCardView(sum: scanVM.sum, numbers: scanVM.numbers)
            }
        }
    }

    // MARK: - Body
    var body: some View {
        Group {
            if hSize == .compact {
                NavigationStack {
                    masterList
                        .navigationTitle("History")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            RootToolbar(
                                showScanner: $navVM.isShowingScanner,
                                showPhotoPicker: $navVM.isShowingPhotoPicker,
                                showLiveScanner: $navVM.isShowingLiveScanner,
                                numberSystem: $scanVM.storedSystem,
                                onStartLiveScan: scanVM.startLiveScan
                            )
                        }
                }
            } else {
                NavigationSplitView {
                    masterList
                        .navigationTitle("History")
                } detail: {
                    detailPane
                }
                .toolbar {
                    RootToolbar(
                        showScanner: $navVM.isShowingScanner,
                        showPhotoPicker: $navVM.isShowingPhotoPicker,
                        showLiveScanner: $navVM.isShowingLiveScanner,
                        numberSystem: $scanVM.storedSystem,
                        onStartLiveScan: scanVM.startLiveScan
                    )
                }
            }
        }
        // MARK: - Document scanner
        .sheet(isPresented: $navVM.isShowingScanner) {
            DocumentScannerView { nums in
                scanVM.handleScanCompleted(nums)
            }
        }
        // MARK: - Photo picker
        .fullScreenCover(isPresented: $navVM.isShowingPhotoPicker) {
            NavigationStack {
                PhotoPickerView { img in
                    scanVM.handlePickedImage(img)
                    navVM.isShowingPhotoPicker = false
                    navVM.isShowingCropper     = true
                }
                .navigationTitle("Choose a Photo")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        // MARK: - Live OCR
        .fullScreenCover(isPresented: $navVM.isShowingLiveScanner) {
            if #available(iOS 17.0, *) {
                NavigationStack {
                    LiveScannerView(
                        numberSystem:    $scanVM.storedSystem,
                        onNumbersUpdate: { nums in
                            scanVM.liveNumbers = nums
                        },
                        highlights:      $liveHighlights,
                        highlightConfs:  $liveConfs,
                        cropRect:        $liveCrop,
                        onFixTap: { fix in
                            scanVM.currentFix = fix
                        },
                        onCoordinatorReady: { c in
                            liveScannerCoord = c
                        }
                    )
                    .overlay(
                        LiveOverlayView(numbers: scanVM.liveNumbers)
                            .allowsHitTesting(false)
                    )
                    .overlay(
                        LiveHighlightOverlay(rects: liveHighlights,
                                             rectConfs: liveConfs,
                                             onTap: { idx in
                                                 liveScannerCoord?.requestFix(at: idx)
                                             })
                    )
                    .overlay {
                        if let _ = liveCrop { LiveCropOverlay(crop: $liveCrop) }
                        LiveFixPopover(candidate: $scanVM.currentFix)
                            .environmentObject(scanVM)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .center)
                    }
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                navVM.isShowingLiveScanner = false
                                liveCrop = nil
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                liveCrop = nil
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
        // MARK: - Cropper
        .fullScreenCover(isPresented: $navVM.isShowingCropper) {
            if let uiImage = scanVM.pickedImage {
                NavigationStack {
                    ImageCropperView(image: uiImage) { cropImage, obs, fixes in
                        scanVM.handleCroppedNumbers(obs.map(\.value), fixes: fixes)
                        scanVM.receiveCroppedResult(image: cropImage, observations: obs)
                        navVM.isShowingCropper = false
                        navVM.isShowingResult  = true
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        // MARK: - Cropped result
        .fullScreenCover(isPresented: $navVM.isShowingResult) {
            if let img = scanVM.croppedImage,
               let obs = scanVM.croppedObservations {
                CroppedResultView(image: img, observations: obs)
                    .onTapGesture { navVM.isShowingResult = false }
            }
        }
        // MARK: - Fix-digit sheet (static scans only)
        .sheet(
            isPresented: Binding(
                get: { scanVM.isShowingFixSheet && !navVM.isShowingLiveScanner },
                set: { scanVM.isShowingFixSheet = $0 }
            )
        ) {
            FixDigitSheet(fixes: $scanVM.pendingFixes) {
                scanVM.finishFixes()
            }
        }
        // MARK: - Sum alert
        .alert("Total", isPresented: $scanVM.showSumAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanVM.lastSum, format: .number)
        }
    }

    // MARK: - Helpers
    private func deleteRecords(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(records[index])
            }
        }
    }

    private func imageFor(record: ScanRecord) -> UIImage? {
        guard let name = record.imagePath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(name)
        return UIImage(contentsOfFile: url.path)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
