// SwiftData models in the shape PomPadDo declares them: classes that are not final, an enum
// attribute with a default, an optional Codable enum, and relationships both with and without
// `@Relationship` (a to-one and a to-many typed only as another model).
//
// What the tests prove: `@Model` on a class that is not final conforms (its `_make` returns
// `Self`); the property table gives an enum or Codable value an attribute and another model, or
// an array of them, a relationship, whatever the declaration says; and every one of them comes
// back from the host store with its value; a configuration that names a CloudKit database
// opens the app's own store.
import Testing
import SwiftUI
import SwiftData
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)

enum InferredRepeat: String, Codable, CaseIterable { case none, daily, weekly }
enum InferredUnit: String, Codable { case days, weeks }

@Model
class InferredProject {
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \InferredTask.project)
    var tasks: [InferredTask]? = []
    var groups: [InferredGroup]? = []
    init(name: String) { self.name = name }
}

@Model
class InferredGroup {
    var title: String = ""
    init(title: String) { self.title = title }
}

@Model
class InferredTask {
    var name: String = ""
    var repeation: InferredRepeat = InferredRepeat.none
    var unit: InferredUnit? = InferredUnit.days
    var project: InferredProject?
    init(name: String) { self.name = name }
}

@Suite(.serialized) struct SwiftDataInferredKindsTests {
    @Test func propertyKindsComeFromTheTypes() {
        let task = Dictionary(uniqueKeysWithValues: InferredTask._persistedProperties.map { ($0.name, $0) })
        #expect(task["repeation"]?.kind == .attribute)
        #expect(task["unit"]?.kind == .attribute)
        #expect(task["project"]?.kind == .toOne)
        #expect(task["project"]?.relatedEntity == "InferredProject")
        let project = Dictionary(uniqueKeysWithValues: InferredProject._persistedProperties.map { ($0.name, $0) })
        #expect(project["tasks"]?.kind == .toMany)
        #expect(project["groups"]?.kind == .toMany)
        #expect(project["groups"]?.relatedEntity == "InferredGroup")
    }

    @Test @MainActor func aConfigurationNamingCloudKitOpensTheAppsOwnStore() throws {
        let schema = Schema([InferredProject.self, InferredTask.self, InferredGroup.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = try ModelContainer(for: schema, configurations: [configuration]).mainContext
        context.insert(InferredTask(name: "One"))
        #expect(try context.fetchCount(FetchDescriptor<InferredTask>()) == 1)
    }

    @Test @MainActor func everyKindComesBackFromTheStore() throws {
        nonisolated(unsafe) var saved: [String: String] = [:]
        _ModelStore.Host.store = (load: { saved[$0] }, save: { name, json in saved[name] = json })
        defer { _ModelStore.Host.store = nil }
        let name = "inferred-\(Int.random(in: 0..<1_000_000))"
        let schema = Schema([InferredProject.self, InferredTask.self, InferredGroup.self])
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: false)])
        }

        do {
            let context = try open().mainContext
            let project = InferredProject(name: "Home")
            let group = InferredGroup(title: "Chores")
            let weekly = InferredTask(name: "Water plants")
            weekly.repeation = .weekly
            weekly.unit = .weeks
            let once = InferredTask(name: "Fix the tap")
            once.unit = nil
            context.insert(project)
            project.groups = [group]
            weekly.project = project
            once.project = project
            try context.save()
            #expect(project.tasks?.count == 2)   // the inverse, set from the task's side
        }

        let context = try open().mainContext
        let tasks = try context.fetch(FetchDescriptor<InferredTask>(sortBy: [SortDescriptor(\.name)]))
        #expect(tasks.map(\.name) == ["Fix the tap", "Water plants"])
        #expect(tasks.map(\.repeation) == [.none, .weekly])
        #expect(tasks.map(\.unit) == [nil, .weeks])
        let project = try #require(tasks.first?.project)
        #expect(project.name == "Home")
        #expect(tasks.last?.project === project)
        #expect(project.groups?.map(\.title) == ["Chores"])
        #expect(Set(project.tasks?.map(\.name) ?? []) == ["Fix the tap", "Water plants"])
    }
}

#endif
