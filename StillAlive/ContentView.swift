import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: AliveManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSettings = false
    @State private var showContact = false
    @AppStorage("appAppearance") var appAppearance: Int = 0

    @State private var showToast = false
    @State private var pulse = false
    @State private var appear = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let scale = calculateScale(size: geo.size)
                
                ZStack {
                    // MARK: - Liquid Background
                    LiquidBackground(status: manager.status)
                        .ignoresSafeArea()
                    
                    // MARK: - Noise Texture Overlay
                    NoiseTexture()
                        .opacity(colorScheme == .dark ? 0.12 : 0.05)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 30 * scale) {
                        Spacer()
                        
                        // MARK: - Main Glass Card
                        VStack(spacing: 20 * scale) {
                            HStack {
                                Spacer()
                                Text(statusTitle)
                                    .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                                    .foregroundColor(statusColor.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            
                            Text(timeString(from: manager.timeRemaining))
                                .font(.system(size: 84 * scale, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.4)
                                .foregroundColor(.primary)
                                .shadow(color: Color.primary.opacity(0.2), radius: 15, x: 0, y: 15)
                        }
                        .padding(.vertical, 50 * scale)
                        .padding(.horizontal, 20 * scale)
                        .frame(maxWidth: .infinity)
                        .background {
                            ZStack {
                                // Background Glow
                                RoundedRectangle(cornerRadius: 48 * scale, style: .continuous)
                                    .fill(statusColor.opacity(0.12))
                                    .blur(radius: pulse ? 40 : 20)
                                    .scaleEffect(pulse ? 1.02 : 0.98)
                                
                                // Main Frosted Glass
                                RoundedRectangle(cornerRadius: 48 * scale, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                
                                // Color Vibrancy Tint
                                RoundedRectangle(cornerRadius: 48 * scale, style: .continuous)
                                    .fill(statusColor.opacity(0.08))
                                
                                // Edge Highlight
                                RoundedRectangle(cornerRadius: 48 * scale, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.6),
                                                .white.opacity(0.1),
                                                .clear,
                                                .white.opacity(0.1),
                                                .white.opacity(0.4)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            }
                        }
                        .shadow(color: Color.primary.opacity(0.1), radius: 40, x: 0, y: 30)
                        .padding(.horizontal, 25)
                        .opacity(appear ? 1 : 0) // Keep fade-in only, no motion
                        
                        Spacer()
                        
                        // MARK: - Liquid Action Button
                        Button(action: {
                            triggerCheckIn()
                        }) {
                            ZStack {
                                // Breath/Pulse effect
                                Circle()
                                    .fill(statusColor.opacity(0.25))
                                    .frame(width: 320 * scale, height: 320 * scale) // Increased spread size
                                    .scaleEffect(pulse ? 1.15 : 1.0)
                                    .blur(radius: pulse ? 45 : 30) // Significantly increased blur for "Mist" effect
                                
                                // Outer Glass Ring
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 200 * scale, height: 200 * scale)
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.4), lineWidth: 1)
                                    }
                                
                                // Inner Liquid Core
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [statusColor, statusColor.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 170 * scale, height: 170 * scale)
                                    .shadow(color: statusColor.opacity(0.4), radius: 45, x: 0, y: 20) // Increased shadow radius for larger diffusion
                                    .overlay {
                                        // Highlight on the core
                                        Circle()
                                            .stroke(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 2)
                                            .padding(2)
                                    }
                                
                                VStack(spacing: 8 * scale) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 44 * scale, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 5)
                                    
                                    Text("I'm OK")
                                        .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                                        .tracking(2)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .opacity(appear ? 1 : 0)
                        
                        Spacer()
                        
                        // MARK: - Bottom Info
                        VStack(spacing: 8 * scale) {
                            Text("Last_Verification")
                                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                                .tracking(2)
                                .foregroundColor(.primary.opacity(0.4))
                            
                            Text(manager.lastCheckInDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                        .padding(.bottom, 15)
                        .opacity(appear ? 1 : 0)
                    }
                    .frame(width: geo.size.width, height: geo.size.height) // Lock content to exact center of screen
                    
                    // MARK: - Toast Overlay
                    if showToast || manager.syncStatus != .idle {
                        ToastView(syncStatus: manager.syncStatus)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            .zIndex(2)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("App_Title")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundColor(.primary)
                        .opacity(0.9)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showContact = true }) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView(manager: manager)
            }
            .sheet(isPresented: $showContact) {
                ContactView(manager: manager)
            }
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    appear = true
                }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .preferredColorScheme(appAppearance == 0 ? nil : (appAppearance == 1 ? .light : .dark))
    }
    
    // MARK: - Actions
    
    private func triggerCheckIn() {
        let impact = UIImpactFeedbackGenerator(style: .rigid)
        impact.prepare()
        impact.impactOccurred()
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            manager.checkIn()
            
            showToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeIn(duration: 0.4)) {
                    showToast = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    func calculateScale(size: CGSize) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return min(size.width, size.height) / 480.0
        }
        return 1.0
    }
    
    var statusTitle: LocalizedStringKey {
        switch manager.status {
        case .safe: return "Status_Active"
        case .warning: return "Status_Required"
        case .danger: return "Status_Alert"
        }
    }
    
    var statusColor: Color {
        if colorScheme == .dark {
            switch manager.status {
            case .safe: return Color(hex: "00F260")
            case .warning: return Color(hex: "FFB347")
            case .danger: return Color(hex: "FF4B2B")
            }
        } else {
            switch manager.status {
            case .safe: return Color(hex: "1D976C") // Deep Emerald for readability
            case .warning: return Color(hex: "E67E22") // Sophisticated Orange
            case .danger: return Color(hex: "C0392B") // Rich Red
            }
        }
    }
    
    func timeString(from timeInterval: TimeInterval) -> String {
        if timeInterval <= 0 { return "00:00:00" }
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Subviews

struct LiquidBackground: View {
    let status: AliveManager.AliveStatus
    @Environment(\.colorScheme) var colorScheme
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Main Base Color
            bgColor.ignoresSafeArea()
            
            // Animated Blobs
            Canvas { context, size in
                context.addFilter(.alphaThreshold(min: 0.5, color: bgColor))
                context.addFilter(.blur(radius: 40))
                
                context.drawLayer { ctx in
                    for index in 0..<3 {
                        let rect = rect(for: index, in: size)
                        ctx.fill(Circle().path(in: rect), with: .color(blobColor(for: index)))
                    }
                }
            }
        }
        .animation(.spring(), value: status)
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
    
    func rect(for index: Int, in size: CGSize) -> CGRect {
        let width = size.width * 0.8
        let height = width
        
        var x = size.width / 2 - width / 2
        var y = size.height / 2 - height / 2
        
        switch index {
        case 0:
            x += animate ? 120 : -100
            y += animate ? -180 : 100
        case 1:
            x += animate ? -150 : 150
            y += animate ? 200 : -150
        case 2:
            x += animate ? 80 : -120
            y += animate ? 150 : 250
        default:
            break
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    var bgColor: Color {
        if colorScheme == .dark {
            switch status {
            case .safe: return Color(hex: "0F2027") // Deep Night Blue
            case .warning: return Color(hex: "1F1405") // Deep Amber Black
            case .danger: return Color(hex: "1A0505") // Deep Crimson Black
            }
        } else {
            switch status {
            case .safe: return Color(hex: "F0F9FF") // Very Light Blue
            case .warning: return Color(hex: "FFF7ED") // Very Light Amber
            case .danger: return Color(hex: "FEF2F2") // Very Light Red
            }
        }
    }
    
    func blobColor(for index: Int) -> Color {
        if colorScheme == .dark {
            switch status {
            case .safe:
                return index == 0 ? Color(hex: "2193b0") : (index == 1 ? Color(hex: "6dd5ed") : Color(hex: "00F260"))
            case .warning:
                return index == 0 ? Color(hex: "FFB347") : (index == 1 ? Color(hex: "F2994A") : Color(hex: "EB5757"))
            case .danger:
                return index == 0 ? Color(hex: "FF4B2B") : (index == 1 ? Color(hex: "8E0E00") : Color(hex: "4b1212"))
            }
        } else {
            switch status {
            case .safe:
                return index == 0 ? Color(hex: "D1FAE5") : (index == 1 ? Color(hex: "A7F3D0") : Color(hex: "6EE7B7"))
            case .warning:
                return index == 0 ? Color(hex: "FFEDD5") : (index == 1 ? Color(hex: "FED7AA") : Color(hex: "FDBA74"))
            case .danger:
                return index == 0 ? Color(hex: "FEE2E2") : (index == 1 ? Color(hex: "FECACA") : Color(hex: "FCA5A5"))
            }
        }
    }
}

struct NoiseTexture: View {
    var body: some View {
        // Optimized noise using a tiled pattern to reduce Canvas calculation load
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                Canvas { context, size in
                    // Draw a sparse noise pattern that is static
                    // Using a seed for stability if needed, but here we just draw once
                    for _ in 0..<Int(size.width * size.height / 30) {
                        let x = Double.random(in: 0...size.width)
                        let y = Double.random(in: 0...size.height)
                        let opacity = Double.random(in: 0.1...0.3)
                        context.opacity = opacity
                        context.fill(Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white))
                    }
                }
            }
            .drawingGroup() // Flattens the view into a single offscreen buffer
    }
}

struct ToastView: View {
    let syncStatus: AliveManager.SyncStatus
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor)
                        .frame(width: 24, height: 24)
                    
                    if syncStatus == .syncing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                    }
                }
                
                Text(message)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .shadow(color: Color.primary.opacity(0.1), radius: 20, x: 0, y: 10)
            .padding(.top, 2)
            
            Spacer()
        }
    }
    
    private var iconName: String {
        switch syncStatus {
        case .success: return "checkmark"
        case .idle: return "checkmark"
        case .failed: return "xmark"
        case .syncing: return "circle"
        case .noEmail: return "exclamationmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch syncStatus {
        case .success: return .green
        case .idle: return .green
        case .failed: return .red
        case .syncing: return .blue
        case .noEmail: return .orange
        }
    }
    
    private var message: LocalizedStringKey {
        switch syncStatus {
        case .success: return "Verification_Success"
        case .idle: return "Verification_Success"
        case .syncing: return "Sync_Status_Syncing"
        case .failed: return "Sync_Status_Failed"
        case .noEmail: return "Sync_Status_NoEmail"
        }
    }
}

// MARK: - Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AliveManager())
}
