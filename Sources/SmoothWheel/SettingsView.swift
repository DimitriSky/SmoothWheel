import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var engine: ScrollEngine
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !engine.accessibilityGranted { permissionCard }
                    else if engine.problem != nil { problemCard }
                    motionCard
                    exclusionsCard
                    HStack {
                        Toggle("Запускать при входе в macOS", isOn: Binding(
                            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                            set: { enabled in
                                do {
                                    if enabled { try SMAppService.mainApp.register() }
                                    else { try SMAppService.mainApp.unregister() }
                                    loginError = nil
                                } catch {
                                    loginError = error.localizedDescription
                                }
                                loginStatus = SMAppService.mainApp.status
                            }))
                        Spacer()
                    }
                    if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                    if loginStatus == .requiresApproval {
                        Button("Подтвердить запуск в настройках macOS…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }.font(.caption)
                    }
                    Text("Трекпад и другие устройства с непрерывной прокруткой проходят без обработки. ⌃ / ⌥ / ⌘ + колёсико сохраняют обычное поведение. Shift + колёсико прокручивает по горизонтали.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("SmoothWheel 0.1 · Работает локально")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Завершить") { NSApp.terminate(nil) }.controlSize(.small)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(width: 560, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 30)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading,
                                            endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("SmoothWheel").font(.system(size: 25, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(engine.running ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(engine.statusText).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Toggle("Включено", isOn: $preferences.enabled).labelsHidden().toggleStyle(.switch)
                .help("Включить или приостановить сглаживание")
        }.padding(24)
    }

    private var permissionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Разрешите обработку прокрутки", systemImage: "hand.raised.fill")
                    .font(.headline)
                Text("В настройках macOS включите SmoothWheel в разделе «Конфиденциальность и безопасность → Универсальный доступ». Приложение подключится автоматически.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Открыть настройки доступа") { engine.requestAccessibility() }
                    .buttonStyle(.bordered)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var problemCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(engine.problem ?? "").font(.callout)
                HStack {
                    Button("Проверить снова") { engine.retry() }
                    Button("Универсальный доступ") { engine.requestAccessibility() }
                    Button("Мониторинг ввода") { engine.requestInputAccess() }
                }.controlSize(.small)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var motionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Характер прокрутки").font(.headline)
                    Spacer()
                    Button("Сбросить") { preferences.restoreMotionDefaults() }
                        .buttonStyle(.link).font(.caption)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Скорость")
                        Spacer()
                        Text("\(Int(preferences.distance)) пт / единицу колёсика")
                            .monospacedDigit().foregroundStyle(.secondary).font(.caption)
                    }
                    Slider(value: $preferences.distance, in: 8...100, step: 1)
                    HStack { Text("Медленнее"); Spacer(); Text("Быстрее") }
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Инерция")
                        Spacer()
                        Text("\(Int((preferences.duration * 1000).rounded())) мс")
                            .monospacedDigit().foregroundStyle(.secondary).font(.caption)
                    }
                    Slider(value: $preferences.duration, in: 0.1...0.6, step: 0.01)
                    HStack { Text("Короткая и чёткая"); Spacer(); Text("Мягкая и протяжная") }
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Обратить направление колёсика", isOn: $preferences.reversed)
            }.padding(12)
        }
    }

    private var exclusionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Исключения").font(.headline)
                    Spacer()
                    Button { preferences.addExclusion() } label: {
                        Label("Добавить", systemImage: "plus")
                    }.controlSize(.small)
                }
                if preferences.exclusions.isEmpty {
                    Text("Добавьте игры, редакторы или другие приложения, где нужна обычная прокрутка.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(preferences.exclusions) { app in
                        HStack {
                            Image(systemName: "app.dashed").foregroundStyle(.secondary)
                            Text(app.name)
                            Spacer()
                            Button {
                                preferences.exclusions.removeAll { $0.id == app.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("Удалить исключение")
                        }
                    }
                }
            }.padding(12)
        }
    }
}
