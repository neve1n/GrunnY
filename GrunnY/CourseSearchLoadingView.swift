import SwiftUI

struct CourseSearchLoadingView: View {
    let progress: String
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 30.0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("달릴 길을\n찾고 있어요.")
                        .font(.system(size: headingSize, weight: .bold))
                        .tracking(-1).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 28)
                    Spacer(minLength: 24)
                    routeIllustration
                        .frame(maxWidth: 270)
                        .frame(height: max(180, min(270, geometry.size.height * 0.35)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    Text(progress)
                        .font(.subheadline)
                        .foregroundStyle(GrunnYStyle.brand)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    Spacer(minLength: 24)

                    Button("탐색 취소", action: cancel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GrunnYStyle.brand)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                }
                .frame(minHeight: max(0, geometry.size.height - 40))
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
            }
        }
        .foregroundStyle(GrunnYStyle.primary)
        .background(GrunnYStyle.background.ignoresSafeArea())
    }

    private var routeIllustration: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let start = reduceMotion ? 0.2 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3) / 3
            let end = start + 0.24
            let stroke = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            ZStack {
                SearchLoopShape()
                    .stroke(GrunnYStyle.teal.opacity(0.16), style: stroke)
                SearchLoopShape().trim(from: start, to: min(end, 1))
                    .stroke(GrunnYStyle.brand, style: stroke)
                if end > 1 {
                    SearchLoopShape().trim(from: 0, to: end - 1)
                        .stroke(GrunnYStyle.brand, style: stroke)
                }
            }
            .padding(12)
        }
        .accessibilityHidden(true)
    }
}

private struct SearchLoopShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.22, 0.13))
        path.addCurve(to: point(0.62, 0.29), control1: point(0.41, -0.03), control2: point(0.58, 0.07))
        path.addCurve(to: point(0.82, 0.60), control1: point(0.67, 0.51), control2: point(0.68, 0.49))
        path.addCurve(to: point(0.75, 0.94), control1: point(1.06, 0.76), control2: point(0.87, 0.93))
        path.addCurve(to: point(0.37, 0.76), control1: point(0.52, 1.02), control2: point(0.45, 0.89))
        path.addCurve(to: point(0.12, 0.55), control1: point(0.26, 0.58), control2: point(0.14, 0.68))
        path.addCurve(to: point(0.22, 0.13), control1: point(0.02, 0.44), control2: point(0.13, 0.23))
        path.closeSubpath()
        return path
    }
}
