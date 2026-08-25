import SwiftUI
import AppKit

struct BroadcastView: View {
    @StateObject private var viewModel = BroadcastViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let success = viewModel.lastSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Sent to \(success) users")
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
                .transition(.opacity)
            }

            ScrollView {
                VStack(spacing: 24) {
                    Form {
                        Section("Broadcast Message") {
                            HStack {
                                TextField("Title", text: $viewModel.title)
                                    .textFieldStyle(.roundedBorder)
                                Text("\(viewModel.title.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }

                            ZStack(alignment: .topLeading) {
                                if viewModel.body.isEmpty {
                                    Text("Message body (optional)")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }
                                SpellCheckTextEditor(text: $viewModel.body)
                                    .frame(minHeight: 200)
                                    .frame(maxHeight: .infinity)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(viewModel.body.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .padding(4)
                            }

                            Button {
                                viewModel.showConfirmation = true
                            } label: {
                                if viewModel.isSending {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Sending\u{2026}")
                                } else {
                                    Text("Send to all \(appState.adminStats?.users.total ?? 0) users")
                                }
                            }
                            .disabled(viewModel.isSending || viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .formStyle(.grouped)

                    // Sent History
                    if !viewModel.history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SENT HISTORY")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(viewModel.history) { entry in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                            .font(.subheadline)
                                            .strikethrough(entry.recalled)
                                            .foregroundColor(entry.recalled ? .secondary : .primary)
                                        HStack(spacing: 6) {
                                            Text("\(entry.recipientCount) sent")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let read = entry.readCount, let total = entry.readTotal {
                                                Text("·")
                                                    .font(.caption).foregroundColor(.secondary)
                                                Text("\(read)/\(total) read")
                                                    .font(.caption)
                                                    .foregroundColor(read == total && total > 0 ? .green : .secondary)
                                            }
                                            Text("·")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(entry.sentAt, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if entry.recalled {
                                                Text("· Recalled")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        Task { await viewModel.refreshReceipts(entry) }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    if !entry.recalled {
                                        Button("Recall") {
                                            Task { await viewModel.recall(entry) }
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    }
                                    Button {
                                        viewModel.deleteFromHistory(entry)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(
            "Send broadcast to \(appState.adminStats?.users.total ?? 0) users?",
            isPresented: $viewModel.showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send") { Task { await viewModel.send() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SpellCheckTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckTextEditor
        init(_ parent: SpellCheckTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
