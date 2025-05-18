import SwiftUI
import SwiftData
import AVFoundation
import VisionKit

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
    
    // Add loading state
    @State private var isReady = false

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

    private struct CustomToolbar: View {
        @ObservedObject var navVM: NavigationViewModel
        @ObservedObject var scanVM: ScannerViewModel
        
        var body: some View {
            HStack {
                // Leading items
                HStack(spacing: 16) {
                    Button { navVM.isShowingScanner = true } label: {
                        Label("Scan", systemImage: "camera.viewfinder")
                            .symbolEffect(.bounce, value: navVM.isShowingScanner)
                    }
                    Button { navVM.isShowingPhotoPicker = true } label: {
                        Label("Photo", systemImage: "photo.on.rectangle")
                            .symbolEffect(.bounce, value: navVM.isShowingPhotoPicker)
                    }
                }
                
                Spacer()
                
                // Trailing items
                HStack(spacing: 16) {
                    if #available(iOS 17.0, *) {
                        Button {
                            scanVM.startLiveScan()
                            navVM.isShowingLiveScanner = true
                        } label: {
                            Label("Live", systemImage: "eye")
                                .symbolEffect(.bounce, value: navVM.isShowingLiveScanner)
                        }
                    }
                    
                    Menu {
                        Picker("Digits", selection: $scanVM.storedSystem) {
                            Text("Western 0-9").tag(NumberSystem.western)
                            Text("Eastern ٠-٩").tag(NumberSystem.eastern)
                        }
                    } label: {
                        Image(systemName: "textformat.123")
                            .symbolVariant(.circle)
                    }
                    
                    EditButton()
                }
            }
            .padding()
            .background(.bar)
        }
    }
    
    private struct CompactView: View {
        @ObservedObject var navVM: NavigationViewModel
        @ObservedObject var scanVM: ScannerViewModel
        let masterList: AnyView
        
        var body: some View {
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
        }
    }
    
    private struct SplitView: View {
        @ObservedObject var navVM: NavigationViewModel
        @ObservedObject var scanVM: ScannerViewModel
        let masterList: AnyView
        let detailPane: AnyView
        
        var body: some View {
            NavigationSplitView {
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
            } detail: {
                detailPane
            }
        }
    }

    private struct MainContentView: View {
        @ObservedObject var navVM: NavigationViewModel
        @ObservedObject var scanVM: ScannerViewModel
        @Environment(\.horizontalSizeClass) private var hSize
        let masterList: AnyView
        let detailPane: AnyView
        
        @Binding var liveCrop: CGRect?
        @Binding var liveHighlights: [CGRect]
        @Binding var liveConfs: [Float]
        @Binding var liveScannerCoord: LiveScannerView.Coordinator?
        
        var body: some View {
            Group {
                if hSize == .compact {
                    CompactView(navVM: navVM, scanVM: scanVM, masterList: masterList)
                } else {
                    SplitView(navVM: navVM, scanVM: scanVM, masterList: masterList, detailPane: detailPane)
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
                            numberSystem: $scanVM.storedSystem,
                            onNumbersUpdate: { nums in
                                print("LiveScanner detected: \(nums)")  // Debug
                                scanVM.handleLiveNumbersUpdate(nums)
                            },
                            highlights: $liveHighlights,
                            highlightConfs: $liveConfs,
                            cropRect: $liveCrop,
                            onFixTap: { fix in
                                scanVM.currentFix = fix
                            },
                            onCoordinatorReady: { c in
                                print("LiveScanner coordinator ready")  // Debug
                                liveScannerCoord = c
                            }
                        )
                        .onAppear {
                            print("LiveScanner view appeared")
                        }
                        .overlay(
                            LiveHighlightOverlay(
                                rects: liveHighlights,
                                rectConfs: liveConfs,
                                onTap: { idx in
                                    liveScannerCoord?.requestFix(at: idx)
                                }
                            )
                        )
                        .overlay(
                            LiveOverlayView(numbers: scanVM.liveNumbers)
                                .allowsHitTesting(false)
                        )
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
            // MARK: - Fix-digit sheet
            .sheet(isPresented: $scanVM.isShowingFixSheet) {
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
    }

    // MARK: - Body
    var body: some View {
        Group {
            if !isReady {
                ProgressView()
                    .onAppear {
                        Task {
                            await requestCameraPermission()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isReady = true
                            }
                        }
                    }
            } else {
                MainContentView(
                    navVM: navVM,
                    scanVM: scanVM,
                    masterList: AnyView(masterList),
                    detailPane: AnyView(detailPane),
                    liveCrop: $liveCrop,
                    liveHighlights: $liveHighlights,
                    liveConfs: $liveConfs,
                    liveScannerCoord: $liveScannerCoord
                )
            }
        }
        .overlay {
            ProcessingOverlay(
                progress: scanVM.processingState.progress,
                isVisible: scanVM.processingState.isProcessing
            )
        }
    }

    @MainActor
    private func requestCameraPermission() async {
        print("Checking camera permission...")
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            print("Camera permission not determined, requesting...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            print("Camera permission \(granted ? "granted" : "denied")")
        case .authorized:
            print("Camera permission already granted")
        case .denied:
            print("Camera permission denied")
        case .restricted:
            print("Camera permission restricted")
        @unknown default:
            print("Unknown camera permission status")
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
