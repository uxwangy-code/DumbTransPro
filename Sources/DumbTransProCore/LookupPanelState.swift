import Foundation

@MainActor
final class LookupPanelState: ObservableObject {
    @Published var originalText: String
    @Published var translation: String = ""
    @Published var isLoading: Bool = true
    @Published var isSlowLoading: Bool = false
    @Published var didFallback: Bool = false
    @Published var error: String? = nil
    @Published var modelName: String
    @Published var isOriginalExpanded: Bool = false

    var onClose: (() -> Void)?

    init(originalText: String, modelName: String) {
        self.originalText = originalText
        self.modelName = modelName
    }
}
