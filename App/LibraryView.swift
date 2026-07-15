import SwiftUI
import SkillsManagerCore

enum LibrarySelection: Hashable {
    case skill(String)    // Skill.id
    case plugin(String)   // Plugin.id
    case needsAttention
}

struct LibraryView: View {
    @Environment(InventoryStore.self) private var store
    @State private var selection: LibrarySelection?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detailView
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search skills and commands")
        .toolbar {
            ToolbarItem {
                Button {
                    store.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Re-scan skills and plugins")
                .disabled(store.isLoading)
            }
        }
        .navigationTitle("Skills Manager")
    }

    private var sidebar: some View {
        List(selection: $selection) {
            if !filteredPlugins.isEmpty {
                Section("Plugins") {
                    // Expandable (spec §5.1): bundled skills are selectable rows
                    // so each gets its full cheat sheet, not just a chip.
                    ForEach(filteredPlugins) { plugin in
                        DisclosureGroup {
                            ForEach(plugin.skills) { skill in
                                SkillRow(skill: skill).tag(LibrarySelection.skill(skill.id))
                            }
                        } label: {
                            PluginRow(plugin: plugin).tag(LibrarySelection.plugin(plugin.id))
                        }
                    }
                }
            }
            if !filteredPersonal.isEmpty {
                Section("Your Skills") {
                    ForEach(filteredPersonal) { skill in
                        SkillRow(skill: skill).tag(LibrarySelection.skill(skill.id))
                    }
                }
            }
            if !filteredShared.isEmpty {
                Section("Shared Skills") {
                    ForEach(filteredShared) { skill in
                        SkillRow(skill: skill).tag(LibrarySelection.skill(skill.id))
                    }
                }
            }
            if !store.inventory.issues.isEmpty {
                Section {
                    Label("Needs Attention (\(store.inventory.issues.count))",
                          systemImage: "exclamationmark.triangle")
                        .tag(LibrarySelection.needsAttention)
                }
            }
        }
        .overlay {
            if isEmptyLibrary {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Skills Found" : "No Results",
                    systemImage: searchText.isEmpty ? "sparkles" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Nothing found in ~/.claude or ~/.agents yet."
                        : "Nothing matches “\(searchText)”."))
            }
        }
    }

    private var isEmptyLibrary: Bool {
        filteredPlugins.isEmpty && filteredPersonal.isEmpty
            && filteredShared.isEmpty && store.inventory.issues.isEmpty
    }

    // Task 15 replaces this placeholder with the real detail views.
    @ViewBuilder
    private var detailView: some View {
        ContentUnavailableView(
            "Select an Item",
            systemImage: "sidebar.left",
            description: Text("Choose a skill or plugin to see how to use it."))
    }

    // MARK: Filtering

    private var filteredPlugins: [Plugin] {
        store.inventory.plugins.filter { matches($0) }
    }
    private var filteredPersonal: [Skill] {
        store.inventory.personalSkills.filter { matches($0) }
    }
    private var filteredShared: [Skill] {
        store.inventory.sharedSkills.filter { matches($0) }
    }

    private func matches(_ skill: Skill) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.localizedLowercase
        return skill.displayName.localizedLowercase.contains(q)
            || (skill.summary?.localizedLowercase.contains(q) ?? false)
            || Invocation.string(for: skill).localizedLowercase.contains(q)
    }

    private func matches(_ plugin: Plugin) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.localizedLowercase
        return plugin.name.localizedLowercase.contains(q)
            || plugin.skills.contains { matches($0) }
            || plugin.commands.contains {
                $0.name.localizedLowercase.contains(q)
                    || ($0.summary?.localizedLowercase.contains(q) ?? false)
            }
    }
}
