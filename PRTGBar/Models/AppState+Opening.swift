import AppKit

extension AppState {
    func findNode(id: Int) -> TreeNode? {
        var stack = treeNodes
        while let node = stack.popLast() {
            if node.id == id { return node }
            stack.append(contentsOf: node.children)
        }
        return nil
    }

    func open(objectId: Int) {
        let page = switch findNode(id: objectId)?.kind {
        case .device: "/device.htm"
        case .group: "/group.htm"
        case .probedevice: "/probenode.htm"
        case .sensor, nil: "/sensor.htm"
        }
        open(path: page, objectId: objectId)
    }

    func open(path: String, objectId: Int?) {
        let server = DemoData.isEnabled ? DemoData.serverURL : serverURL
        let base = server
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: base.contains("://") ? base : "https://\(base)") else { return }
        // The web UI listens on the default HTTPS port even when the API uses another one.
        components.port = nil
        components.path = path
        components.queryItems = objectId.map { [URLQueryItem(name: "id", value: "\($0)")] }
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
