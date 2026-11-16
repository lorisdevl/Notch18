import AppKit
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var cityDraft = ""
    @Published var loginError: String?
}

struct SettingsView: View {
    @AppStorage("openOnHover") private var openOnHover = true
    @AppStorage("hoverDelay") private var hoverDelay = 0.15
    @AppStorage("haptics") private var haptics = true
    @AppStorage("showTrackSneak") private var showTrackSneak = true
    @AppStorage("showBatterySneak") private var showBatterySneak = true
    @AppStorage("clipboardEnabled") private var clipboardEnabled = true
    @AppStorage("weatherCity") private var weatherCity = "Nantes"
    @AppStorage("pingHost") private var pingHost = "1.1.1.1"
    @AppStorage("pomoWork") private var pomoWork = 25
    @AppStorage("pomoShort") private var pomoShort = 5
    @AppStorage("pomoLong") private var pomoLong = 15
    @AppStorage("pomoAuto") private var pomoAuto = true
    @AppStorage("showGardeInNotch") private var showGardeInNotch = true
    @AppStorage("mirrorFlip") private var mirrorFlip = true

    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        Form {
            Section("Général") {
                Toggle("Lancer Notch18 à l'ouverture de session", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            model.loginError = nil
                        } catch {
                            model.loginError = "Impossible de modifier l'ouverture automatique : \(error.localizedDescription)"
                        }
                    }
                if let err = model.loginError { Text(err).font(.caption).foregroundStyle(.red) }
                Toggle("Ouvrir l'encoche au survol (sinon : au clic)", isOn: $openOnHover)
                if openOnHover {
                    LabeledContent("Délai avant ouverture") {
                        HStack {
                            Slider(value: $hoverDelay, in: 0...0.8, step: 0.05).frame(width: 160)
                            Text("\(Int(hoverDelay * 1000)) ms").monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                Toggle("Petit retour haptique à l'ouverture", isOn: $haptics)
                LabeledContent("Raccourci clavier", value: "⌥⌘N (ouvrir / fermer)")
                LabeledContent("Garder ouvert", value: "Icône punaise dans l'encoche")
            }

            Section("Aperçus dans l'encoche fermée") {
                Toggle("Afficher le titre quand la musique change", isOn: $showTrackSneak)
                Toggle("Afficher les branchements du chargeur et la batterie faible", isOn: $showBatterySneak)
                Toggle("Afficher mon statut de garde à côté de la caméra", isOn: $showGardeInNotch)
            }

            Section("Météo") {
                HStack {
                    TextField("Ville", text: $model.cityDraft, prompt: Text("Ex. : Nantes, La Roche-sur-Yon…"))
                        .onSubmit(applyCity)
                    Button("Valider", action: applyCity)
                }
                Text("Ville actuelle : \(weatherCity)").font(.caption).foregroundStyle(.secondary)
            }

            Section("Réseau") {
                TextField("Hôte pour le ping", text: $pingHost, prompt: Text("1.1.1.1"))
            }

            Section("Minuteur Pomodoro") {
                Stepper("Concentration : \(pomoWork) min", value: $pomoWork, in: 5...120, step: 5)
                Stepper("Pause courte : \(pomoShort) min", value: $pomoShort, in: 1...30)
                Stepper("Pause longue : \(pomoLong) min", value: $pomoLong, in: 5...60, step: 5)
                Toggle("Enchaîner automatiquement les phases", isOn: $pomoAuto)
            }

            Section("Presse-papiers") {
                Toggle("Garder un historique du texte copié", isOn: $clipboardEnabled)
                Text("Stocké uniquement sur ce Mac. Les mots de passe copiés depuis un gestionnaire sont ignorés.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Effacer tout l'historique") {
                    for item in ClipboardManager.shared.items { ClipboardManager.shared.delete(item) }
                }
            }

            Section("Miroir") {
                Toggle("Image en miroir", isOn: $mirrorFlip)
            }

            Section {
                LabeledContent("Notch18", value: "version 1.0")
                Button("Quitter Notch18") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onAppear { model.cityDraft = weatherCity }
    }

    private func applyCity() {
        let c = model.cityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        weatherCity = c
        WeatherManager.shared.refresh(force: true)
    }
}
