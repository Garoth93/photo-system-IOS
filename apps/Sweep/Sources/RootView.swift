import Photos
import SwiftUI
import UIKit

/// Asks for access to the photos, then shows the home.
struct RootView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(CloudBackupService.self) private var cloud
    @Environment(\.m3) private var m3

    var body: some View {
        @Bindable var cloud = cloud
        ZStack(alignment: .bottom) {
            m3.surface.ignoresSafeArea()

            if library.canRead {
                HomeView()
            } else {
                WelcomeView()
            }

            if let toast = model.toast {
                Snackbar(text: toast)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
                    .zIndex(10)
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
        .animation(.easeInOut(duration: 0.3), value: library.canRead)
        // First launch with an empty app and a backup in iCloud: guided restore.
        .task(id: library.canRead) {
            if library.canRead { await cloud.offerRestoreIfNeeded() }
        }
        .sheet(isPresented: $cloud.offerRestore) {
            CloudRestoreView(firstLaunch: true)
        }
    }
}

/// First screen: what the app does and the permission request.
struct WelcomeView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL

    private var denied: Bool {
        library.status == .denied || library.status == .restricted
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            ZStack {
                CookieShape(lobes: 12, depth: 0.05)
                    .fill(m3.primaryContainer)
                    .frame(width: 132, height: 132)
                Image(systemName: "photo.stack")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(m3.onPrimaryContainer)
            }

            VStack(spacing: 10) {
                Text("Sweep")
                    .font(.m3DisplaySmall)
                    .foregroundStyle(m3.onSurface)
                Text("Fai pulizia nella galleria,\nuna foto alla volta.")
                    .font(.m3BodyLarge)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                GestureHintRow(icon: "arrow.left", title: "Scorri a sinistra", detail: "tieni la foto e vai avanti", tones: m3.keep)
                GestureHintRow(icon: "arrow.right", title: "Scorri a destra", detail: "eliminala e vai avanti", tones: m3.delete)
                GestureHintRow(icon: "arrow.up", title: "Scorri in su", detail: "decidi dopo: torna alla fine", tones: m3.later)
                GestureHintRow(icon: "arrow.down", title: "Scorri in giù", detail: "aggiungila ai Preferiti", tones: m3.favorite)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 10)

            VStack(spacing: 10) {
                if denied {
                    Text("L'accesso alle foto è disattivato. Attivalo da Impostazioni → Sweep → Foto → Accesso completo.")
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Apri Impostazioni") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.m3FilledLarge)
                } else {
                    Button("Consenti accesso alle foto") {
                        Task { await library.requestAccess() }
                    }
                    .buttonStyle(.m3FilledLarge)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
    }
}

struct GestureHintRow: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let detail: String
    let tones: Tones

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(icon: icon, tones: tones, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                Text(detail).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer()
        }
        .padding(10)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
