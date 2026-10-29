import SwiftUI

struct OutingView: View {
    @ObservedObject var manager: AliveManager
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("hapticsEnabled") var hapticsEnabled = true
    // Length of the current guard window, used to draw the remaining-time ring
    @AppStorage("outingTotalSeconds") private var outingTotalSeconds: Double = 0

    @State private var durationMinutes = 120
    @State private var activity: OutingActivity?
    @State private var note = ""
    @State private var isWorking = false
    @State private var feedbackCount = 0
    @State private var dialTick = 0
    @State private var holdProgress: CGFloat = 0
    @State private var pulse = false
    @State private var alertMessage: LocalizedStringKey?
    @State private var toastMessage: LocalizedStringKey?
    @State private var toastDismissTask: Task<Void, Never>?
    @FocusState private var noteFocused: Bool

    #if DEBUG
    private let minMinutes = 10
    #else
    private let minMinutes = 15
    #endif
    private let maxMinutes = 720
    private let holdDuration = 1.2

    private var hasContact: Bool {
        !trimmedContact.isEmpty
    }

    private var trimmedContact: String {
        manager.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(status: backgroundStatus)
                    .ignoresSafeArea()

                NoiseTexture()
                    .opacity(colorScheme == .dark ? 0.12 : 0.05)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        if manager.isOutingActive {
                            activeContent
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            setupContent
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: manager.isOutingActive)
                }
                .scrollDismissesKeyboard(.interactively)

                if let toastMessage {
                    OutingToast(message: toastMessage)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                        .zIndex(2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Outing_Title")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundColor(.primary)
                        .opacity(0.9)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFocused = false }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .disabled(isWorking)
            .sensoryFeedback(trigger: feedbackCount) { _, _ in
                hapticsEnabled ? .success : nil
            }
            .sensoryFeedback(trigger: dialTick) { _, _ in
                hapticsEnabled ? .selection : nil
            }
            .alert(
                Text("Outing_Title"),
                isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                if let alertMessage {
                    Text(alertMessage)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    // MARK: - Not Started

    @ViewBuilder
    private var setupContent: some View {
        activityPicker

        dial

        noteCard

        VStack(spacing: 14) {
            tips
            startButton
        }
    }

    private var activityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(OutingActivity.all) { item in
                    let selected = activity == item
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            if selected {
                                activity = nil
                            } else {
                                activity = item
                                durationMinutes = item.minutes
                            }
                        }
                        dialTick += 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                            Text(LocalizedStringKey(item.titleKey))
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background {
                            Capsule()
                                .fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
                                .overlay {
                                    Capsule()
                                        .stroke(Color.primary.opacity(selected ? 0 : 0.1), lineWidth: 0.5)
                                }
                                .shadow(color: selected ? accent.opacity(0.4) : .clear, radius: 10, x: 0, y: 6)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            // Extra room so the selected chip's shadow isn't clipped by the scroll view
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, -22)
        .padding(.bottom, -16)
    }

    private var dial: some View {
        let size: CGFloat = 290

        return ZStack {
            OutingRing(
                progress: Double(durationMinutes) / Double(maxMinutes),
                accent: accent,
                showsHourTicks: true
            )
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateDuration(at: value.location, in: size)
                    }
            )

            TimelineView(.everyMinute) { context in
                let returnDate = context.date.addingTimeInterval(TimeInterval(durationMinutes * 60))

                VStack(spacing: 6) {
                    Text("Outing_Expected_Return")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color.primary.opacity(0.45))

                    Text(returnDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())

                    HStack(spacing: 6) {
                        if !Calendar.current.isDate(returnDate, inSameDayAs: context.date) {
                            Text("Outing_Tomorrow")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accent))
                        }
                        Text(durationText(durationMinutes))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .contentTransition(.numericText())
                    }
                }
                .frame(width: size * 0.62)
                .animation(.snappy, value: durationMinutes)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Outing_Duration"))
        .accessibilityValue(Text(durationText(durationMinutes)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: durationMinutes = min(maxMinutes, durationMinutes + 15)
            case .decrement: durationMinutes = max(minMinutes, durationMinutes - 15)
            @unknown default: break
            }
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Outing_Note", systemImage: "mappin.and.ellipse")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(Color.primary.opacity(0.45))

            TextField("Outing_Note_Placeholder", text: $note, axis: .vertical)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .lineLimit(2...5)
                .focused($noteFocused)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasContact {
                tipRow(systemImage: "envelope.fill") {
                    Text(String(format: NSLocalizedString("Outing_Notify_Contact", comment: ""), trimmedContact))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                tipRow(systemImage: "exclamationmark.triangle.fill") {
                    Text("Sync_Status_NoEmail")
                }
                .foregroundStyle(Color.orange)
            }

            tipRow(systemImage: "text.bubble.fill") {
                Text("Outing_Note_Footer")
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func tipRow<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var startButton: some View {
        Button {
            noteFocused = false
            Task { await start() }
        } label: {
            HStack(spacing: 10) {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "shield.lefthalf.filled")
                    Text("Outing_Start")
                }
            }
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Capsule()
                            .stroke(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 1.5)
                    }
                    .shadow(color: accent.opacity(0.45), radius: 24, x: 0, y: 14)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!hasContact)
        .opacity(hasContact ? 1 : 0.4)
    }

    // MARK: - In Progress

    @ViewBuilder
    private var activeContent: some View {
        statusPill

        ZStack {
            OutingRing(
                progress: remainingProgress,
                accent: activeColor,
                showsHourTicks: false
            )
            .frame(width: 290, height: 290)

            VStack(spacing: 6) {
                Text(isOverdue ? LocalizedStringKey("Outing_Overdue_By") : LocalizedStringKey("Outing_Remaining"))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.primary.opacity(0.45))

                Text(countdownText)
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(isOverdue ? activeColor : Color.primary)
                    .contentTransition(.numericText(countsDown: !isOverdue))
                    .animation(.snappy, value: countdownText)

                if let deadline = manager.outingDeadline {
                    Text(String(format: NSLocalizedString("Outing_Return_By", comment: ""), deadline.formatted(date: .omitted, time: .shortened)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(activeColor)
                }
            }
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity)

        if isOverdue {
            Text("Outing_Overdue_Hint")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(activeColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }

        if !manager.outingNote.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Outing_Note", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.primary.opacity(0.45))
                Text(manager.outingNote)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 26)
        }

        extendRow

        VStack(spacing: 12) {
            holdToEndButton

            Text("Outing_Active_Footer")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(activeColor)
                .frame(width: 8, height: 8)
                .background {
                    Circle()
                        .fill(activeColor.opacity(0.5))
                        .scaleEffect(pulse ? 2.6 : 1)
                        .opacity(pulse ? 0 : 1)
                }
            Text(isOverdue ? LocalizedStringKey("Outing_Overdue") : LocalizedStringKey("Outing_Active"))
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(activeColor)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().stroke(activeColor.opacity(0.3), lineWidth: 1)
                }
        }
    }

    private var extendRow: some View {
        VStack(spacing: 10) {
            Text("Outing_Extend")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(Color.primary.opacity(0.45))

            HStack(spacing: 10) {
                ForEach([30, 60, 120], id: \.self) { minutes in
                    Button {
                        Task { await extend(by: minutes) }
                    } label: {
                        Text("+" + durationText(minutes, style: .abbreviated))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                    }
                            }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    private var holdToEndButton: some View {
        let safeColor = statusColor(.safe)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.ultraThinMaterial)

            GeometryReader { geo in
                Capsule()
                    .fill(LinearGradient(colors: [safeColor, safeColor.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.height, geo.size.width * holdProgress))
                    .opacity(holdProgress > 0 ? 1 : 0)
            }

            HStack(spacing: 10) {
                if isWorking {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.shield.fill")
                    Text("Outing_End")
                    Text("·")
                        .opacity(0.5)
                    Text("Outing_Hold_Hint")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .opacity(0.7)
                }
            }
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(holdProgress > 0.5 ? Color.white : safeColor)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 64)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(safeColor.opacity(0.5), lineWidth: 1.5)
        }
        .shadow(color: safeColor.opacity(0.3), radius: 20, x: 0, y: 12)
        .scaleEffect(holdProgress > 0 ? 0.97 : 1)
        .onLongPressGesture(minimumDuration: holdDuration) {
            Task { await end() }
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(.linear(duration: holdDuration)) { holdProgress = 1 }
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { holdProgress = 0 }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            Task { await end() }
        }
    }

    // MARK: - Actions

    private func start() async {
        isWorking = true
        let result = await manager.startOuting(minutes: durationMinutes, note: composedNote)
        isWorking = false
        if result != .failed && result != .noEmail {
            outingTotalSeconds = Double(durationMinutes * 60)
            note = ""
            activity = nil
        }
        handle(result, successMessage: nil)
    }

    private func extend(by minutes: Int) async {
        let remaining = max(0, manager.outingTimeRemaining)
        isWorking = true
        let result = await manager.extendOuting(by: minutes)
        isWorking = false
        if result != .failed && result != .noEmail {
            outingTotalSeconds = remaining + Double(minutes * 60)
        }
        handle(result, successMessage: nil)
    }

    private func end() async {
        isWorking = true
        let result = await manager.endOuting()
        isWorking = false
        if result != .failed {
            outingTotalSeconds = 0
        }
        handle(result, successMessage: "Outing_Ended")
    }

    private func handle(_ result: AliveManager.OutingResult, successMessage: LocalizedStringKey?) {
        switch result {
        case .success:
            feedbackCount += 1
            if let successMessage {
                showToast(successMessage)
            }
        case .allClearSent:
            feedbackCount += 1
            showToast("All_Clear_Sent")
        case .noEmail:
            alertMessage = "Sync_Status_NoEmail"
        case .failed:
            alertMessage = "Outing_Request_Failed"
        }
    }

    private func showToast(_ message: LocalizedStringKey) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            toastMessage = message
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) {
                toastMessage = nil
            }
        }
    }

    private func updateDuration(at location: CGPoint, in size: CGFloat) {
        let dx = location.x - size / 2
        let dy = location.y - size / 2
        // 0 at 12 o'clock, increasing clockwise
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }

        let raw = angle / (2 * .pi) * Double(maxMinutes)
        var minutes = Int((raw / 5).rounded()) * 5

        // Don't jump across the 12 o'clock seam
        if durationMinutes > maxMinutes * 3 / 4 && minutes < maxMinutes / 4 {
            minutes = maxMinutes
        } else if durationMinutes < maxMinutes / 4 && minutes > maxMinutes * 3 / 4 {
            minutes = minMinutes
        }
        minutes = min(max(minutes, minMinutes), maxMinutes)

        if minutes != durationMinutes {
            durationMinutes = minutes
            dialTick += 1
        }
    }

    // MARK: - Helpers

    private var composedNote: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let activity else { return trimmed }
        let name = NSLocalizedString(activity.titleKey, comment: "")
        return trimmed.isEmpty ? name : "\(name) · \(trimmed)"
    }

    private var isOverdue: Bool {
        manager.outingTimeRemaining <= 0
    }

    private var remainingProgress: Double {
        let remaining = max(0, manager.outingTimeRemaining)
        let total = max(outingTotalSeconds, remaining, 1)
        return remaining / total
    }

    private var backgroundStatus: AliveManager.AliveStatus {
        guard manager.isOutingActive else { return .safe }
        if isOverdue { return .danger }
        return manager.outingTimeRemaining < 15 * 60 ? .warning : .safe
    }

    private var activeColor: Color {
        statusColor(backgroundStatus)
    }

    /// Calm blue used while planning an outing
    private var accent: Color {
        colorScheme == .dark ? Color(hex: "4FC3F7") : Color(hex: "1E6FD9")
    }

    private func statusColor(_ status: AliveManager.AliveStatus) -> Color {
        if colorScheme == .dark {
            switch status {
            case .safe: return Color(hex: "00F260")
            case .warning: return Color(hex: "FFB347")
            case .danger: return Color(hex: "FF4B2B")
            }
        } else {
            switch status {
            case .safe: return Color(hex: "1D976C")
            case .warning: return Color(hex: "E67E22")
            case .danger: return Color(hex: "C0392B")
            }
        }
    }

    private var countdownText: String {
        let seconds = Int(abs(manager.outingTimeRemaining))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func durationText(_ minutes: Int, style: DateComponentsFormatter.UnitsStyle = .short) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = style
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)"
    }
}

// MARK: - Activities

private struct OutingActivity: Identifiable, Equatable {
    let id: String
    let symbol: String
    let minutes: Int

    var titleKey: String { "Outing_Activity_\(id)" }

    static let all: [OutingActivity] = [
        OutingActivity(id: "night", symbol: "moon.stars.fill", minutes: 30),
        OutingActivity(id: "run", symbol: "figure.run", minutes: 60),
        OutingActivity(id: "ride", symbol: "bicycle", minutes: 120),
        OutingActivity(id: "date", symbol: "heart.fill", minutes: 180),
        OutingActivity(id: "hike", symbol: "mountain.2.fill", minutes: 300),
        OutingActivity(id: "trip", symbol: "car.fill", minutes: 480)
    ]
}

// MARK: - Toast

/// Same look as the check-in toast on the home tab
private struct OutingToast: View {
    let message: LocalizedStringKey

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white)
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
        .allowsHitTesting(false)
    }
}

// MARK: - Ring

private struct OutingRing: View {
    let progress: Double
    let accent: Color
    let showsHourTicks: Bool

    private let lineWidth: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - lineWidth) / 2
            let clamped = min(max(progress, 0), 1)
            let angle = clamped * 2 * .pi

            ZStack {
                // Soft glow behind the ring
                Circle()
                    .fill(accent.opacity(0.18))
                    .blur(radius: 40)
                    .padding(lineWidth)

                // Glass track
                Circle()
                    .stroke(.ultraThinMaterial, lineWidth: lineWidth)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
                    }
                    .padding(lineWidth / 2)

                if showsHourTicks {
                    ForEach(0..<12, id: \.self) { hour in
                        Capsule()
                            .fill(Color.primary.opacity(hour % 3 == 0 ? 0.35 : 0.15))
                            .frame(width: 2, height: hour % 3 == 0 ? 10 : 6)
                            .offset(y: -(radius - lineWidth / 2 - 10))
                            .rotationEffect(.degrees(Double(hour) * 30))
                    }

                    ForEach([3, 6, 9, 12], id: \.self) { hour in
                        let a = Double(hour) / 12 * 2 * .pi
                        let r = radius - lineWidth / 2 - 28
                        Text("\(hour)h")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .position(x: size / 2 + r * sin(a), y: size / 2 - r * cos(a))
                    }
                }

                // Progress arc
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            colors: [accent.opacity(0.55), accent],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(max(clamped * 360, 1))
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                    .shadow(color: accent.opacity(0.45), radius: 12, x: 0, y: 6)

                // Knob at the end of the arc
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth + 10, height: lineWidth + 10)
                    .overlay {
                        Circle()
                            .fill(accent)
                            .frame(width: 10, height: 10)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .position(x: size / 2 + radius * sin(angle), y: size / 2 - radius * cos(angle))
            }
            .frame(width: size, height: size)
            .animation(.snappy, value: clamped)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    OutingView(manager: AliveManager())
}
