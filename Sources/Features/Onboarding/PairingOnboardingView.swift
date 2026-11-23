import SwiftUI

struct PairingOnboardingView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @State private var bonjour = BonjourServerBrowser()

    @State private var manualURLInput: String = ""
    @State private var showManualInput: Bool = false
    @State private var selectedBaseURL: URL?
    @State private var selectedLocalHostnameURL: URL?
    @State private var pairingInfo: TvPairingRequestResponse?
    @State private var errorMessage: String?
    @State private var isRequestingCode: Bool = false
    @State private var isCodeExpired: Bool = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AmbientBackdropView()

            VStack(spacing: 36) {
                VStack(spacing: 14) {
                    LunaCrescentMarkView(size: 64, color: LunaTheme.amber)

                    Text("Luna")
                        .font(LunaTheme.Font.heroSerif)
                        .foregroundStyle(LunaTheme.linen)
                }

                if let pairingInfo, let selectedBaseURL {
                    pairingCodePanel(pairingInfo: pairingInfo, baseURL: selectedBaseURL)
                } else {
                    discoveryPanel
                }

                if let errorMessage {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(LunaTheme.coral)
                            .frame(width: 8, height: 8)
                        Text(errorMessage)
                            .font(LunaTheme.Font.body)
                            .foregroundStyle(LunaTheme.linen)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 920)
                }
            }
            .padding(60)
        }
        .onAppear {
            bonjour.start()
        }
        .onDisappear {
            pollTask?.cancel()
            bonjour.stop()
        }
        .onChange(of: bonjour.servers) { _, discovered in
            if selectedBaseURL == nil,
               pairingInfo == nil,
               discovered.count == 1,
               let onlyServer = discovered.first,
               !showManualInput {
                startPairing(against: onlyServer.baseURL, localHostnameURL: onlyServer.localHostnameURL)
            }
        }
    }

    private var discoveryPanel: some View {
        VStack(spacing: 26) {
            if bonjour.servers.isEmpty {
                HStack(spacing: 16) {
                    ProgressView()
                    Text("Søker etter LunaCore på lokalnettet…")
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.moonlight)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Funnet på lokalnettet")
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.muted)

                    ForEach(Array(bonjour.servers.enumerated()), id: \.element.id) { index, srv in
                        LunaPillButton(
                            "\(srv.name) · \(srv.displayAddress)",
                            systemImage: "server.rack",
                            prominence: (!showManualInput && index == 0) ? .primary : .glassPill
                        ) {
                            guard !isRequestingCode else { return }
                            startPairing(against: srv.baseURL, localHostnameURL: srv.localHostnameURL)
                        }
                    }
                }
            }

            if showManualInput {
                VStack(spacing: 16) {
                    TextField("Serveradresse (f.eks. http://lunacore.local:8090)", text: $manualURLInput)
                        .frame(width: 760)

                    HStack(spacing: 20) {
                        LunaPillButton("Start paring", systemImage: "link", prominence: .primary) {
                            guard !isRequestingCode else { return }
                            guard let normalized = AppSessionStore.normalizeServerURL(manualURLInput) else {
                                errorMessage = "Oppgi en gyldig http:// eller https:// adresse."
                                return
                            }
                            startPairing(against: normalized)
                        }

                        LunaPillButton("Skjul manuell adresse", prominence: .subtleChip) {
                            showManualInput = false
                        }
                    }
                }
            } else {
                LunaPillButton("Skriv inn serveradresse manuelt", systemImage: "keyboard", prominence: .subtleChip) {
                    showManualInput = true
                }
            }
        }
    }

    private func pairingCodePanel(pairingInfo: TvPairingRequestResponse, baseURL: URL) -> some View {
        VStack(spacing: 28) {
            Text(isCodeExpired ? "Paringskoden er utløpt" : "Godkjenn TV-en i LunaCore")
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(isCodeExpired ? LunaTheme.warn : LunaTheme.linen)

            Text(isCodeExpired ? "------" : pairingInfo.displayCode)
                .font(LunaTheme.Font.pairingCode)
                .foregroundStyle(isCodeExpired ? LunaTheme.muted : LunaTheme.linen)
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                        .fill(LunaTheme.surfaceRaised)
                )
                .lunaTopLightEdge(cornerRadius: LunaTokens.Radius.panel, topColor: LunaTokens.Edge.top3)

            VStack(spacing: 8) {
                Text("Åpne LunaCore på iPhone eller Mac → Apple TV.")
                    .font(LunaTheme.Font.body)
                    .foregroundStyle(LunaTheme.moonlight)
                Text("Velg rom («Kjellerstua» eller «Stua») og trykk Godkjenn — Luna logger inn automatisk.")
                    .font(LunaTheme.Font.body)
                    .foregroundStyle(LunaTheme.moonlight)
                Text("Tilkobling: \(baseURL.absoluteString)")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                LunaPillButton("Ny kode", systemImage: "arrow.clockwise", prominence: .primary) {
                    startPairing(against: baseURL, localHostnameURL: selectedLocalHostnameURL)
                }

                LunaPillButton("Bytt server", systemImage: "network", prominence: .subtleChip) {
                    pollTask?.cancel()
                    self.pairingInfo = nil
                    self.selectedBaseURL = nil
                    self.selectedLocalHostnameURL = nil
                    self.showManualInput = true
                }
            }
        }
    }

    private func startPairing(against baseURL: URL, localHostnameURL: URL? = nil) {
        pollTask?.cancel()
        errorMessage = nil
        isCodeExpired = false
        selectedBaseURL = baseURL
        selectedLocalHostnameURL = localHostnameURL
        isRequestingCode = true

        pollTask = Task { @MainActor in
            guard let client = sessionStore.makeClient(overrideBaseURL: baseURL) else {
                isRequestingCode = false
                errorMessage = "Kunne ikke opprette klient mot \(baseURL.absoluteString)."
                return
            }

            do {
                let info = try await client.requestPairingCode(
                    model: AppSessionStore.currentHardwareModelString(),
                    osVersion: AppSessionStore.currentSystemVersionString(),
                    appVersion: AppSessionStore.currentAppVersionString()
                )
                self.pairingInfo = info
                self.isRequestingCode = false

                let interval = max(2, info.pollIntervalSeconds ?? 3)
                var consecutivePollFailures = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                    guard !Task.isCancelled else { return }

                    do {
                        let (httpStatus, poll) = try await client.pollPairingCode(info.pairingCode)
                        consecutivePollFailures = 0
                        if poll.status == "approved",
                           let token = poll.deviceToken,
                           let pairedDevice = poll.device {
                            sessionStore.completePairing(
                                baseURL: baseURL,
                                token: token,
                                pairedDevice: pairedDevice,
                                localHostnameURL: localHostnameURL
                            )
                            return
                        }
                        if httpStatus == 404 || httpStatus == 410 || poll.status == "expired" {
                            self.isCodeExpired = true
                            self.errorMessage = "Paringskoden utløp eller ble brukt. Trykk «Ny kode» for å hente en ny."
                            return
                        }
                        if httpStatus == 429 || poll.status == "rate_limited" {
                            try? await Task.sleep(nanoseconds: UInt64(interval) * 2_000_000_000)
                            continue
                        }
                        if httpStatus == 400 || poll.status == "invalid" {
                            self.isCodeExpired = true
                            self.pairingInfo = nil
                            self.errorMessage = poll.error ?? "Ugyldig paringskode. Trykk «Ny kode» for å prøve igjen."
                            return
                        }
                    } catch {
                        consecutivePollFailures += 1
                        if consecutivePollFailures >= 8, !Task.isCancelled {
                            self.errorMessage = "Midlertidig nettverksbrudd mot LunaCore. Prøver fortsatt…"
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.isRequestingCode = false
                    self.pairingInfo = nil
                    self.errorMessage = LunaCopy.friendlyErrorMessage(
                        error,
                        fallback: "Kunne ikke kontakte LunaCore på \(baseURL.absoluteString)."
                    )
                }
            }
        }
    }
}
