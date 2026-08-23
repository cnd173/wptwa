import SwiftUI

/// Port of MonitorWindow in main.py: ping graph + avg/max/loss, and WPT/self CPU-RAM stats.
struct MonitorView: View {
    private let monitor = PingMonitor()
    @State private var pings: [Int] = []
    @State private var serverLabel = t("monitor_detecting")
    @State private var pingText = t("ping_placeholder")
    @State private var pingColor: Color = Palette.text
    @State private var avgText = t("avg_placeholder")
    @State private var maxText = t("max_placeholder")
    @State private var lossText = t("loss_placeholder")
    @State private var wptCPU = "—"
    @State private var wptRAM = "—"
    @State private var appCPU = "—"
    @State private var appRAM = "—"
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .background(Palette.bg)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private var header: some View {
        HStack {
            Text(t("monitor_title")).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text)
            Spacer()
            Text(serverLabel).font(.system(size: 8)).foregroundColor(Palette.dim)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Palette.surface)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("monitor_network")).font(.system(size: 7, weight: .bold)).foregroundColor(Palette.dim)

            PingGraphView(pings: pings)
                .frame(width: 280, height: 80)
                .background(Palette.bg)
                .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))

            HStack(alignment: .top, spacing: 16) {
                Text(pingText).font(.system(size: 22, weight: .bold)).foregroundColor(pingColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(avgText).font(.system(size: 8)).foregroundColor(Palette.dim)
                    Text(maxText).font(.system(size: 8)).foregroundColor(Palette.dim)
                    Text(lossText).font(.system(size: 8)).foregroundColor(Palette.dim)
                }
            }

            Rectangle().fill(Palette.border).frame(height: 1)
            Text(t("monitor_processes")).font(.system(size: 7, weight: .bold)).foregroundColor(Palette.dim)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    Text(t("col_cpu")).font(.system(size: 8, weight: .bold)).foregroundColor(Palette.dim)
                    Text(t("col_ram")).font(.system(size: 8, weight: .bold)).foregroundColor(Palette.dim)
                }
                GridRow {
                    Text(t("proc_wpt")).font(.system(size: 9)).foregroundColor(Palette.accent)
                    Text(wptCPU).font(.system(size: 9)).foregroundColor(Palette.text)
                    Text(wptRAM).font(.system(size: 9)).foregroundColor(Palette.text)
                }
                GridRow {
                    Text(t("proc_app")).font(.system(size: 9)).foregroundColor(Palette.green)
                    Text(appCPU).font(.system(size: 9)).foregroundColor(Palette.text)
                    Text(appRAM).font(.system(size: 9)).foregroundColor(Palette.text)
                }
            }
        }
        .padding(16)
    }

    private func start() {
        monitor.detectServer { host in
            serverLabel = t("monitor_pinging", ["target": host])
        }
        tick()
        let tmr = Timer(timeInterval: 2.0, repeats: true) { _ in tick() }
        RunLoop.main.add(tmr, forMode: .common)
        timer = tmr
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        DispatchQueue.global(qos: .utility).async {
            let ping = monitor.pingOnce()
            let wpt = ProcessStats.wptStats()
            let own = ProcessStats.ownStats()
            let history = monitor.pings
            let loss = monitor.loss
            let total = monitor.total
            DispatchQueue.main.async {
                apply(ping: ping, history: history, loss: loss, total: total, wpt: wpt, own: own)
            }
        }
    }

    private func apply(ping: Int?, history: [Int], loss: Int, total: Int,
                        wpt: (cpu: Double, ramMB: Int)?, own: (cpu: Double, ramMB: Int)) {
        pings = history
        if let ping {
            pingColor = ping < 50 ? Palette.green : (ping < 100 ? Palette.yellow : Palette.red)
            pingText = "\(ping) ms"
        } else {
            pingColor = Palette.red
            pingText = t("ping_timeout")
        }
        if !history.isEmpty {
            let avg = history.reduce(0, +) / history.count
            avgText = t("avg_ms", ["v": avg])
            maxText = t("max_ms", ["v": history.max() ?? 0])
        }
        let lossPct = total > 0 ? Int(Double(loss) / Double(total) * 100) : 0
        lossText = t("loss_pct", ["pct": lossPct, "loss": loss, "total": total])

        if let wpt {
            wptCPU = String(format: "%.1f%%", wpt.cpu)
            wptRAM = "\(wpt.ramMB) MB"
        } else {
            wptCPU = "—"
            wptRAM = "—"
        }
        appCPU = String(format: "%.1f%%", own.cpu)
        appRAM = "\(own.ramMB) MB"
    }
}

private struct PingGraphView: View {
    let pings: [Int]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
            guard pings.count >= 2 else {
                context.draw(Text(t("graph_collecting")).font(.system(size: 9)).foregroundColor(Palette.dim),
                              at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            let peak = max(pings.max() ?? 1, 1)
            func y(_ ms: Int) -> CGFloat { size.height - max(2, CGFloat(ms) / CGFloat(peak) * (size.height - 4)) }

            for (ref, label) in [(50, "50ms"), (100, "100ms")] where peak > ref {
                let yy = y(ref)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: yy))
                path.addLine(to: CGPoint(x: size.width, y: yy))
                context.stroke(path, with: .color(Palette.border), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                context.draw(Text(label).font(.system(size: 6)).foregroundColor(Palette.dim),
                              at: CGPoint(x: size.width - 2, y: yy - 6), anchor: .trailing)
            }

            let step = size.width / CGFloat(max(PingMonitor.historyLimit - 1, 1))
            let offset = PingMonitor.historyLimit - pings.count
            let points = pings.enumerated().map { i, p in CGPoint(x: CGFloat(i + offset) * step, y: y(p)) }

            let lastColor = pings.last! < 50 ? Palette.green : (pings.last! < 100 ? Palette.yellow : Palette.red)
            if points.count >= 2 {
                var linePath = Path()
                linePath.addLines(points)
                context.stroke(linePath, with: .color(lastColor), lineWidth: 1)
            }
            if let last = points.last {
                let r: CGFloat = 3
                context.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)),
                             with: .color(lastColor))
            }
        }
    }
}
