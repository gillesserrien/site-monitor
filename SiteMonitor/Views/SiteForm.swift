import SwiftUI

struct SiteForm: View {
    let original: Site?
    let onSave: (Site) -> Void
    let onCancel: () -> Void

    @State private var address: String
    @State private var name: String
    @State private var expectedText: String
    @State private var checksInertiaSSR: Bool
    @State private var showsError = false
    @FocusState private var addressFocused: Bool

    init(original: Site?, onSave: @escaping (Site) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.onSave = onSave
        self.onCancel = onCancel
        _address = State(initialValue: original?.url.absoluteString ?? "")
        _name = State(initialValue: original?.name ?? "")
        _expectedText = State(initialValue: original?.expectedText ?? "")
        _checksInertiaSSR = State(initialValue: original?.checksInertiaSSR ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            field("Website") {
                TextField("example.com", text: $address)
                    .focused($addressFocused)
            }
            field("Name") {
                TextField("Optional, defaults to the domain", text: $name)
            }
            field("Must contain") {
                TextField("Optional text that must be on the page", text: $expectedText)
            }

            Toggle(isOn: $checksInertiaSSR) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Check Inertia SSR")
                    Text("Warns when the page comes back without server-side rendering.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if showsError {
                Text("That doesn't look like a web address.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .onAppear { addressFocused = true }
    }

    private var title: String {
        if let original {
            return "Edit \(original.name)"
        }
        return "Add a site"
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        guard let url = Site.url(from: address) else {
            showsError = true
            return
        }
        var site = original ?? Site(name: "", url: url)
        site.url = url
        site.name = name.trimmingCharacters(in: .whitespaces)
        if site.name.isEmpty { site.name = site.host }
        site.expectedText = expectedText.trimmingCharacters(in: .whitespaces)
        site.checksInertiaSSR = checksInertiaSSR
        onSave(site)
    }
}

#Preview {
    SiteForm(original: nil, onSave: { _ in }, onCancel: {})
        .frame(width: 360)
}
