//
//  ContentView.swift
//  Sum
//
//  Created by Yousef Jawdat on 13/05/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ScanRecord]
    @StateObject private var scanVM = ScannerViewModel()
    @StateObject private var navVM  = NavigationViewModel()
    /// iPhone = .compact  /  iPad = .regular
    @Environment(\.horizontalSizeClass) private var hSize

    // MARK: - Re-usable toolbar
    @ToolbarContentBuilder
    private var toolBarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Scan Numbers") { navVM.isShowingScanner = true }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Upload Photo") { navVM.isShowingPhotoPicker = true }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            if #available(iOS 17.0, *) {
                Button("Live OCR") { scanVM.startLiveScan(); navVM.isShowingLiveScanner = true }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Number System", selection: $scanVM.storedSystem) {
                    Text("Western 0-9").tag(NumberSystem.western)
                    Text("Eastern ٠-٩").tag(NumberSystem.eastern)
                }
            } label: {
                Label("Digits", systemImage: "textformat.123")
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
        .toolbar { toolBarContent }
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
                .toolbar {
                    // In case the user wants to cancel without picking
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            navVM.isShowingPhotoPicker = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $navVM.isShowingLiveScanner) {
            if #available(iOS 17.0, *) {
                NavigationStack {
                    LiveScannerView { nums in
                        scanVM.handleLiveNumbers(nums)
                    }
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
