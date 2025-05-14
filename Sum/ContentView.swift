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
    @Query private var items: [Item]
    @StateObject private var scannerVM = ScannerViewModel()

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Scan Numbers") {
                        scannerVM.startScan()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Upload Photo") {
                        scannerVM.startPhotoPick()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if #available(iOS 17.0, *) {
                        Button("Live OCR") {
                            scannerVM.startLiveScan()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if scannerVM.numbers.isEmpty {
                Text("Select an item")
                    .foregroundStyle(.secondary)
            } else {
                ResultCardView(sum: scannerVM.sum, numbers: scannerVM.numbers)
            }
        }
        .sheet(isPresented: $scannerVM.isShowingScanner) {
            DocumentScannerView { numbers in
                scannerVM.handleScanCompleted(numbers)
            }
        }
        .fullScreenCover(isPresented: $scannerVM.isShowingPhotoPicker) {
            NavigationStack {                    // gives us a nav-bar if needed
                PhotoPickerView { img in           // now SwiftUI picker
                    scannerVM.handlePickedImage(img)
                }
                .navigationTitle("Choose a Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // In case the user wants to cancel without picking
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            scannerVM.isShowingPhotoPicker = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $scannerVM.isShowingLiveScanner) {
            if #available(iOS 17.0, *) {
                NavigationStack {
                    LiveScannerView { nums in
                        scannerVM.handleLiveNumbers(nums)
                    }
                    .ignoresSafeArea()          // fill entire screen
                    .toolbar {
                        // “Done” button to exit live OCR
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                scannerVM.isShowingLiveScanner = false
                            }
                        }
                    }
                }
            } else {
                Text("Live OCR requires iOS 17 or later.")
            }
        }
        .fullScreenCover(isPresented: $scannerVM.isShowingCropper) {
            if let uiImage = scannerVM.pickedImage {
                // Wrap in NavigationStack so the toolbar (Done/Cancel) is visible
                NavigationStack {
                    ImageCropperView(image: uiImage) { cropImage, obs in
                        scannerVM.handleCroppedNumbers(obs.map(\.value))
                        scannerVM.receiveCroppedResult(image: cropImage,
                                                       observations: obs)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .fullScreenCover(isPresented: $scannerVM.isShowingResult) {
            if let img = scannerVM.croppedImage,
               let obs = scannerVM.croppedObservations {
                CroppedResultView(image: img, observations: obs)
                    .onTapGesture { scannerVM.isShowingResult = false } // tap to dismiss
            }
        }
        .alert("Total", isPresented: $scannerVM.showSumAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scannerVM.lastSum, format: .number)
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
