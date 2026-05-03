import SwiftUI

struct MoveGlyphView: View {
    let kind: Move.MoveKind
    let side: Move.MoveSide
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 36.0
            context.concatenate(CGAffineTransform(scaleX: s, y: s))
            let stroke = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            let thin   = StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)

            switch kind {
            case .jab:
                context.stroke(Path(ellipseIn: CGRect(x: 4, y: 13, width: 10, height: 10)),
                                with: .color(color), style: thin)
                var line = Path()
                line.move(to: .init(x: 14, y: 18))
                line.addLine(to: .init(x: 29, y: 18))
                context.stroke(line, with: .color(color), style: stroke)
                var arrow = Path()
                arrow.move(to: .init(x: 25, y: 14))
                arrow.addLine(to: .init(x: 29, y: 18))
                arrow.addLine(to: .init(x: 25, y: 22))
                context.stroke(arrow, with: .color(color), style: stroke)

            case .hook:
                context.stroke(Path(ellipseIn: CGRect(x: 4, y: 4, width: 10, height: 10)),
                                with: .color(color), style: thin)
                var curve = Path()
                curve.move(to: .init(x: 14, y: 9))
                curve.addQuadCurve(to: .init(x: 26, y: 21), control: .init(x: 26, y: 9))
                curve.addLine(to: .init(x: 26, y: 28))
                context.stroke(curve, with: .color(color), style: stroke)
                var arrow = Path()
                arrow.move(to: .init(x: 22, y: 24))
                arrow.addLine(to: .init(x: 26, y: 28))
                arrow.addLine(to: .init(x: 30, y: 24))
                context.stroke(arrow, with: .color(color), style: stroke)

            case .uppercut:
                context.stroke(Path(ellipseIn: CGRect(x: 4, y: 23, width: 10, height: 10)),
                                with: .color(color), style: thin)
                var curve = Path()
                curve.move(to: .init(x: 14, y: 28))
                curve.addQuadCurve(to: .init(x: 22, y: 18), control: .init(x: 22, y: 28))
                curve.addLine(to: .init(x: 22, y: 7))
                context.stroke(curve, with: .color(color), style: stroke)
                var arrow = Path()
                arrow.move(to: .init(x: 18, y: 11))
                arrow.addLine(to: .init(x: 22, y: 7))
                arrow.addLine(to: .init(x: 26, y: 11))
                context.stroke(arrow, with: .color(color), style: stroke)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: side == .right ? -1 : 1, y: 1)
    }
}
