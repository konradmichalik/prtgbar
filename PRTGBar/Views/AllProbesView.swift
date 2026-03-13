import SwiftUI

struct AllProbesView: View {
    let treeNodes: [TreeNode]
    let serverURL: String
    let searchText: String
    var statusFilter: StatusPillFilter?

    var body: some View {
        let filtered = TreeFilter.filter(treeNodes, query: searchText, statusFilter: statusFilter)

        if !filtered.isEmpty {
            Section {
                ForEach(filtered) { node in
                    TreeNodeRowView(node: node, serverURL: serverURL, searchActive: !searchText.isEmpty || statusFilter != nil)
                }
            } header: {
                SectionHeaderView(title: "All Probes", count: sensorCount(filtered))
            }
        }
    }

    private func sensorCount(_ nodes: [TreeNode]) -> Int {
        nodes.reduce(0) { $0 + $1.totalSensorCount }
    }
}
