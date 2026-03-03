import SwiftUI

struct TaskListView: View {
    @Bindable var store: TaskStore
    @State private var isAddingTask = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            taskList
            Divider()
            footer
        }
        .frame(width: 320, height: 400)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack {
            Text("Whiplash")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            Spacer()
            if store.activeCount > 0 {
                Text("\(store.activeCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.blue))
            }
            Button(action: { isAddingTask.toggle() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isAddingTask {
                    AddTaskView { title, context in
                        store.addTask(title: title, context: context)
                        isAddingTask = false
                    } onCancel: {
                        isAddingTask = false
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    Divider().padding(.horizontal, 10)
                }

                if store.visibleTasks.isEmpty && !isAddingTask {
                    emptyState
                } else {
                    ForEach(store.visibleTasks) { task in
                        TaskRowView(task: task) { action in
                            handleAction(action, for: task.id)
                        }
                        Divider().padding(.horizontal, 10)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No active tasks")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Click + to add one")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func handleAction(_ action: TaskRowAction, for id: UUID) {
        switch action {
        case .markDone:
            store.markDone(id)
        case .togglePause:
            store.togglePause(id)
        case .dismiss:
            store.dismissTask(id)
        }
    }
}
