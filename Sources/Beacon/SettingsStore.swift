import Foundation

struct SettingRecord {
    let id: String
    let title: String
    let subtitle: String
    let url: String
    let symbol: String
    let keywords: String

    var folded: String { (title + " " + subtitle + " " + keywords).searchFolded }
    var category: String {
        switch id {
        case "wifi", "network", "bluetooth": return "network"
        case "display", "wallpaper", "appearance": return "display"
        case "sound", "notifications": return "sound"
        case "privacy", "full-disk-access", "passwords", "touch-id": return "privacy"
        case "keyboard", "trackpad", "mouse": return "keyboard"
        case "users", "login-items", "icloud": return "accounts"
        default: return ""
        }
    }

    var isCommonFavorite: Bool {
        ["wifi", "bluetooth", "sound", "display", "privacy", "keyboard"].contains(id)
    }
}

/// Searchable shortcuts into System Settings. These are intentionally not part
/// of All: the Settings chip is a focused "jump to a system preference" mode.
final class SettingsStore {
    private let records: [SettingRecord] = [
        SettingRecord(id: "wifi", title: "Wi-Fi", subtitle: "Networks and wireless settings",
                      url: "x-apple.systempreferences:com.apple.wifi-settings-extension",
                      symbol: "wifi", keywords: "internet network wireless router"),
        SettingRecord(id: "network", title: "Network", subtitle: "Ethernet, VPN, DNS, and network services",
                      url: "x-apple.systempreferences:com.apple.Network-Settings.extension",
                      symbol: "network", keywords: "internet ethernet vpn dns tcp ip proxy"),
        SettingRecord(id: "bluetooth", title: "Bluetooth", subtitle: "Devices and accessories",
                      url: "x-apple.systempreferences:com.apple.BluetoothSettings",
                      symbol: "bluetooth", keywords: "airpods mouse keyboard devices"),
        SettingRecord(id: "notifications", title: "Notifications", subtitle: "Alerts and notification style",
                      url: "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                      symbol: "bell.badge", keywords: "alerts banners focus do not disturb"),
        SettingRecord(id: "sound", title: "Sound", subtitle: "Input, output, and volume",
                      url: "x-apple.systempreferences:com.apple.Sound-Settings.extension",
                      symbol: "speaker.wave.2", keywords: "audio microphone speakers output input volume"),
        SettingRecord(id: "display", title: "Displays", subtitle: "Resolution, brightness, and arrangement",
                      url: "x-apple.systempreferences:com.apple.Displays-Settings.extension",
                      symbol: "display", keywords: "monitor brightness resolution night shift"),
        SettingRecord(id: "wallpaper", title: "Wallpaper", subtitle: "Desktop backgrounds and screensaver",
                      url: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
                      symbol: "photo.on.rectangle", keywords: "desktop background screen saver screensaver"),
        SettingRecord(id: "appearance", title: "Appearance", subtitle: "Light, dark, and accent color",
                      url: "x-apple.systempreferences:com.apple.Appearance-Settings.extension",
                      symbol: "circle.lefthalf.filled", keywords: "dark mode light mode accent color"),
        SettingRecord(id: "accessibility", title: "Accessibility", subtitle: "Vision, hearing, motor, and speech",
                      url: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
                      symbol: "accessibility", keywords: "voiceover zoom captions display motor"),
        SettingRecord(id: "control-center", title: "Control Center", subtitle: "Menu bar and control toggles",
                      url: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
                      symbol: "switch.2", keywords: "menu bar bluetooth wifi battery clock"),
        SettingRecord(id: "siri", title: "Siri & Spotlight", subtitle: "Assistant and search settings",
                      url: "x-apple.systempreferences:com.apple.Siri-Settings.extension",
                      symbol: "sparkles", keywords: "spotlight search assistant siri suggestions"),
        SettingRecord(id: "privacy", title: "Privacy & Security", subtitle: "Permissions, security, and FileVault",
                      url: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                      symbol: "lock.shield", keywords: "permissions security privacy filevault firewall location camera microphone"),
        SettingRecord(id: "full-disk-access", title: "Full Disk Access", subtitle: "Allow apps to access protected files",
                      url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                      symbol: "externaldrive.badge.checkmark", keywords: "privacy security permissions files beacon messages notes"),
        SettingRecord(id: "storage", title: "Storage", subtitle: "Mac storage, recommendations, and disk usage",
                      url: "x-apple.systempreferences:com.apple.settings.Storage",
                      symbol: "internaldrive", keywords: "disk space drive documents applications system data"),
        SettingRecord(id: "battery", title: "Battery", subtitle: "Power, charging, and low power mode",
                      url: "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                      symbol: "battery.75", keywords: "power energy charging low power"),
        SettingRecord(id: "keyboard", title: "Keyboard", subtitle: "Shortcuts, text input, and dictation",
                      url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
                      symbol: "keyboard", keywords: "shortcuts input text dictation function keys"),
        SettingRecord(id: "trackpad", title: "Trackpad", subtitle: "Pointing, clicking, and gestures",
                      url: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension",
                      symbol: "rectangle.and.hand.point.up.left", keywords: "gesture click tap scroll pointer"),
        SettingRecord(id: "mouse", title: "Mouse", subtitle: "Pointer, scrolling, and buttons",
                      url: "x-apple.systempreferences:com.apple.Mouse-Settings.extension",
                      symbol: "computermouse", keywords: "pointer scroll tracking buttons"),
        SettingRecord(id: "printers", title: "Printers & Scanners", subtitle: "Add and manage printers",
                      url: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension",
                      symbol: "printer", keywords: "printer scanner print scan"),
        SettingRecord(id: "users", title: "Users & Groups", subtitle: "Accounts, login items, and passwords",
                      url: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension",
                      symbol: "person.2", keywords: "account user login items startup admin"),
        SettingRecord(id: "login-items", title: "Login Items", subtitle: "Apps that open at login and background items",
                      url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
                      symbol: "rectangle.stack.badge.play", keywords: "startup launch background allow in background"),
        SettingRecord(id: "passwords", title: "Passwords", subtitle: "Saved passwords, passkeys, and verification codes",
                      url: "x-apple.systempreferences:com.apple.Passwords-Settings.extension",
                      symbol: "key", keywords: "passkeys keychain codes autofill"),
        SettingRecord(id: "touch-id", title: "Touch ID & Password", subtitle: "Fingerprint unlock and password settings",
                      url: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension",
                      symbol: "touchid", keywords: "fingerprint unlock security password"),
        SettingRecord(id: "icloud", title: "Apple ID / iCloud", subtitle: "iCloud, media, purchases, and account",
                      url: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings",
                      symbol: "icloud", keywords: "apple id icloud account storage media purchases"),
        SettingRecord(id: "software-update", title: "Software Update", subtitle: "macOS updates and automatic updates",
                      url: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
                      symbol: "arrow.triangle.2.circlepath", keywords: "update upgrade macos system"),
        SettingRecord(id: "date-time", title: "Date & Time", subtitle: "Clock, time zone, and calendar settings",
                      url: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
                      symbol: "calendar.badge.clock", keywords: "clock timezone time zone calendar"),
        SettingRecord(id: "general", title: "General", subtitle: "Software Update, storage, date, and language",
                      url: "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension",
                      symbol: "gearshape", keywords: "about software update storage date time language transfer reset")
    ]

    func search(tokens: [String], limit: Int = 80) -> [SettingRecord] {
        guard !tokens.isEmpty else { return records }
        return records
            .filter { record in tokens.allSatisfy { record.folded.contains($0) } }
            .sorted { a, b in
                let sa = score(a, tokens: tokens)
                let sb = score(b, tokens: tokens)
                if sa != sb { return sa < sb }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private func score(_ record: SettingRecord, tokens: [String]) -> Int {
        let query = tokens.joined(separator: " ")
        let title = record.title.searchFolded
        if title == query { return 0 }
        if title.hasPrefix(query) { return 50 }
        switch SearchText.matchQuality(title, tokens: tokens) {
        case .exactPhrase, .wholeWords: return 100
        case .wordStarts: return 150
        case .substring: return 200
        case nil:
            switch SearchText.matchQuality(record.folded, tokens: tokens) {
            case .exactPhrase, .wholeWords: return 250
            case .wordStarts: return 300
            case .substring: return 350
            case nil: return 400
            }
        }
    }
}
