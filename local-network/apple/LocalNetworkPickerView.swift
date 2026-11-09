import SwiftUI

// The list of the picker: the services that the browser finds, which update while it shows, a line while one resolves or when the search waits, and Cancel. A tap on a service resolves it.
struct LocalNetworkPickerView: View {
    @ObservedObject var browser: LocalNetworkBrowser

    let picked: @MainActor (LocalNetworkBrowser.Service) -> Void
    let cancelled: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(browser.services) { service in
                        Button(service.name) {
                            picked(service)
                        }
                        .disabled(browser.resolving != nil)
                    }
                } footer: {
                    Text(status)
                }
            }
            .navigationTitle("Services on the local network")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancelled)
                }
            }
        }
    }

    private var status: String {
        if let name = browser.resolving {
            return "Connecting to \"\(name)\"."
        }
        if let problem = browser.problem {
            return problem
        }
        return browser.services.isEmpty ? "Looking for services of the type \"\(browser.type)\"." : "Pick a service of the type \"\(browser.type)\"."
    }
}
