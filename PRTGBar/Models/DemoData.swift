import Foundation

enum DemoData {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--demo")
    }

    static let serverURL = "https://prtg.example.com"

    // MARK: - Demo Tree

    static func buildTree() -> [TreeNode] {
        [
            TreeNode(id: 1, name: "Local Probe", kind: .probedevice, status: .down, children: [
                groupWebServers, groupDatabases, groupNetwork, groupOffice,
            ]),
            TreeNode(id: 2, name: "Frankfurt Probe", kind: .probedevice, status: .warning, children: [
                groupWebServersFrankfurt, groupOfficeFrankfurt,
            ]),
        ]
    }

    static var problemTimestamps: [Int: Date] {
        [
            101: Date(timeIntervalSinceNow: -691_200),  // 8d
            102: Date(timeIntervalSinceNow: -45),        // < 1m
            201: Date(timeIntervalSinceNow: -3_720),     // ~1h
            301: Date(timeIntervalSinceNow: -172_800),   // 2d
            501: Date(timeIntervalSinceNow: -7_200),     // 2h
        ]
    }

    /// Sensor 101 was down for 90 minutes about 5 h ago, sensor 201 for 30 minutes about 2 h ago.
    @MainActor static func seedHistory(_ history: StatusHistory, now: Date) {
        let outages: [(id: Int, hoursAgo: Double, minutes: Double)] = [(101, 5, 90), (201, 2, 30)]
        for outage in outages {
            let downStart = now.addingTimeInterval(-outage.hoursAgo * 3600)
            let downEnd = downStart.addingTimeInterval(outage.minutes * 60)
            for minutesAgo in stride(from: 480, through: 10, by: -10) {
                let date = now.addingTimeInterval(-Double(minutesAgo) * 60)
                let isDown = date >= downStart && date < downEnd
                history.record([outage.id: isDown ? .down : .up], at: date)
            }
        }
    }

    // MARK: - Groups

    private static var groupWebServers: TreeNode {
        TreeNode(id: 10, name: "Web Servers", kind: .group, status: .down, children: [
            deviceStage,
            TreeNode(id: 11, name: "Shop", kind: .group, status: .up, children: [deviceShop]),
            deviceProduction,
        ])
    }

    private static var groupWebServersFrankfurt: TreeNode {
        TreeNode(id: 60, name: "Web Servers", kind: .group, status: .warning, children: [
            TreeNode(id: 600, name: "Webserver - Edge", kind: .device, status: .warning, children: [
                TreeNode(
                    id: 601, name: "HTTP Latency", kind: .sensor, status: .warning,
                    message: "Response time 2400 ms", lastDown: Date(timeIntervalSinceNow: -900)
                ),
                TreeNode(id: 602, name: "Ping", kind: .sensor, status: .up),
            ]),
        ])
    }

    private static var groupDatabases: TreeNode {
        TreeNode(id: 20, name: "Databases", kind: .group, status: .down, children: [
            TreeNode(id: 400, name: "MySQL Primary", kind: .device, status: .down, children: [
                TreeNode(
                    id: 401, name: "MySQL Connections", kind: .sensor, status: .down,
                    message: "Acknowledged by admin [K.Michalik]: Maintenance window until 2026-03-12",
                    lastDown: Date(timeIntervalSinceNow: -172_800)
                ),
                TreeNode(id: 402, name: "Disk Free", kind: .sensor, status: .up),
            ]),
            deviceAWS,
        ])
    }

    private static var groupNetwork: TreeNode {
        TreeNode(id: 30, name: "Network", kind: .group, status: .warning, children: [
            deviceFirewall,
            deviceSwitch,
        ])
    }

    private static var groupOffice: TreeNode {
        TreeNode(id: 40, name: "Office", kind: .group, status: .up, children: [
            TreeNode(id: 700, name: "Office Router", kind: .device, status: .up, children: [
                TreeNode(id: 701, name: "Ping", kind: .sensor, status: .up),
                TreeNode(id: 702, name: "Bandwidth", kind: .sensor, status: .up),
            ]),
        ])
    }

    private static var groupOfficeFrankfurt: TreeNode {
        TreeNode(id: 70, name: "Office", kind: .group, status: .up, children: [
            TreeNode(id: 800, name: "Frankfurt Switch", kind: .device, status: .up, children: [
                TreeNode(id: 801, name: "Ping", kind: .sensor, status: .up),
                TreeNode(id: 802, name: "Port Utilization", kind: .sensor, status: .paused),
            ]),
        ])
    }

    // MARK: - Devices & Sensors

    private static var deviceStage: TreeNode {
        TreeNode(id: 100, name: "Webserver - Stage", kind: .device, status: .down, children: [
            TreeNode(
                id: 101, name: "HTTP - Impressum vorhanden", kind: .sensor, status: .down,
                message: "HTTP/1.1 421 Misdirected Request",
                lastDown: Date(timeIntervalSinceNow: -691_200)
            ),
            TreeNode(id: 102, name: "Ping", kind: .sensor, status: .up),
            TreeNode(id: 103, name: "CPU Load", kind: .sensor, status: .up),
        ])
    }

    private static var deviceShop: TreeNode {
        TreeNode(id: 120, name: "Shop Frontend", kind: .device, status: .down, children: [
            TreeNode(
                id: 501, name: "Checkout Health", kind: .sensor, status: .down,
                message: "HTTP/1.1 503 Service Unavailable",
                lastDown: Date(timeIntervalSinceNow: -7_200)
            ),
            TreeNode(id: 502, name: "HTTP", kind: .sensor, status: .up),
        ])
    }

    private static var deviceProduction: TreeNode {
        TreeNode(id: 110, name: "Webserver - Production", kind: .device, status: .up, children: [
            TreeNode(id: 111, name: "HTTP", kind: .sensor, status: .up),
            TreeNode(id: 112, name: "Ping", kind: .sensor, status: .up),
            TreeNode(id: 113, name: "SSL Certificate", kind: .sensor, status: .up),
            TreeNode(id: 114, name: "DNS Resolution", kind: .sensor, status: .up),
        ])
    }

    private static var deviceFirewall: TreeNode {
        TreeNode(id: 200, name: "FortiGate 200F", kind: .device, status: .warning, children: [
            TreeNode(
                id: 201, name: "SSL Certificate Sensor", kind: .sensor, status: .warning,
                message: "34 days until expiration",
                lastDown: Date(timeIntervalSinceNow: -3_720)
            ),
            TreeNode(id: 202, name: "Ping", kind: .sensor, status: .up),
            TreeNode(id: 203, name: "CPU Load", kind: .sensor, status: .up),
            TreeNode(id: 204, name: "VPN Tunnel", kind: .sensor, status: .up),
        ])
    }

    private static var deviceSwitch: TreeNode {
        TreeNode(id: 210, name: "Cisco Catalyst 9300", kind: .device, status: .up, children: [
            TreeNode(id: 211, name: "SNMP Traffic", kind: .sensor, status: .up),
            TreeNode(id: 212, name: "Ping", kind: .sensor, status: .up),
            TreeNode(id: 213, name: "Port Utilization", kind: .sensor, status: .paused),
        ])
    }

    private static var deviceAWS: TreeNode {
        TreeNode(id: 300, name: "AWS EU-Central", kind: .device, status: .down, children: [
            TreeNode(
                id: 301, name: "EC2 Health Check", kind: .sensor, status: .down,
                message: "Acknowledged by admin [K.Michalik]: Maintenance window until 2026-03-12",
                lastDown: Date(timeIntervalSinceNow: -172_800)
            ),
            TreeNode(id: 302, name: "CloudWatch CPU", kind: .sensor, status: .up),
            TreeNode(id: 303, name: "S3 Bucket Size", kind: .sensor, status: .up),
        ])
    }
}
