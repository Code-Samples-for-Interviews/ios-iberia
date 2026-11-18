import Data
import Domain
import Presentation
import SwiftUI

@main
struct AlbumSearchApp: App {
    @State private var model: SearchViewModel

    init() {
        // The composition root is the only place that knows the concrete repository.
        let repository = ITunesAlbumRepository()
        _model = State(initialValue: SearchViewModel(searchAlbums: SearchAlbums(repository: repository)))
    }

    var body: some Scene {
        WindowGroup {
            AlbumSearchView(model: model)
        }
    }
}

// Accessibility summary:
// - Uses the system scene and delegates accessibility to the two feature views.
// - No forced text size, color scheme, orientation or custom navigation behavior.
// Test: launch with VoiceOver and an accessibility text size enabled; the search control must be reachable.
