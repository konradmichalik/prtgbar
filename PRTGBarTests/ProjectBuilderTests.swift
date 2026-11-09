import XCTest
@testable import PRTGBar

final class ProjectBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func sensor(_ id: Int, _ status: SensorStatus, message: String? = nil) -> TreeNode {
        TreeNode(id: id, name: "Sensor \(id)", kind: .sensor, status: status, message: message)
    }

    private func device(_ id: Int, _ name: String, sensors: [TreeNode]) -> TreeNode {
        TreeNode(id: id, name: name, kind: .device, status: .up, children: sensors)
    }

    private func group(_ id: Int, _ name: String, children: [TreeNode]) -> TreeNode {
        TreeNode(id: id, name: name, kind: .group, status: .up, children: children)
    }

    private func probe(_ id: Int, _ name: String, children: [TreeNode]) -> TreeNode {
        TreeNode(id: id, name: name, kind: .probedevice, status: .up, children: children)
    }

    // MARK: - Projects

    func testTopLevelGroupBecomesProject() {
        let roots = [
            probe(1, "Dresden", children: [
                group(10, "Kunde A", children: [device(100, "web-01", sensors: [sensor(1000, .up)])])
            ])
        ]

        let projects = ProjectBuilder.projects(from: roots)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].id, 10)
        XCTAssertEqual(projects[0].name, "Kunde A")
        XCTAssertEqual(projects[0].probeName, "Dresden")
        XCTAssertEqual(projects[0].devices.map(\.name), ["web-01"])
        XCTAssertEqual(projects[0].sensorCount, 1)
    }

    func testNestedGroupBecomesHeadingPath() {
        let roots = [
            probe(1, "Dresden", children: [
                group(10, "Kunde A", children: [
                    group(11, "Web", children: [device(100, "shop-prod", sensors: [sensor(1000, .up)])])
                ])
            ])
        ]

        let projects = ProjectBuilder.projects(from: roots)

        XCTAssertEqual(projects.map(\.name), ["Kunde A"])
        XCTAssertEqual(projects[0].devices[0].path, ["Web"])
        XCTAssertEqual(projects[0].devices[0].heading, "Web › shop-prod")
    }

    func testDevicesWithoutGroupFormProbeProject() {
        let roots = [
            probe(1, "Dresden", children: [device(100, "router", sensors: [sensor(1000, .up)])])
        ]

        let projects = ProjectBuilder.projects(from: roots)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].id, 1)
        XCTAssertEqual(projects[0].name, "Dresden")
        XCTAssertEqual(projects[0].devices[0].path, [])
        XCTAssertEqual(projects[0].devices[0].heading, "router")
    }

    func testProjectsSortWorstFirstThenName() {
        let roots = [
            probe(1, "Dresden", children: [
                group(10, "beta", children: [device(100, "d1", sensors: [sensor(1000, .up)])]),
                group(11, "Alpha", children: [device(101, "d2", sensors: [sensor(1001, .up)])]),
                group(12, "Warn", children: [device(102, "d3", sensors: [sensor(1002, .warning)])]),
                group(13, "Crit", children: [device(103, "d4", sensors: [sensor(1003, .down)])])
            ])
        ]

        let projects = ProjectBuilder.projects(from: roots)

        XCTAssertEqual(projects.map(\.name), ["Crit", "Warn", "Alpha", "beta"])
        XCTAssertEqual(projects[0].worstStatus, .down)
        XCTAssertEqual(projects[0].downCount, 1)
        XCTAssertEqual(projects[1].warningCount, 1)
        XCTAssertEqual(projects[2].worstStatus, .up)
    }

    func testDuplicateProjectNamesGetProbeSuffix() {
        let roots = [
            probe(1, "Dresden", children: [
                group(10, "Office", children: [device(100, "d1", sensors: [sensor(1000, .up)])])
            ]),
            probe(2, "Berlin", children: [
                group(20, "Office", children: [device(200, "d2", sensors: [sensor(2000, .up)])]),
                group(21, "Lager", children: [device(201, "d3", sensors: [sensor(2001, .up)])])
            ])
        ]

        let projects = ProjectBuilder.projects(from: roots)
        let displayNames = Set(projects.map(\.displayName))

        XCTAssertEqual(displayNames, ["Office · Dresden", "Office · Berlin", "Lager"])
    }

    func testAcknowledgedSensorsAreNotProblems() {
        let roots = [
            probe(1, "Dresden", children: [
                group(10, "Kunde A", children: [
                    device(100, "web-01", sensors: [
                        sensor(1000, .down, message: "Acknowledged by admin [x]: known"),
                        sensor(1001, .up)
                    ])
                ])
            ])
        ]

        let project = ProjectBuilder.projects(from: roots)[0]

        XCTAssertEqual(project.devices[0].problemSensors, [])
        XCTAssertEqual(project.devices[0].upCount, 1)
        XCTAssertEqual(project.worstStatus, .up)
        XCTAssertEqual(project.downCount, 0)
    }

    func testSecondLevelGroupBecomesProjectWhenConfigured() {
        let roots = [
            probe(1, "Cloud Probe", children: [
                group(10, "Team A", children: [
                    group(11, "vhw", children: [
                        group(12, "Stage", children: [device(100, "Middleware - Stage", sensors: [sensor(1000, .up)])]),
                        device(101, "Middleware - Production", sensors: [sensor(1001, .warning)]),
                    ]),
                    group(13, "Wilka", children: [device(102, "Webserver", sensors: [sensor(1002, .up)])]),
                ]),
                group(20, "Office", children: [device(200, "router", sensors: [sensor(2000, .up)])]),
            ])
        ]

        let projects = ProjectBuilder.projects(from: roots, level: 2)

        XCTAssertEqual(projects.map(\.name), ["vhw", "Office", "Wilka"])
        XCTAssertEqual(projects.map(\.id), [11, 20, 13])
        XCTAssertEqual(projects[0].devices.map(\.heading), ["Middleware - Production", "Stage › Middleware - Stage"])
        XCTAssertEqual(projects[0].probeName, "Cloud Probe")
    }

    func testProjectsWithoutLoadedProbe() {
        let roots = [
            group(10, "Team A", children: [
                group(11, "vhw", children: [device(100, "api", sensors: [sensor(1000, .up)])]),
            ]),
            group(20, "Team B", children: [
                group(21, "vhw", children: [device(200, "db", sensors: [sensor(2000, .up)])]),
            ]),
        ]

        let projects = ProjectBuilder.projects(from: roots, level: 2)

        XCTAssertEqual(projects.map(\.name), ["vhw", "vhw"])
        XCTAssertEqual(projects.map(\.probeName), ["", ""])
        XCTAssertEqual(projects.map(\.displayName), ["vhw", "vhw"], "no probe suffix without a probe name")
        XCTAssertEqual(ProjectBuilder.projects(from: roots).map(\.name), ["Team A", "Team B"])
    }

    func testProjectNameFromAncestors() {
        let probeNode = probe(1, "Dresden", children: [])
        let top = group(10, "Kunde A", children: [])
        let nested = group(11, "Web", children: [])

        XCTAssertEqual(ProjectBuilder.projectName(ancestors: [probeNode, top, nested]), "Kunde A")
        XCTAssertEqual(ProjectBuilder.projectName(ancestors: [probeNode]), "Dresden")
        XCTAssertEqual(ProjectBuilder.projectName(ancestors: [probeNode, top, nested], level: 2), "Web")
        XCTAssertEqual(ProjectBuilder.projectName(ancestors: [probeNode, top], level: 2), "Kunde A")
        XCTAssertEqual(ProjectBuilder.subgroupPath(ancestors: [probeNode, top, nested], level: 2), [])
    }
}
