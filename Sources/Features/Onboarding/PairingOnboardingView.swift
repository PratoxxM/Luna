import SwiftUI

struct PairingOnboardingView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @StateObject private var bonjour = BonjourServerBrowser()

    @State private var manualURLInput: String = ""
    @State private var showManualInput: Bool = false
    @State private var selectedBaseURL: URL?
    @State private var pairingInfo: TvPairingRequestResponse?
    @State private var statusMessage: String = "Søker etter LunaCore på lokalnettet…"
    @State private var errorMessage: String?
    @State private var isRequestingCode: Bool = false
    @State private var isCodeExpired: Bool = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.09, green: 0.08, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 36) {
                VStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.42))

                    Text("Luna")
                        .font(.system(size: 56, weight: .bold, design: .rounded))

                    Text("Dedikert hjemmekino for LunaCore · Dolby Vision FEL & Spatial Audio")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if let pairingInfo, let selectedBaseURL {
                    pairingCodePanel(pairingInfo: pairingInfo, baseURL: selectedBaseURL)
                } else {
                    discoveryPanel
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
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
                startPairing(against: onlyServer.baseURL)
            }
        }
    }

    private var discoveryPanel: some View {
        VStack(spacing: 26) {
            if bonjour.servers.isEmpty {
                HStack(spacing: 16) {
                    ProgressView()
                    Text(statusMessage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Funnet på lokalnettet")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ForEach(bonjour.servers) { srv in
                        LunaPillButton(
                            "\(srv.name) · \(srv.displayAddress)",
                            systemImage: "server.rack",
                            prominence: .primaryAmber
                        ) {
                            guard !isRequestingCode else { return }
                            startPairing(against: srv.baseURL)
                        }
                    }
                }
            }

            if showManualInput {
                VStack(spacing: 16) {
                    TextField("Serveradresse (f.eks. http://lunacore.local:8090)", text: $manualURLInput)
                        .frame(width: 760)

                    HStack(spacing: 20) {
                        LunaPillButton("Start paring", systemImage: "link", prominence: .primaryAmber) {
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
            Text(isCodeExpired ? "Paringskoden er utløpt" : "Godkjenn TV-en i LunaCore Web")
                .font(.title2.weight(.semibold))
                .foregroundStyle(isCodeExpired ? LunaTheme.amber : .white)

            Text(isCodeExpired ? "------" : pairingInfo.displayCode)
                .font(.system(size: 88, weight: .heavy, design: .monospaced))
                .tracking(8)
                .foregroundStyle(isCodeExpired ? LunaTheme.muted : Color(red: 0.96, green: 0.77, blue: 0.42))
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

            VStack(spacing: 8) {
                Text("Åpne LunaCore på mobil eller PC → System → Luna Apple TV (eller banneret øverst).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Velg rom («Kjellerstua» eller «Stua») og trykk Godkjenn — Luna logger inn automatisk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Server: \(baseURL.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                LunaPillButton("Ny kode", systemImage: "arrow.clockwise", prominence: .primaryAmber) {
                    startPairing(against: baseURL)
                }

                LunaPillButton("Bytt server", systemImage: "network", prominence: .subtleChip) {
                    pollTask?.cancel()
                    self.pairingInfo = nil
                    self.selectedBaseURL = nil
                    self.showManualInput = true
                }
            }
        }
    }

    private func startPairing(against baseURL: URL) {
        pollTask?.cancel()
        errorMessage = nil
        isCodeExpired = false
        selectedBaseURL = baseURL
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
                                pairedDevice: pairedDevice
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
                            self.errorMessage = "Midlertidig nettverksbrudd mot LunaCore (\(error.localizedDescription)). Prøver fortsatt…"
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.isRequestingCode = false
                    self.pairingInfo = nil
                    self.errorMessage = "Kunne ikke kontakte LunaCore på \(baseURL.absoluteString): \(error.localizedDescription)"
                }
            }
        }
    }
}
