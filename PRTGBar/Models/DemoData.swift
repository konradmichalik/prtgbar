import Foundation

enum DemoData {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--demo")
    }

    // MARK: - Demo Tree

    static func buildTree() -> [TreeNode] {
        let probe = TreeNode(id: 1, name: "Local Probe", kind: .probedevice, status: .up, children: [
            groupWebservers,
            groupNetwork,
            groupCloud,
        ])
        return [probe]
    }

    static var problemTimestamps: [Int: Date] {
        [
            101: Date(timeIntervalSinceNow: -691_200),  // 8d
            102: Date(timeIntervalSinceNow: -45),        // < 1m
            201: Date(timeIntervalSinceNow: -3_720),     // ~1h
            301: Date(timeIntervalSinceNow: -172_800),   // 2d
        ]
    }

    // MARK: - Groups

    private static var groupWebservers: TreeNode {
        TreeNode(id: 10, name: "Webservers", kind: .group, status: .down, children: [
            deviceStage,
            deviceProduction,
        ])
    }

    private static var groupNetwork: TreeNode {
        TreeNode(id: 20, name: "Network Infrastructure", kind: .group, status: .warning, children: [
            deviceFirewall,
            deviceSwitch,
        ])
    }

    private static var groupCloud: TreeNode {
        TreeNode(id: 30, name: "Cloud Services", kind: .group, status: .down, children: [
            deviceAWS,
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
