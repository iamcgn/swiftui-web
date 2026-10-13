// SwiftData (decision 0021, pf-swiftdata) against the Countries app's models and repository,
// in their shapes exactly: `DBModel.Country`, `DBModel.CountryDetails` and `DBModel.Currency`
// with their unique attributes and one-sided `@Relationship(inverse:)` declarations, the
// `@ModelActor` repository's `store(countries:)` (an upsert per fetch), `store(countryDetails:for:)`
// (fresh Currency instances per call, neighbours by a `#Predicate` fetch) and
// `countryDetails(for:)` (a `#Predicate` fetch on the main context), the list's search
// `#Predicate` over `localizedStandardContains` sorted by name, and the `Query+Search` view
// helper (`@Query var query: [T]` assigned through `_query`).
//
// What the tests prove: schema and identity, upsert by the unique attribute (no second row,
// the first instance updated), inverses kept from either side's declaration, delete unlinking,
// predicate/sort/limit fetches, a model actor's save reaching the main context and a
// `@Query`, persistence through the host store (a reopened container has the rows, values and
// relationships; another schema version or bytes that are not a store do not open and are not
// written over; no storage or a refused write is an error, never an in-memory stand-in),
// in-memory containers independent of each other, and one host write per transaction.
//
// Not proven here: the app's own flows end to end (its data endpoint is deprecated, see
// pf-urlsession); SQL semantics, faulting, migrations (a version change empties the store).
import Testing
import SwiftUI
import SwiftData
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)

// MARK: - The app's models, as published

enum DBModel {}

extension DBModel {
    @Model final class Country {
        var name: String
        var translations: [String: String?]
        var population: Int
        var flag: URL?
        @Attribute(.unique) var alpha3Code: String
        @Relationship(inverse: \CountryDetails.neighbors) var neighbors: [CountryDetails] = []

        init(name: String, translations: [String: String?], population: Int, flag: URL? = nil, alpha3Code: String) {
            self.name = name
            self.translations = translations
            self.population = population
            self.flag = flag
            self.alpha3Code = alpha3Code
        }
    }
}

extension DBModel {
    @Model final class CountryDetails {
        @Attribute(.unique) var alpha3Code: String
        var capital: String
        var currencies: [Currency]
        var neighbors: [Country]?

        init(alpha3Code: String, capital: String, currencies: [Currency], neighbors: [Country]) {
            self.alpha3Code = alpha3Code
            self.capital = capital
            self.currencies = currencies
            self.neighbors = neighbors
        }
    }
}

extension DBModel {
    @Model final class Currency {
        @Relationship(inverse: \CountryDetails.currencies) var countries: [CountryDetails] = []
        @Attribute(.unique) var code: String
        var symbol: String?
        var name: String

        init(code: String, symbol: String?, name: String) {
            self.code = code
            self.symbol = symbol
            self.name = name
        }
    }
}

enum ApiModel {
    struct Country: Equatable {
        let name: String
        let translations: [String: String?]
        let population: Int
        let flag: URL?
        let alpha3Code: String
        func dbModel() -> DBModel.Country {
            .init(name: name, translations: translations, population: population, flag: flag, alpha3Code: alpha3Code)
        }
    }
    struct Currency: Equatable {
        let code: String
        let symbol: String?
        let name: String
        func dbModel() -> DBModel.Currency { .init(code: code, symbol: symbol, name: name) }
    }
    struct CountryDetails: Equatable {
        let capital: String
        let currencies: [Currency]
        let borders: [String]?
    }
}

// The app's Swift 5 sources pass a model into the actor's `store(countryDetails:for:)`; this
// Swift 6 test target needs the models marked to do the same (SwiftData's are not Sendable).
extension DBModel.Country: @unchecked Sendable {}
extension DBModel.CountryDetails: @unchecked Sendable {}
extension DBModel.Currency: @unchecked Sendable {}

extension Schema {
    static var appSchema: Schema {
        Schema([DBModel.Country.self, DBModel.CountryDetails.self, DBModel.Currency.self], version: Version(1, 0, 0))
    }
}

// MARK: - The app's repository, as published

@ModelActor
final actor MainDBRepository {}

extension MainDBRepository {
    @MainActor
    func countryDetails(for country: DBModel.Country) async throws -> DBModel.CountryDetails? {
        let alpha3Code = country.alpha3Code
        let fetchDescriptor = FetchDescriptor(predicate: #Predicate<DBModel.CountryDetails> {
            $0.alpha3Code == alpha3Code
        })
        return try modelContainer.mainContext.fetch(fetchDescriptor).first
    }

    func store(countries: [ApiModel.Country]) async throws {
        try modelContext.transaction {
            countries
                .map { $0.dbModel() }
                .forEach {
                    modelContext.insert($0)
                }
        }
    }

    func store(countryDetails: ApiModel.CountryDetails, for country: DBModel.Country) async throws {
        let alpha3Code = country.alpha3Code
        try modelContext.transaction {
            let currencies = countryDetails.currencies.map { $0.dbModel() }
            let neighborsFetch = FetchDescriptor(predicate: #Predicate<DBModel.Country> { countryDBModel in
                countryDetails.borders?.contains(countryDBModel.alpha3Code) == true
            })
            let neighbors = try modelContext.fetch(neighborsFetch)
            currencies.forEach {
                modelContext.insert($0)
            }
            let object = DBModel.CountryDetails(
                alpha3Code: alpha3Code,
                capital: countryDetails.capital,
                currencies: currencies,
                neighbors: neighbors)
            modelContext.insert(object)
        }
    }
}

// MARK: - The app's Query+Search helper, as published

extension View {
    func query<T: PersistentModel>(searchText: String, results: Binding<[T]>, _ builder: @escaping (String) -> Query<T, [T]>) -> some View {
        background {
            QueryViewContainer(searchText: searchText, builder: builder) { _, values in
                results.wrappedValue = values
            }.equatable()
        }
    }
}

private struct QueryViewContainer<T: PersistentModel>: View, Equatable {
    let searchText: String
    let builder: (String) -> Query<T, [T]>
    let results: ([T], [T]) -> Void
    var body: some View {
        QueryView(query: builder(searchText), results: results)
    }
    // `nonisolated` is this Swift 6 test target's spelling; the app's Swift 5 sources write it bare.
    nonisolated static func == (lhs: QueryViewContainer<T>, rhs: QueryViewContainer<T>) -> Bool { lhs.searchText == rhs.searchText }
}

private struct QueryView<T: PersistentModel>: View {
    @Query var query: [T]
    let results: ([T], [T]) -> Void
    init(query: Query<T, [T]>, results: @escaping ([T], [T]) -> Void) {
        _query = query
        self.results = results
    }
    var body: some View {
        Rectangle().hidden().onChange(of: query, initial: true, results)
    }
}

// MARK: - The tests

@Suite(.serialized) struct SwiftDataTests {
    static let countries: [ApiModel.Country] = [
        .init(name: "Finland", translations: ["fi": "Suomi", "de": nil], population: 5_530_000, flag: URL(string: "https://flagcdn.com/w640/fi.jpg"), alpha3Code: "FIN"),
        .init(name: "Sweden", translations: ["sv": "Sverige"], population: 10_400_000, flag: nil, alpha3Code: "SWE"),
        .init(name: "Norway", translations: [:], population: 5_400_000, flag: nil, alpha3Code: "NOR"),
        .init(name: "Poland", translations: ["pl": "Polska"], population: 37_900_000, flag: nil, alpha3Code: "POL"),
    ]
    static let euro = ApiModel.Currency(code: "EUR", symbol: "€", name: "Euro")
    static let krona = ApiModel.Currency(code: "SEK", symbol: "kr", name: "Swedish krona")
    static let finlandDetails = ApiModel.CountryDetails(capital: "Helsinki", currencies: [euro], borders: ["SWE", "NOR", "RUS"])
    static let swedenDetails = ApiModel.CountryDetails(capital: "Stockholm", currencies: [krona, euro], borders: ["FIN", "NOR"])

    /// A fresh in-memory container; names are distinct so tests share nothing.
    nonisolated(unsafe) private static var made = 0
    private func container(inMemory: Bool = true, name: String? = nil, version: Schema.Version = Schema.Version(1, 0, 0)) throws -> ModelContainer {
        Self.made += 1
        let schema = Schema([DBModel.Country.self, DBModel.CountryDetails.self, DBModel.Currency.self], version: version)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(name ?? "test-\(Self.made)", schema: schema, isStoredInMemoryOnly: inMemory)])
    }

    private func settled(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 { if await MainActor.run(body: condition) { return }; await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
    }

    @Test func schemaAndIdentity() throws {
        let schema = Schema.appSchema
        #expect(schema.entityNames == ["Country", "CountryDetails", "Currency"])
        #expect(schema.version == Schema.Version(1, 0, 0))

        let country = DBModel.Country._persistedProperties
        #expect(country.map(\.name) == ["name", "translations", "population", "flag", "alpha3Code", "neighbors"])
        #expect(country.first { $0.name == "alpha3Code" }?.isUnique == true)
        #expect(country.first { $0.name == "name" }?.isUnique == false)
        let neighbors = try #require(country.first { $0.name == "neighbors" })
        #expect(neighbors.kind == .toMany && neighbors.relatedEntity == "CountryDetails" && neighbors.inverse == "neighbors")
        let details = DBModel.CountryDetails._persistedProperties
        let currencies = try #require(details.first { $0.name == "currencies" })
        #expect(currencies.kind == .toMany && currencies.relatedEntity == "Currency" && currencies.inverse == nil)   // declared on Currency's side only
        let detailsNeighbors = try #require(details.first { $0.name == "neighbors" })
        #expect(detailsNeighbors.kind == .toMany && detailsNeighbors.inverse == nil)
        #expect(DBModel.Currency._persistedProperties.first { $0.name == "countries" }?.inverse == "currencies")

        let container = try container()
        let context = ModelContext(container)
        let finland = Self.countries[0].dbModel()
        #expect(finland.persistentModelID.isTemporary)
        #expect(finland.modelContext == nil)
        context.insert(finland)
        #expect(!finland.persistentModelID.isTemporary)
        #expect(finland.persistentModelID.entityName == "Country")
        #expect(finland.modelContext === context)
        #expect(finland.id == finland.persistentModelID)
        let again = try #require(context.registeredModel(for: finland.persistentModelID) as DBModel.Country?)
        #expect(again === finland)
        #expect(finland == again)
        #expect(finland != Self.countries[1].dbModel())
        #expect(Set([finland, again]).count == 1)
        #expect(context.model(for: finland.persistentModelID) === finland)
    }

    @Test func storeCountriesIsAnUpsert() async throws {
        let container = try container()
        let sut = MainDBRepository(modelContainer: container)
        try await sut.store(countries: Self.countries)
        let results = try await MainActor.run { try container.mainContext.fetch(FetchDescriptor<DBModel.Country>()) }
        #expect(results.count == Self.countries.count)
        #expect(results.map(\.name) == ["Finland", "Sweden", "Norway", "Poland"])   // insertion order without a sort
        #expect(results[0].translations == ["fi": "Suomi", "de": nil])
        #expect(results[0].flag?.absoluteString == "https://flagcdn.com/w640/fi.jpg")
        #expect(results[1].flag == nil)
        let ids = results.map(\.persistentModelID)
        #expect(Set(ids).count == 4)

        // A second fetch of the same countries (the app stores every list it loads): the rows
        // update, no second Finland, the main context's instance keeps its identity and value.
        var updated = Self.countries
        updated[0] = .init(name: "Finland", translations: ["fi": "Suomi"], population: 5_600_000, flag: nil, alpha3Code: "FIN")
        try await sut.store(countries: updated)
        let after = try await MainActor.run { try container.mainContext.fetch(FetchDescriptor<DBModel.Country>()) }
        #expect(after.count == 4)
        #expect(after.map(\.persistentModelID) == ids)
        #expect(after[0] === results[0])
        #expect(after[0].population == 5_600_000)
        #expect(after[0].translations == ["fi": "Suomi"])
        #expect(after[0].flag == nil)
        let count = try await MainActor.run { try container.mainContext.fetchCount(FetchDescriptor<DBModel.Country>(predicate: #Predicate { $0.alpha3Code == "FIN" })) }
        #expect(count == 1)
    }

    @Test func storeCountryDetailsKeepsBothSidesOfEveryRelationship() async throws {
        let container = try container()
        let sut = MainDBRepository(modelContainer: container)
        try await sut.store(countries: Self.countries)
        let finland = try await MainActor.run { try #require(try container.mainContext.fetch(FetchDescriptor<DBModel.Country>(predicate: #Predicate { $0.alpha3Code == "FIN" })).first) }
        try await sut.store(countryDetails: Self.finlandDetails, for: finland)

        let (details, currencies, countries) = try await MainActor.run {
            (try container.mainContext.fetch(FetchDescriptor<DBModel.CountryDetails>()),
             try container.mainContext.fetch(FetchDescriptor<DBModel.Currency>()),
             try container.mainContext.fetch(FetchDescriptor<DBModel.Country>()))
        }
        let stored = try #require(details.first)
        #expect(details.count == 1)
        #expect(stored.capital == "Helsinki")
        #expect(stored.currencies.map(\.code) == ["EUR"])
        // The inverse declared on Currency alone: the currency lists the details.
        #expect(currencies.map(\.code) == ["EUR"])
        #expect(currencies[0].countries.map(\.alpha3Code) == ["FIN"])
        #expect(currencies[0].countries.first === stored)
        // Neighbours by the predicate over `borders` (RUS is not stored: not a neighbour), and
        // the inverse declared on Country alone: each neighbour lists the details.
        #expect(stored.neighbors?.map(\.alpha3Code).sorted() == ["NOR", "SWE"])
        let sweden = try #require(countries.first { $0.alpha3Code == "SWE" })
        let norway = try #require(countries.first { $0.alpha3Code == "NOR" })
        #expect(sweden.neighbors.map(\.alpha3Code) == ["FIN"])
        #expect(norway.neighbors.map(\.alpha3Code) == ["FIN"])
        #expect(countries.first { $0.alpha3Code == "POL" }?.neighbors.isEmpty == true)
        #expect(finland.neighbors.isEmpty)

        // Sweden's details share the euro: the repository makes a fresh Currency("EUR") and
        // inserts it — the row is the one euro, now listing both details.
        try await sut.store(countryDetails: Self.swedenDetails, for: sweden)
        let (details2, currencies2) = try await MainActor.run {
            (try container.mainContext.fetch(FetchDescriptor<DBModel.CountryDetails>()), try container.mainContext.fetch(FetchDescriptor<DBModel.Currency>()))
        }
        #expect(details2.count == 2)
        #expect(currencies2.map(\.code).sorted() == ["EUR", "SEK"])
        let euro = try #require(currencies2.first { $0.code == "EUR" })
        #expect(euro.countries.map(\.alpha3Code).sorted() == ["FIN", "SWE"])
        let swedenDetails = try #require(details2.first { $0.alpha3Code == "SWE" })
        #expect(swedenDetails.currencies.map(\.code) == ["SEK", "EUR"])
        #expect(swedenDetails.currencies.contains { $0 === euro })
        #expect(swedenDetails.neighbors?.map(\.alpha3Code).sorted() == ["FIN", "NOR"])
        #expect(finland.neighbors.map(\.alpha3Code) == ["SWE"])
        #expect(norway.neighbors.map(\.alpha3Code).sorted() == ["FIN", "SWE"])

        // Storing Finland's details again (a second visit) updates the one row.
        try await sut.store(countryDetails: .init(capital: "Helsingfors", currencies: [Self.euro], borders: ["SWE"]), for: finland)
        let details3 = try await MainActor.run { try container.mainContext.fetch(FetchDescriptor<DBModel.CountryDetails>()) }
        #expect(details3.count == 2)
        #expect(details3.first { $0.alpha3Code == "FIN" } === stored)
        #expect(stored.capital == "Helsingfors")
        #expect(stored.neighbors?.map(\.alpha3Code) == ["SWE"])
        #expect(norway.neighbors.map(\.alpha3Code) == ["SWE"])   // no longer Finland's neighbour
        #expect(euro.countries.count == 2)
        let currencyCount = try await MainActor.run { try container.mainContext.fetchCount(FetchDescriptor<DBModel.Currency>()) }
        #expect(currencyCount == 2)
    }

    @Test func countryDetailsForCountry() async throws {
        let container = try container()
        let sut = MainDBRepository(modelContainer: container)
        let country = Self.countries[0].dbModel()   // the app's test passes an unregistered model
        try await sut.store(countryDetails: Self.finlandDetails, for: country)
        let stored = try #require(try await sut.countryDetails(for: country))
        #expect(stored.capital == Self.finlandDetails.capital)
        #expect(stored.currencies.count == Self.finlandDetails.currencies.count)
        let none = try await sut.countryDetails(for: Self.countries[1].dbModel())
        #expect(none == nil)
    }

    @Test @MainActor func settingARelationshipSetsItsInverse() throws {
        let container = try container()
        let context = container.mainContext
        let finland = Self.countries[0].dbModel(), sweden = Self.countries[1].dbModel()
        context.insert(finland); context.insert(sweden)
        let euro = DBModel.Currency(code: "EUR", symbol: "€", name: "Euro")
        let details = DBModel.CountryDetails(alpha3Code: "FIN", capital: "Helsinki", currencies: [], neighbors: [])
        context.insert(details)
        // Through the setters, from each side.
        details.currencies = [euro]
        #expect(euro.modelContext === context)   // the graph came along
        #expect(euro.countries.first === details)
        details.neighbors = [sweden]
        #expect(sweden.neighbors.first === details)
        sweden.neighbors = []
        #expect(details.neighbors?.isEmpty == true)
        finland.neighbors = [details]
        #expect(details.neighbors?.first === finland)
        euro.countries = []
        #expect(details.currencies.isEmpty)
        // Observation: a change to a stored property is seen through the registrar.
        nonisolated(unsafe) var observed = false
        withObservationTracking { _ = details.capital } onChange: { observed = true }
        details.capital = "Helsingfors"
        #expect(observed)
    }

    @Test @MainActor func deleteUnlinksAndRemovesTheRow() async throws {
        let container = try container()
        let sut = MainDBRepository(modelContainer: container)
        try await sut.store(countries: Self.countries)
        let finland = try #require(try container.mainContext.fetch(FetchDescriptor<DBModel.Country>(predicate: #Predicate { $0.alpha3Code == "FIN" })).first)
        try await sut.store(countryDetails: Self.finlandDetails, for: finland)
        let context = container.mainContext
        let euro = try #require(try context.fetch(FetchDescriptor<DBModel.Currency>()).first)
        let details = try #require(try context.fetch(FetchDescriptor<DBModel.CountryDetails>()).first)
        let sweden = try #require(try context.fetch(FetchDescriptor<DBModel.Country>(predicate: #Predicate { $0.alpha3Code == "SWE" })).first)
        #expect(details.currencies.count == 1 && sweden.neighbors.count == 1)

        context.delete(euro)
        #expect(euro.isDeleted && euro.modelContext == nil)
        #expect(details.currencies.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<DBModel.Currency>()) == 0)
        context.delete(details)
        #expect(sweden.neighbors.isEmpty)
        #expect(try context.fetch(FetchDescriptor<DBModel.CountryDetails>()).isEmpty)
        // Gone for the actor's context too, after its own fetch.
        let fromActor = try await sut.countryDetails(for: finland)
        #expect(fromActor == nil)
        try context.delete(model: DBModel.Country.self, where: #Predicate { $0.population < 6_000_000 })
        #expect(try context.fetch(FetchDescriptor<DBModel.Country>()).map(\.alpha3Code) == ["SWE", "POL"])
        try context.delete(model: DBModel.Country.self)
        #expect(try context.fetchCount(FetchDescriptor<DBModel.Country>()) == 0)
    }

    @Test @MainActor func predicateSortLimitAndOffset() throws {
        let container = try container()
        let context = container.mainContext
        for country in Self.countries { context.insert(country.dbModel()) }

        // The list's search predicate.
        func matching(_ search: String) throws -> [String] {
            try context.fetch(FetchDescriptor(predicate: #Predicate<DBModel.Country> { country in
                if search.isEmpty {
                    return true
                } else {
                    return country.name.localizedStandardContains(search)
                }
            }, sortBy: [SortDescriptor(\DBModel.Country.name)])).map(\.name)
        }
        #expect(try matching("") == ["Finland", "Norway", "Poland", "Sweden"])
        #expect(try matching("LAN") == ["Finland", "Poland"])
        #expect(try matching("é") == ["Sweden"])   // diacritic-insensitive, as Foundation's
        #expect(try matching("swe") == ["Sweden"])

        var descriptor = FetchDescriptor<DBModel.Country>(sortBy: [SortDescriptor(\.population, order: .reverse)])
        #expect(try context.fetch(descriptor).map(\.alpha3Code) == ["POL", "SWE", "FIN", "NOR"])
        descriptor.fetchLimit = 2
        #expect(try context.fetch(descriptor).map(\.alpha3Code) == ["POL", "SWE"])
        descriptor.fetchOffset = 1
        #expect(try context.fetch(descriptor).map(\.alpha3Code) == ["SWE", "FIN"])
        // An optional sort key: nils first in forward order.
        let flags = try context.fetch(FetchDescriptor<DBModel.Country>(sortBy: [SortDescriptor(\DBModel.Country.flag?.absoluteString), SortDescriptor(\DBModel.Country.name)]))
        #expect(flags.map(\.alpha3Code) == ["NOR", "POL", "SWE", "FIN"])
        #expect(try context.fetchCount(FetchDescriptor<DBModel.Country>(predicate: #Predicate { $0.population > 10_000_000 })) == 2)
    }

    @Test func reopenedContainerHasTheRowsValuesAndRelationships() async throws {
        // The host store: what the browser keeps in localStorage, here a dictionary.
        nonisolated(unsafe) var saved: [String: String] = [:]
        nonisolated(unsafe) var writes = 0
        _ModelStore.Host.store = (load: { saved[$0] }, save: { name, json in saved[name] = json; writes += 1 })
        defer { _ModelStore.Host.store = nil }
        let name = "reopen-\(Int.random(in: 0..<1_000_000))"

        var ids: [String: PersistentIdentifier] = [:]
        do {
            let container = try container(inMemory: false, name: name)
            let sut = MainDBRepository(modelContainer: container)
            try await sut.store(countries: Self.countries)
            let finland = try await MainActor.run { try #require(try container.mainContext.fetch(FetchDescriptor<DBModel.Country>(predicate: #Predicate { $0.alpha3Code == "FIN" })).first) }
            try await sut.store(countryDetails: Self.finlandDetails, for: finland)
            let all = try await MainActor.run { try container.mainContext.fetch(FetchDescriptor<DBModel.Country>()) }
            for country in all { ids[country.alpha3Code] = country.persistentModelID }
            #expect(saved[name] != nil)
        }
        #expect(writes == 2)   // one per transaction

        let reopened = try container(inMemory: false, name: name)
        let (countries, details, currencies) = try await MainActor.run {
            (try reopened.mainContext.fetch(FetchDescriptor<DBModel.Country>(sortBy: [SortDescriptor(\.name)])),
             try reopened.mainContext.fetch(FetchDescriptor<DBModel.CountryDetails>()),
             try reopened.mainContext.fetch(FetchDescriptor<DBModel.Currency>()))
        }
        #expect(countries.map(\.alpha3Code) == ["FIN", "NOR", "POL", "SWE"])
        let finland = try #require(countries.first { $0.alpha3Code == "FIN" })
        #expect(finland.persistentModelID == ids["FIN"])
        #expect(!finland.persistentModelID.isTemporary)
        #expect(finland.population == 5_530_000)
        #expect(finland.translations == ["fi": "Suomi", "de": nil])
        #expect(finland.flag?.absoluteString == "https://flagcdn.com/w640/fi.jpg")
        #expect(countries.first { $0.alpha3Code == "SWE" }?.flag == nil)
        let stored = try #require(details.first)
        #expect(stored.capital == "Helsinki")
        #expect(stored.currencies.map(\.code) == ["EUR"])
        #expect(stored.currencies.first === currencies.first)
        #expect(currencies.first?.symbol == "€")
        #expect(currencies.first?.countries.first === stored)
        #expect(stored.neighbors?.map(\.alpha3Code).sorted() == ["NOR", "SWE"])
        #expect(countries.first { $0.alpha3Code == "SWE" }?.neighbors.first === stored)
        #expect(finland.neighbors.isEmpty)
        let pending = await MainActor.run { reopened.mainContext.hasChanges }
        #expect(!finland.hasChanges && !pending)

        // A new row in the reopened store gets an identifier after the stored ones.
        let numbers = Set(countries.map(\.persistentModelID.description))
        let iceland = DBModel.Country(name: "Iceland", translations: [:], population: 380_000, alpha3Code: "ISL")
        await MainActor.run { reopened.mainContext.insert(iceland); try? reopened.mainContext.save() }
        #expect(!numbers.contains(iceland.persistentModelID.description))
        let third = try container(inMemory: false, name: name)
        let count = try await MainActor.run { try third.mainContext.fetchCount(FetchDescriptor<DBModel.Country>()) }
        #expect(count == 5)

        // Another schema version does not open the store (no migration here) and leaves its
        // bytes as they were; bytes that are not a store document do the same.
        let bytes = try #require(saved[name])
        let writesBefore = writes
        #expect(throws: SwiftDataError.self) { try container(inMemory: false, name: name, version: Schema.Version(2, 0, 0)) }
        do { _ = try container(inMemory: false, name: name, version: Schema.Version(2, 0, 0)) } catch SwiftDataError.incompatibleSchema(let store, let stored, let expected) {
            #expect(store == name && stored == "1.0.0" && expected == "2.0.0")
        }
        #expect(saved[name] == bytes && writes == writesBefore)
        saved["broken"] = "not json"
        do { _ = try container(inMemory: false, name: "broken") } catch SwiftDataError.corruptStore(let store) { #expect(store == "broken") }
        #expect(saved["broken"] == "not json")
        let fifth = try container(inMemory: false, name: name)   // the right version still opens it
        let fifthCount = try await MainActor.run { try fifth.mainContext.fetchCount(FetchDescriptor<DBModel.Country>()) }
        #expect(fifthCount == 5)
        // `deleteAllData` empties it for the next open.
        await MainActor.run { third.deleteAllData() }
        let fourth = try container(inMemory: false, name: name)
        let fourthCount = try await MainActor.run { try fourth.mainContext.fetchCount(FetchDescriptor<DBModel.Country>()) }
        #expect(fourthCount == 0)
    }

    @Test @MainActor func persistentStorageThatIsMissingOrRefusesIsAnError() throws {
        // No host storage bound: a persistent configuration does not open (nothing in-memory
        // stands in for it), an in-memory one does.
        _ModelStore.Host.store = nil
        do { _ = try container(inMemory: false, name: "nohost"); Issue.record("opened without storage") } catch SwiftDataError.storageUnavailable(let store) { #expect(store == "nohost") }
        _ = try container(inMemory: true, name: "nohost")

        // The host refuses a write (a spent quota): the save throws and the changes stay pending.
        nonisolated(unsafe) var refuse = false
        nonisolated(unsafe) var kept: [String: String] = [:]
        struct Quota: Error {}
        _ModelStore.Host.store = (load: { kept[$0] }, save: { name, json in if refuse { throw Quota() }; kept[name] = json })
        defer { _ModelStore.Host.store = nil }
        let container = try container(inMemory: false, name: "refusing")
        let context = container.mainContext
        context.autosaveEnabled = false
        let finland = Self.countries[0].dbModel()
        context.insert(finland)
        refuse = true
        do { try context.save(); Issue.record("saved through a refused write") } catch SwiftDataError.saveFailed(let store, let reason) {
            #expect(store == "refusing" && reason.contains("Quota"))
        }
        #expect(context.hasChanges && finland.hasChanges)
        #expect(kept["refusing"] == nil)
        refuse = false
        try context.save()
        #expect(!context.hasChanges && !finland.hasChanges)
        #expect(kept["refusing"] != nil)
    }

    @Test @MainActor func inMemoryContainersAreIndependent() throws {
        // Two in-memory containers, the same name (the app's `stub` and `mock` containers are
        // made again per test): each holds its own rows, and the host store never sees them.
        nonisolated(unsafe) var hostSaves = 0
        _ModelStore.Host.store = (load: { _ in nil }, save: { _, _ in hostSaves += 1 })
        defer { _ModelStore.Host.store = nil }
        let a = try ModelContainer(for: Schema.appSchema, configurations: [ModelConfiguration("stub", schema: .appSchema, isStoredInMemoryOnly: true)])
        let b = try ModelContainer(for: Schema.appSchema, configurations: [ModelConfiguration("stub", schema: .appSchema, isStoredInMemoryOnly: true)])
        #expect(a.configurations.first?.name == "stub" && a.configurations.first?.isStoredInMemoryOnly == true)
        a.mainContext.insert(Self.countries[0].dbModel())
        try a.mainContext.save()
        #expect(try a.mainContext.fetchCount(FetchDescriptor<DBModel.Country>()) == 1)
        #expect(try b.mainContext.fetchCount(FetchDescriptor<DBModel.Country>()) == 0)
        b.mainContext.insert(Self.countries[1].dbModel())
        try b.mainContext.save()
        #expect(try a.mainContext.fetch(FetchDescriptor<DBModel.Country>()).map(\.alpha3Code) == ["FIN"])
        #expect(try b.mainContext.fetch(FetchDescriptor<DBModel.Country>()).map(\.alpha3Code) == ["SWE"])
        let c = try ModelContainer(for: Schema.appSchema, configurations: [ModelConfiguration("stub", schema: .appSchema, isStoredInMemoryOnly: true)])
        #expect(try c.mainContext.fetchCount(FetchDescriptor<DBModel.Country>()) == 0)
        #expect(hostSaves == 0)
    }

    @Test @MainActor func autosaveWritesOncePerTransaction() throws {
        nonisolated(unsafe) var writes = 0
        _ModelStore.Host.store = (load: { _ in nil }, save: { _, _ in writes += 1 })
        defer { _ModelStore.Host.store = nil }
        let container = try container(inMemory: false, name: "autosave-\(Int.random(in: 0..<1_000_000))")
        let context = container.mainContext
        try context.transaction {
            for country in Self.countries { context.insert(country.dbModel()) }
        }
        #expect(writes == 1)
        #expect(!context.hasChanges)
        // Outside a transaction every change autosaves.
        let finland = try #require(try context.fetch(FetchDescriptor<DBModel.Country>()).first)
        finland.population += 1
        #expect(writes == 2)
        context.autosaveEnabled = false
        finland.population += 1
        #expect(writes == 2)
        #expect(context.hasChanges && finland.hasChanges)
        try context.save()
        #expect(writes == 3)
        #expect(!finland.hasChanges)
    }

    struct CountryNames: View {
        @Query(sort: \DBModel.Country.name) private var countries: [DBModel.Country]
        var body: some View {
            VStack { ForEach(countries) { Text($0.name) } }
        }
    }

    struct Searching: View {
        @State var countries: [DBModel.Country] = []
        var searchText: String
        var body: some View {
            Text(countries.map(\.alpha3Code).joined(separator: ","))
                .query(searchText: searchText, results: $countries) { search in
                    Query(filter: #Predicate<DBModel.Country> { country in
                        if search.isEmpty {
                            return true
                        } else {
                            return country.name.localizedStandardContains(search)
                        }
                    }, sort: \DBModel.Country.name)
                }
        }
    }

    @MainActor private func texts(_ runtime: Runtime) -> [String] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
    }

    @Test @MainActor func queryFollowsTheModelActorsSaves() async throws {
        let container = try container()
        let runtime = Runtime()
        runtime.mount(CountryNames().modelContainer(container))
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == [])
        let sut = MainDBRepository(modelContainer: container)
        try await sut.store(countries: Self.countries)
        // The actor saved off the main actor: the `@Query` re-reads at the main actor's next turn.
        await settled { runtime.layout(in: CGSize(width: 320, height: 400)); return texts(runtime).count == 4 }
        #expect(texts(runtime) == ["Finland", "Norway", "Poland", "Sweden"])
        // A save on the main context re-reads the body in the same turn.
        container.mainContext.insert(DBModel.Country(name: "Iceland", translations: [:], population: 380_000, alpha3Code: "ISL"))
        runtime.layout(in: CGSize(width: 320, height: 400))
        #expect(texts(runtime) == ["Finland", "Iceland", "Norway", "Poland", "Sweden"])
        // An update through the actor reaches the registered instance the view shows.
        try await sut.store(countries: [.init(name: "Suomi", translations: [:], population: 1, flag: nil, alpha3Code: "FIN")])
        await settled { runtime.layout(in: CGSize(width: 320, height: 400)); return texts(runtime).first == "Iceland" }
        #expect(texts(runtime) == ["Iceland", "Norway", "Poland", "Suomi", "Sweden"])
    }

    @Test @MainActor func querySearchHelperRecreatesTheQueryPerSearchText() throws {
        let container = try container()
        for country in Self.countries { container.mainContext.insert(country.dbModel()) }
        let runtime = Runtime()
        runtime.mount(Searching(searchText: "").modelContainer(container))
        runtime.layout(in: CGSize(width: 320, height: 100))
        #expect(texts(runtime) == ["FIN,NOR,POL,SWE"])
        runtime.mount(Searching(searchText: "lan").modelContainer(container))
        runtime.layout(in: CGSize(width: 320, height: 100))
        #expect(texts(runtime) == ["FIN,POL"])
        runtime.mount(Searching(searchText: "zz").modelContainer(container))
        runtime.layout(in: CGSize(width: 320, height: 100))
        #expect(texts(runtime) == [""])
    }
}
#endif
