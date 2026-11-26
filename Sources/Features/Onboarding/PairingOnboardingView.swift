import SwiftUI

struct PairingOnboardingView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @State private var viewModel = PairingViewModel(discovery: BonjourServerBrowser())

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            AmbientBackdropView()

            VStack(spacing: 36) {
                VStack(spacing: 14) {
                    LunaCrescentMarkView(size: 64, color: LunaTheme.amber)

                    Text("Luna")
                        .font(LunaTheme.Font.heroSerif)
                        .foregroundStyle(LunaTheme.linen)
                }

                if let pairingInfo = viewModel.pairingInfo, let selectedBaseURL = viewModel.selectedBaseURL {
                    pairingCodePanel(pairingInfo: pairingInfo, baseURL: selectedBaseURL)
                } else {
                    discoveryPanel
                }

                if let errorMessage = viewModel.errorMessage {
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
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
        .onChange(of: viewModel.discoveredServers) { _, discovered in
            viewModel.handleDiscoveredServers(discovered, session: sessionStore)
        }
    }

    private var discoveryPanel: some View {
        @Bindable var viewModel = viewModel
        let servers = viewModel.discoveredServers

        return VStack(spacing: 26) {
            if servers.isEmpty {
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

                    ForEach(Array(servers.enumerated()), id: \.element.id) { index, srv in
                        LunaPillButton(
                            "\(srv.name) · \(srv.displayAddress)",
                            systemImage: "server.rack",
                            prominence: (!viewModel.showManualInput && index == 0) ? .primary : .glassPill
                        ) {
                            guard !viewModel.isRequestingCode else { return }
                            viewModel.startPairing(
                                against: srv.baseURL,
                                localHostnameURL: srv.localHostnameURL,
                                session: sessionStore
                            )
                        }
                    }
                }
            }

            if viewModel.showManualInput {
                VStack(spacing: 16) {
                    LunaTextField(
                        "Serveradresse (f.eks. http://lunacore.local:8090)",
                        text: $viewModel.manualURLInput,
                        leadingSystemImage: "server.rack",
                        keyboardType: .URL,
                        returnKeyType: .go
                    )
                    .frame(width: 760)

                    HStack(spacing: 20) {
                        LunaPillButton("Start paring", systemImage: "link", prominence: .primary) {
                            viewModel.submitManualURL(session: sessionStore)
                        }

                        LunaPillButton("Skjul manuell adresse", prominence: .subtleChip) {
                            viewModel.showManualInput = false
                        }
                    }
                }
            } else {
                LunaPillButton("Skriv inn serveradresse manuelt", systemImage: "keyboard", prominence: .subtleChip) {
                    viewModel.showManualInput = true
                }
            }
        }
    }

    private func pairingCodePanel(pairingInfo: TvPairingRequestResponse, baseURL: URL) -> some View {
        let isCodeExpired = viewModel.isCodeExpired

        return VStack(spacing: 28) {
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
                    viewModel.startPairing(
                        against: baseURL,
                        localHostnameURL: viewModel.selectedLocalHostnameURL,
                        session: sessionStore
                    )
                }

                LunaPillButton("Bytt server", systemImage: "network", prominence: .subtleChip) {
                    viewModel.resetServerSelection()
                }
            }
        }
    }
}
