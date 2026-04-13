import SwiftUI

/// Animated grass island with one sprite per active Claude Code session.
struct AgentSpriteView: View {
    @ObservedObject var store: ClaudeSessionStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawGround(context: context, size: size)
                drawSprites(context: context, size: size, time: t)
            }
        }
        .frame(height: 55)
    }

    // MARK: - Ground

    private func drawGround(context: GraphicsContext, size: CGSize) {
        let groundHeight: CGFloat = 14
        let groundY = size.height - groundHeight
        let groundRect = CGRect(x: 8, y: groundY, width: size.width - 16, height: groundHeight)
        let roundedPath = RoundedRectangle(cornerRadius: 7).path(in: groundRect)

        // Green gradient ground
        context.fill(
            roundedPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.25, green: 0.55, blue: 0.20),
                    Color(red: 0.20, green: 0.45, blue: 0.15),
                ]),
                startPoint: CGPoint(x: size.width / 2, y: groundY),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )

        // Grass tufts
        let tufts = [0.15, 0.3, 0.5, 0.7, 0.85]
        for pct in tufts {
            let cx = 8 + (size.width - 16) * pct
            drawTuft(context: context, x: cx, y: groundY)
        }
    }

    private func drawTuft(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        var path = Path()
        let h: CGFloat = 5
        // Left blade
        path.move(to: CGPoint(x: x - 3, y: y))
        path.addQuadCurve(
            to: CGPoint(x: x - 1, y: y - h),
            control: CGPoint(x: x - 4, y: y - h * 0.6)
        )
        // Center blade
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: y - h - 1))
        // Right blade
        path.move(to: CGPoint(x: x + 3, y: y))
        path.addQuadCurve(
            to: CGPoint(x: x + 1, y: y - h),
            control: CGPoint(x: x + 4, y: y - h * 0.6)
        )

        context.stroke(
            path,
            with: .color(Color(red: 0.3, green: 0.6, blue: 0.25)),
            lineWidth: 1.2
        )
    }

    // MARK: - Sprites

    private func drawSprites(context: GraphicsContext, size: CGSize, time: Double) {
        let sessions = store.activeSessions
        guard !sessions.isEmpty else { return }

        let groundY = size.height - 14
        let usableWidth = size.width - 32
        let spacing = sessions.count == 1 ? 0 : usableWidth / CGFloat(sessions.count - 1)

        for (index, session) in sessions.enumerated() {
            let baseX: CGFloat
            if sessions.count == 1 {
                baseX = size.width / 2
            } else {
                baseX = 16 + spacing * CGFloat(index)
            }
            let baseY = groundY - 4

            drawSprite(
                context: context,
                session: session,
                x: baseX,
                y: baseY,
                time: time
            )
        }
    }

    private func drawSprite(
        context: GraphicsContext,
        session: ClaudeSession,
        x: CGFloat,
        y: CGFloat,
        time: Double
    ) {
        let state = session.spriteState
        let symbolName = symbolForState(state)
        let color = colorForState(state)

        // Animation offsets
        var offsetY: CGFloat = 0
        var scale: CGFloat = 1.0
        var opacity: Double = 1.0

        switch state {
        case .idle:
            // Gentle bobbing
            offsetY = CGFloat(sin(time * 2.0)) * 2.0
        case .working:
            // Rapid bouncing
            offsetY = CGFloat(abs(sin(time * 5.0))) * -6.0
        case .sleeping:
            // Lowered, slight fade
            offsetY = 3.0
            opacity = 0.6
        case .compacting:
            // Pulsing scale
            scale = 1.0 + CGFloat(sin(time * 4.0)) * 0.15
        case .needsPermission:
            // Pulsing with attention
            scale = 1.0 + CGFloat(sin(time * 3.0)) * 0.1
        }

        let spriteY = y + offsetY - 16

        // Draw sprite symbol
        var spriteContext = context
        spriteContext.opacity = opacity
        spriteContext.translateBy(x: x, y: spriteY)
        spriteContext.scaleBy(x: scale, y: scale)

        let symbol = Image(systemName: symbolName)
        let fontSize: CGFloat = 18
        let resolved = spriteContext.resolve(
            Text(symbol).font(.system(size: fontSize, weight: .medium))
                .foregroundColor(color)
        )
        spriteContext.draw(
            resolved,
            at: .zero,
            anchor: .center
        )

        // Reset transform for subsequent draws
        spriteContext.scaleBy(x: 1.0 / scale, y: 1.0 / scale)
        spriteContext.translateBy(x: -x, y: -spriteY)

        // Working state: sparkle particles
        if state == .working {
            drawSparkles(context: &spriteContext, x: x, y: spriteY, time: time)
        }

        // Sleeping state: z's
        if state == .sleeping {
            drawZzz(context: &spriteContext, x: x, y: spriteY, time: time)
        }

        // Needs permission: pulsing ring
        if state == .needsPermission {
            let ringRadius = 12.0 + CGFloat(sin(time * 3.0)) * 3.0
            let ring = Circle().path(in: CGRect(
                x: x - ringRadius, y: spriteY - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
            var ringCtx = context
            ringCtx.opacity = 0.3 + sin(time * 3.0) * 0.2
            ringCtx.stroke(ring, with: .color(.orange), lineWidth: 1.5)
        }

        // Tool label
        if let tool = session.lastTool, (state == .working) {
            let label = spriteContext.resolve(
                Text(abbreviateTool(tool))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            )
            spriteContext.draw(label, at: CGPoint(x: x, y: y + 6), anchor: .center)
        }
    }

    // MARK: - Particles

    private func drawSparkles(context: inout GraphicsContext, x: CGFloat, y: CGFloat, time: Double) {
        for i in 0..<3 {
            let angle = time * 3.0 + Double(i) * 2.094 // 120 degrees apart
            let radius: CGFloat = 8.0 + CGFloat(sin(time * 2.0 + Double(i))) * 3.0
            let px = x + CGFloat(cos(angle)) * radius
            let py = y + CGFloat(sin(angle)) * radius - 4
            let sparkle = Circle().path(in: CGRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3))
            let sparkleOpacity = 0.4 + sin(time * 4.0 + Double(i)) * 0.3
            var sCtx = context
            sCtx.opacity = sparkleOpacity
            sCtx.fill(sparkle, with: .color(.cyan))
        }
    }

    private func drawZzz(context: inout GraphicsContext, x: CGFloat, y: CGFloat, time: Double) {
        let phase = time.truncatingRemainder(dividingBy: 3.0) / 3.0
        for i in 0..<2 {
            let p = (phase + Double(i) * 0.4).truncatingRemainder(dividingBy: 1.0)
            let zx = x + 8 + CGFloat(p) * 6
            let zy = y - CGFloat(p) * 12
            let zOpacity = 1.0 - p
            let z = context.resolve(
                Text("z").font(.system(size: 6 + CGFloat(p) * 3, weight: .bold))
                    .foregroundColor(.secondary)
            )
            var zCtx = context
            zCtx.opacity = zOpacity * 0.6
            zCtx.draw(z, at: CGPoint(x: zx, y: zy), anchor: .center)
        }
    }

    // MARK: - Helpers

    private func symbolForState(_ state: SpriteState) -> String {
        switch state {
        case .idle: return "figure.stand"
        case .working: return "figure.run"
        case .sleeping: return "moon.zzz"
        case .compacting: return "arrow.triangle.2.circlepath"
        case .needsPermission: return "exclamationmark.triangle"
        }
    }

    private func colorForState(_ state: SpriteState) -> Color {
        switch state {
        case .idle: return .secondary
        case .working: return .cyan
        case .sleeping: return .indigo
        case .compacting: return .purple
        case .needsPermission: return .orange
        }
    }

    private func abbreviateTool(_ tool: String) -> String {
        // Show last component if it's a path-like name, otherwise truncate
        let name = tool.split(separator: "_").last.map(String.init) ?? tool
        return String(name.prefix(8))
    }
}
