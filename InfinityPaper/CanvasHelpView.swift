import SwiftUI

struct CanvasQuickHelpView: View {
    let pencilOnly: Bool
    let onLearnMore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(pencilOnly ? "first_use.pencil_lead" : "first_use.lead"))
                    .font(.footnote.weight(.medium))
                Text(LocalizedStringKey(pencilOnly ? "first_use.pencil_body" : "first_use.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("first_use.learn_more", action: onLearnMore)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("first_use.dismiss"))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct CanvasHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.pencilOnly) private var pencilOnly = false

    private var supportsPencil: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var pencilOnlyMode: Bool {
        CanvasInputPolicy.pencilOnly(requested: pencilOnly, supportsPencil: supportsPencil)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LocalizedStringKey(pencilOnlyMode ? "help.pencil.body" : "help.drawing.body"))
                    Text("help.movement.body")
                } header: { Text("help.drawing.title") }
                helpSection("help.tools.title", body: "help.tools.body")
                helpSection("help.selection.title", body: "help.selection.body")
                helpSection("help.reference.title", body: "help.reference.body")
                helpSection("help.library.title", body: "help.library.body")
                if supportsPencil {
                    helpSection("help.pencil.title", body: "help.pencil.settings_body")
                }
                helpSection("help.focus.title", body: "help.focus.body")
            }
            .navigationTitle(Text("help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
    }

    private func helpSection(_ title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        Section { Text(body) } header: { Text(title) }
    }
}
