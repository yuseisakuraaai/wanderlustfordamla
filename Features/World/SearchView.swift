import SwiftUI

struct SearchView: View {
    @ObservedObject var tripStore: TripStore
    var onCountrySelect: ((Country) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var countryResults: [Country] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearchQuery = ""

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyQueryContent
                } else if countryResults.isEmpty {
                    noResultsContent
                } else {
                    resultsContent
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Search"))
            .toolbarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(WanderlustL10n.string("Search country…", table: .world))
            )
            .onChange(of: query) { _, new in scheduleSearch(new) }
            .onDisappear {
                searchTask?.cancel()
                searchTask = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .tint(.blue)
                        .fontWeight(.regular)
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        searchSectionHeader(String(localized: "Countries"))

        ForEach(countryResults) { country in
            countryResultRow(country)
        }
    }

    // Show visited countries when nothing is typed yet
    @ViewBuilder
    private var emptyQueryContent: some View {
        let visited = VisitedCountryAggregator.mappableCountries(in: tripStore.trips)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        if !visited.isEmpty {
            searchSectionHeader(WanderlustL10n.string("Visited Countries", table: .world))

            ForEach(visited) { country in
                countryResultRow(country)
            }
        }
    }

    private func searchSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func countryResultRow(_ country: Country) -> some View {
        if let onCountrySelect {
            Button {
                onCountrySelect(country)
                dismiss()
            } label: {
                CountrySearchRow(country: country)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            NavigationLink {
                SearchCountryDetailView(country: country, tripStore: tripStore)
            } label: {
                CountrySearchRow(country: country)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var noResultsContent: some View {
        Section {
            VStack(spacing: 18) {
                Image(systemName: "magnifyingglass")
                    .wanderlustDecorativeFont(42, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 72, height: 72)
                    .wanderlustGlassSurface(radius: WanderlustRadius.xLarge)

                VStack(spacing: 8) {
                    Text(WanderlustL10n.string("No Countries Found", table: .errors))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(String(localized: "Try a different country name."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: 0,
                    trailing: 0
                )
            )
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Logic

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSearchImmediately = trimmed.count < activeSearchQuery.count
        activeSearchQuery = trimmed
        guard !trimmed.isEmpty else {
            countryResults = []
            return
        }

        searchTask = Task {
            if !shouldSearchImmediately {
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard !Task.isCancelled else { return }
            let results = await GeoJSONLoader.shared.searchCountriesOffMain(query: trimmed, limit: 10)
            await MainActor.run {
                guard !Task.isCancelled,
                      activeSearchQuery == trimmed else { return }
                countryResults = results
            }
        }
    }

}

// MARK: - Row Views

private struct CountrySearchRow: View {
    let country: Country

    var body: some View {
        HStack(spacing: 16) {
            Text(country.flagEmoji)
                .font(.title2)
                .frame(width: 40, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(country.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(WanderlustL10n.continentName(country.continent))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
    }
}

// MARK: - Country Detail (from Search)

struct SearchCountryDetailView: View {
    let country: Country
    @ObservedObject var tripStore: TripStore

    private var trips: [Trip] {
        tripStore.trips(visitingCountry: country.isoCode)
    }

    private var cities: [VisitedCity] {
        tripStore.cities(inCountry: country.isoCode)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    Text(country.flagEmoji)
                        .wanderlustDecorativeFont(56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(country.displayName).font(.title2.bold())
                        Text(WanderlustL10n.continentName(country.continent)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            if !cities.isEmpty {
                Section(PluralizationFormatter.cities(cities.count)) {
                    ForEach(cities) { city in
                        HStack {
                            Text(city.localizedName).font(.headline)
                            Spacer()
                            if let arrival = city.arrivalDate {
                                Text(WanderlustDateFormatter.date(arrival))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !trips.isEmpty {
                Section(PluralizationFormatter.trips(trips.count)) {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripDetailView(tripID: trip.id, tripStore: tripStore)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.displayTitle).font(.headline)
                                Text(trip.dateRangeText).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if trips.isEmpty && cities.isEmpty {
                Section {
                    Text(PluralizationFormatter.noTripsRecorded(to: country.displayName))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(country.displayName)
        .toolbarTitleDisplayMode(.large)
    }
}
