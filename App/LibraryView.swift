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
    @State private var expandedPlugins: Set<String> = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detailView
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search skills and commands")
        .navigationTitle("Skills Manager")
    }

    private var sidebar: some View {
        List(selection: $selection) {
            if !filteredPlugins.isEmpty {
                Section("Plugins") {
                    // Expandable (spec §5.1): bundled skills are selectable rows
                    // so each gets its full cheat sheet, not just a chip.
                    ForEach(filteredPlugins) { plugin in
                        // While searching: always expanded so the matching bundled
                        // skill/command is visible; manual toggling is suspended.
                        // When search clears: manual expansion state is restored.
                        DisclosureGroup(isExpanded: Binding(
                            get: { !searchText.isEmpty || expandedPlugins.contains(plugin.id) },
                            set: { newValue in
                                guard searchText.isEmpty else { return }
                                if newValue {
                                    expandedPlugins.insert(plugin.id)
                                } else {
                                    expandedPlugins.remove(plugin.id)
                                }
                            }
                        )) {
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

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .skill(let id):
            if let skill = allSkills.first(where: { $0.id == id }) {
                SkillDetailView(skill: skill)
            } else {
                missingSelection
            }
        case .plugin(let id):
            if let plugin = store.inventory.plugins.first(where: { $0.id == id }) {
                PluginDetailView(plugin: plugin)
            } else {
                missingSelection
            }
        case .needsAttention:
            NeedsAttentionView(issues: store.inventory.issues)
        case nil:
            ContentUnavailableView(
                "Select an Item",
                systemImage: "sidebar.left",
                description: Text("Choose a skill or plugin to see how to use it."))
        }
    }

    /// Every skill from every source — used to resolve the sidebar selection.
    private var allSkills: [Skill] {
        store.inventory.personalSkills
            + store.inventory.sharedSkills
            + store.inventory.plugins.flatMap(\.skills)
    }

    private var missingSelection: some View {
        ContentUnavailableView(
            "Item No Longer Exists",
            systemImage: "questionmark.folder",
            description: Text("It changed on disk — pick another item."))
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
                    || $0.invocation.localizedLowercase.contains(q)
            }
    }
}
