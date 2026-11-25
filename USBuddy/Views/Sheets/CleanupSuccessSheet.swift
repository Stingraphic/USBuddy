import SwiftUI

struct CleanupSuccessSheet: View {
    let summary: CleanupSummary
    let onDismiss: () -> Void
    @State private var didAppear = false

    var body: some View {
        ZStack {
            MeshGlassBackground()

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }

                VStack(spacing: 4) {
                    Text("清理完成")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(summary.actionTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 16,
                                endRadius: 82
                            )
                        )
                        .frame(width: 156, height: 156)
                        .glassEffect(.regular, in: .circle)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 76, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .symbolEffect(.bounce, value: didAppear)
                }
                .onAppear {
                    didAppear = true
                }

                HStack(spacing: 12) {
                    statCard(title: "已清理文件", value: "\(summary.deletedCount) 个")
                    statCard(title: "释放空间", value: summary.formattedFreedSize)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Text("太棒了")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white, in: Capsule())
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(470), .large])
        .presentationCornerRadius(32)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
