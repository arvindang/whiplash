import SwiftUI

struct AddTaskView: View {
    let onAdd: (String, String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var selectedContext = "iTerm"

    private let contexts = ["iTerm", "Claude Code", "Cowork", "Xcode", "Terminal", "Custom"]
    @State private var customContext = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task name...", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                )

            HStack(spacing: 6) {
                ForEach(contexts, id: \.self) { ctx in
                    contextButton(ctx)
                }
            }

            if selectedContext == "Custom" {
                TextField("Context...", text: $customContext)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                    )
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Add") {
                    let context = selectedContext == "Custom" ? customContext : selectedContext
                    guard !title.isEmpty else { return }
                    onAdd(title, context)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.blue)
                .disabled(title.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func contextButton(_ context: String) -> some View {
        Button(action: { selectedContext = context }) {
            Text(context)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(selectedContext == context ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(selectedContext == context ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.quaternary))
                )
        }
        .buttonStyle(.plain)
    }
}
