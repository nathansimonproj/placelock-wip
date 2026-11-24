import Foundation
import UIKit

/// Shadow-mode recorder (Debug builds): every fix, iOS event, visit, tracking mode, presence
/// change, the shadow engine's would-be decisions, the real lock and unlock, and the battery
/// level, one JSON object per line in Application Support/location-trace.jsonl. Debug › "Export
/// location trace" shares the file. Coordinates stay on the phone unless you share it.
///
/// In Release every call does nothing, so callers need no `#if`.
@MainActor
enum Trace {
    #if DEBUG
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("location-trace.jsonl")
    }()
    /// Past this, the oldest half is dropped. Bursts log a fix a second, so a busy day can be
    /// ~10 MB; this keeps a 3-day test whole.
    private static let maxBytes = 64_000_000
    private static var handle: FileHandle?
    private static var writes = 0
    private static var lastBattery: Float = -2
    #endif

    static func fix(_ fix: Fix, source: String) {
        record("fix", ["source": source, "lat": fix.latitude, "lon": fix.longitude, "acc": fix.accuracy,
                       "speed": fix.speed, "fixAt": fix.at.timeIntervalSince1970])
    }

    /// Every place's circle, so a trace can be replayed and measured on its own. Logged when the
    /// engine starts and whenever places change.
    static func places(_ places: [Place]) {
        record("places", ["places": places.map { p -> [String: Any] in
            var entry: [String: Any] = ["id": p.id.uuidString, "name": p.name, "lat": p.latitude, "lon": p.longitude,
                                        "radius": p.radius]
            if let after = p.activeAfter { entry["activeAfter"] = after.timeIntervalSince1970 }
            return entry
        }])
    }

    static func geofence(_ event: GeofenceMonitor.Event) {
        record("geofence", ["place": event.placeID?.uuidString ?? "?", "ring": event.ring,
                            "presence": event.presence.rawValue, "eventAt": event.date.timeIntervalSince1970])
    }

    static func visit(lat: Double, lon: Double, accuracy: Double, arrival: Date?, departure: Date?) {
        record("visit", ["lat": lat, "lon": lon, "acc": accuracy,
                         "arrival": arrival?.timeIntervalSince1970 ?? 0, "departure": departure?.timeIntervalSince1970 ?? 0])
    }

    static func mode(_ mode: TrackingPolicy.Mode, background: Bool) {
        record("mode", ["mode": mode.rawValue, "background": background])
    }

    static func presence(_ place: Place, _ state: PresenceRules.PlaceState) {
        record("presence", ["place": place.id.uuidString, "name": place.name, "presence": state.presence.rawValue,
                            "reason": state.reason?.rawValue ?? ""])
    }

    /// `engine` is "shadow" (what the new engine would do) or "current" (what Cove did).
    static func decision(_ engine: String, _ what: String, place: Place? = nil) {
        record("decision", ["engine": engine, "what": what, "place": place?.name ?? "",
                            "placeID": place?.id.uuidString ?? ""])
    }

    static func note(_ text: String) {
        record("note", ["text": text])
    }

    static func record(_ kind: String, _ fields: [String: Any]) {
        #if DEBUG
        var line = fields
        line["kind"] = kind
        line["at"] = Date.now.timeIntervalSince1970
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if device.batteryLevel != lastBattery || kind == "mode" {
            lastBattery = device.batteryLevel
            line["battery"] = device.batteryLevel
            line["lowPower"] = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        line["app"] = UIApplication.shared.applicationState == .active ? "front" : "back"
        guard JSONSerialization.isValidJSONObject(line),
              var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        append(data)
        #endif
    }

    #if DEBUG
    private static func append(_ data: Data) {
        let fm = FileManager.default
        writes += 1
        if writes % 500 == 1, let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int), size > maxBytes {
            close()
            trim()
        }
        if handle == nil {
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle else { return }
        _ = try? handle.seekToEnd() // the file may have been cleared or trimmed
        try? handle.write(contentsOf: data)
    }

    private static func close() {
        try? handle?.close()
        handle = nil
    }

    /// Keeps the newer half, cut at a line break.
    private static func trim() {
        guard let data = try? Data(contentsOf: url) else { return }
        let half = data.suffix(from: data.count / 2)
        guard let cut = half.firstIndex(of: 0x0A) else { return }
        try? Data(half.suffix(from: half.index(after: cut))).write(to: url, options: .atomic)
    }

    static func clear() {
        close()
        try? FileManager.default.removeItem(at: url)
    }

    static var sizeDescription: String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    #endif
}
