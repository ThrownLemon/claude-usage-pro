import SwiftUI

struct UsageView: View {
    let account: ClaudeAccount
    var onPing: (() -> Void)?
    
    @State private var isHovering = false
    @State private var showStartText = false
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var tierColor: Color {
        let tier = account.usageData?.tier.lowercased() ?? ""
        if tier.contains("max") { return .yellow }
        if tier.contains("team") { return .purple }
        return .blue // Default/Pro
    }
    
    var body: some View {
        Group {
            if let usage = account.usageData {
                HStack(spacing: 16) {
                    // Left: Circular Session Gauge
                    Gauge(value: usage.sessionPercentage) {
                        EmptyView()
                    } currentValueLabel: {
                        if usage.sessionReset == "Ready" {
                            // Interactive Ready State
                            Button(action: { onPing?() }) {
                                Text(showStartText ? "Start" : "Ready")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(showStartText ? .yellow : .green)
                                    .multilineTextAlignment(.center)
                                    .onReceive(timer) { _ in
                                        withAnimation {
                                            showStartText.toggle()
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Standard Timer
                            Text(usage.sessionReset)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Gradient(colors: [.blue, .purple]))
                    .scaleEffect(1.3)
                    .frame(width: 55, height: 55)
                    
                    // Right: Details & Weekly
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(account.name)
                                .font(.system(.headline, design: .rounded))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(usage.tier.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(.caption2, design: .rounded).bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tierColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        // Weekly Linear Gauge
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Weekly Limit")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(usage.weeklyReset)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            
                            Gauge(value: usage.weeklyPercentage) {
                                EmptyView()
                            }
                            .gaugeStyle(.accessoryLinear)
                            .tint(.green)
                            .scaleEffect(y: 0.8)
                        }
                    }
                }
            } else {
                LoadingCardView()
            }
        }
        .padding(12)
        .background(Material.regular)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1) // Subtle border for definition
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2) // Deeper shadow for pop
    }
}

struct LoadingCardView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 55, height: 55)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 120, height: 16)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 60, height: 10)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 6)
                }
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            }
    }
}
