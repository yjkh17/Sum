import SwiftUI

struct RootToolbar: ToolbarContent {
    @Binding var showScanner: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showLiveScanner: Bool
    @Binding var numberSystem: NumberSystem
    var onStartLiveScan: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { showScanner = true } label: {
                Label("Scan", systemImage: "camera.viewfinder")
                    .symbolEffect(.bounce, value: showScanner)
            }
            Button { showPhotoPicker = true } label: {
                Label("Photo", systemImage: "photo.on.rectangle")
                    .symbolEffect(.bounce, value: showPhotoPicker)
            }
        }
        
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if #available(iOS 17.0, *) {
                Button {
                    onStartLiveScan()
                    showLiveScanner = true
                } label: {
                    Label("Live", systemImage: "eye")
                        .symbolEffect(.bounce, value: showLiveScanner)
                }
            }
            
            Menu {
                Picker("Digits", selection: $numberSystem) {
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
}