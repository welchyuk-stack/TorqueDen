import SwiftUI

struct UsageRowView: View {
    let label: String
    let fraction: Double?
    let detail: String
    let remaining: String

    init(label: String, currentBytes: Int?, limitBytes: Int) {
        self.label = label
        if let current = currentBytes, limitBytes > 0 {
            fraction = Double(current) / Double(limitBytes)
            detail = "\(ByteFormatter.string(fromBytes: current)) / \(ByteFormatter.string(fromBytes: limitBytes))"
            let remaining = max(0, limitBytes - current)
            self.remaining = "\(ByteFormatter.string(fromBytes: remaining)) remaining"
        } else {
            fraction = nil
            detail = currentBytes == nil ? "No data" : "N/A"
            remaining = ""
        }
    }

    init(label: String, current: Int?, limit: Int) {
        self.label = label
        if let current, limit > 0 {
            fraction = Double(current) / Double(limit)
            detail = "\(current) / \(limit)"
            remaining = "\(max(0, limit - current)) remaining"
        } else {
            fraction = nil
            detail = current == nil ? "No data" : "N/A"
            remaining = ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
            HStack {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let fraction {
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                            .frame(height: 7)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(fillColor(for: fraction))
                            .frame(width: geo.size.width * min(fraction, 1), height: 7)
                            .animation(.easeOut(duration: 0.3), value: fraction)
                    }
                }
                .frame(height: 7)
                Text(remaining)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func fillColor(for fraction: Double) -> Color {
        if fraction >= 0.9 { return .red }
        if fraction >= 0.7 { return .yellow }
        return .ember
    }
}
