import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SkillsManagerCore

enum LibrarySelection: Hashable {
    case entry(String)    // SkillEntry.id
    case plugin(String)   // PluginEntry.id
    case skill(String)    // Skill.id — a skill inside a plugin
    case note(String)     // NoteFile.id
    case needsAttention
}

struct LibraryView: View {
    @Environment(InventoryStore.self) private var store
    @Environment(UsageStore.self) private var usage
    @State private var selection: LibrarySelection?
    @State private var searchText = ""
    @State private var expandedPlugins: Set<String> = []
    @State private var builtInExpanded = false
    @State private var expandedNotes: Set<String> = []
    @State private var addFolderMessage: String?
    @State private var showInstall = false
    @State private var dismissedAccessNote = false
    @State private var installModel = InstallSheetModel(
        paths: ClaudePaths(), github: URLSessionGitHubClient(),
        guesser: FoundationModelsGuesser.isAvailable ? FoundationModelsGuesser() : NoopGuesser(),
        runner: ShellCommandRunner())

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detailView
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search skills, commands, and projects")
        .navigationTitle("Skills Manager")
        .toolbar {
            if usage.isEnabled {
                ToolbarItem {
                    Menu {
                        Picker("Sort by", selection: Binding(get: { usage.sort }, set: { usage.sort = $0 })) {
                            ForEach(UsageSort.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Picker("Count", selection: Binding(get: { usage.window }, set: { usage.window = $0 })) {
                            ForEach(UsageWindow.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort skills by name or by how you use them")
                }
            }
            ToolbarItem {
                Button { showInstall = true } label: { Label("Install", systemImage: "plus") }
                    .help("Install a skill or plugin from a link or command")
            }
        }
        // One sheet modifier: two on the same view can't present at once, so
        // ⌘N during the first-run note would silently do nothing.
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .install:
                InstallSheet(model: installModel) { showInstall = false }
            case .projectAccess:
                ProjectAccessSheet(
                    onContinue: { store.acknowledgeProjectAccess() },
                    onLater: { dismissedAccessNote = true })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInstallSheet)) { _ in showInstall = true }
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.canLoadObject(ofClass: NSURL.self) {
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let url = (object as? NSURL)?.absoluteString else { return }
                    Task { @MainActor in installModel.text = url; showInstall = true }
                }
                return true
            }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let s = object as? String else { return }
                Task { @MainActor in installModel.text = s; showInstall = true }
            }
            return true
        }
    }

    private enum ActiveSheet: Identifiable {
        case install, projectAccess
        var id: Self { self }
    }

    /// Install wins while it's open; the first-run note shows until Continue
    /// or Not Now (Not Now lasts for this launch).
    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if showInstall { return .install }
                if store.needsProjectAccessNote && !dismissedAccessNote { return .projectAccess }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                if showInstall { showInstall = false } else { dismissedAccessNote = true }
            })
    }

    private var sidebar: some View {
        List(selection: $selection) {
            if !filteredPlugins.isEmpty {
                Section("Plugins") {
                    // Expandable (spec §5.1): bundled skills are selectable rows
                    // so each gets its full cheat sheet, not just a chip.
                    ForEach(filteredPlugins) { entry in
                        // While searching: always expanded so the matching bundled
                        // skill/command is visible; manual toggling is suspended.
                        // When search clears: manual expansion state is restored.
                        DisclosureGroup(isExpanded: Binding(
                            get: { !searchText.isEmpty || expandedPlugins.contains(entry.id) },
                            set: { newValue in
                                guard searchText.isEmpty else { return }
                                if newValue { expandedPlugins.insert(entry.id) } else { expandedPlugins.remove(entry.id) }
                            }
                        )) {
                            ForEach(entry.plugin.skills) { skill in
                                SkillRow(skill: skill).tag(LibrarySelection.skill(skill.id))
                            }
                        } label: {
                            PluginRow(entry: entry).tag(LibrarySelection.plugin(entry.id))
                                .contextMenu { removeAddedProjectItems(roots: projectRoots(of: entry)) }
                        }
                    }
                }
            }
            if !filteredSkills.isEmpty {
                Section("Skills") {
                    ForEach(filteredSkills) { entry in
                        if usageDividerID == entry.id {
                            Divider()
                                .listRowSeparator(.hidden)
                                .selectionDisabled()
                        }
                        SkillEntryRow(entry: entry, showsUsageHint: usage.isEnabled,
                                     usage: usage.isEnabled ? usage.stats.summary(for: entry.skill) : nil)
                            .tag(LibrarySelection.entry(entry.id))
                            .contextMenu { removeAddedProjectItems(roots: projectRoots(of: entry)) }
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
            if !filteredNotes.isEmpty {
                Section("Your Notes") {
                    ForEach(filteredNotes) { folder in
                        DisclosureGroup(isExpanded: Binding(
                            get: { !searchText.isEmpty || expandedNotes.contains(folder.id) },
                            set: { if $0 { expandedNotes.insert(folder.id) } else { expandedNotes.remove(folder.id) } }
                        )) {
                            ForEach(folder.files) { file in
                                NoteRow(file: file).tag(LibrarySelection.note(file.id))
                            }
                        } label: {
                            Label(folder.name, systemImage: "folder")
                                .lineLimit(1)
                                .help(folder.url.path)
                                .contextMenu {
                                    Button("Remove from Skills Manager") { store.removeFolder(folder.url) }
                                }
                        }
                    }
                }
            }
            if !filteredBuiltIn.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: Binding(get: { !searchText.isEmpty || builtInExpanded },
                                                        set: { builtInExpanded = $0 })) {
                        ForEach(filteredBuiltIn) { entry in
                            SkillEntryRow(entry: entry).tag(LibrarySelection.entry(entry.id))
                        }
                    } label: {
                        Text("Built into Claude (\(filteredBuiltIn.count))").monospacedDigit()
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
                // Every empty state offers one way forward.
                if searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Skills Found", systemImage: "sparkles")
                    } description: {
                        Text("Nothing found in ~/.claude or ~/.agents yet.")
                    } actions: {
                        Button("Install a Skill or Plugin") { showInstall = true }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("Nothing matches “\(searchText)”.")
                    } actions: {
                        Button("Clear Search") { searchText = "" }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button { pickFolder() } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Whole footer strip is the hit area, not just the label.
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add a project Claude hasn't opened yet, or a folder of markdown notes")
            }
            .background(.bar)
        }
        .alert("Can't Add This Folder", isPresented: Binding(get: { addFolderMessage != nil },
                                                              set: { if !$0 { addFolderMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addFolderMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddFolder)) { _ in pickFolder() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a project folder or a folder of markdown notes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.addFolder(url) == .neither {
            addFolderMessage = "It has no Claude skills and no markdown files. Choose a project folder, or a folder with .md notes in it."
        }
    }

    private var projectNames: [String: String] {
        Dictionary(store.inventory.projects.map { ($0.root.path, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    }

    private var isEmptyLibrary: Bool {
        filteredPlugins.isEmpty && filteredSkills.isEmpty && filteredShared.isEmpty
            && filteredNotes.isEmpty && filteredBuiltIn.isEmpty && store.inventory.issues.isEmpty
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .entry(let id):
            if let entry = (library.skills + library.builtIn).first(where: { $0.id == id }) {
                SkillDetailView(skill: entry.skill, parentPlugin: nil, entry: entry,
                                accountLastSynced: store.inventory.accountLastSynced, projectNames: projectNames)
            } else {
                missingSelection
            }
        case .skill(let id):
            if let skill = allSkills.first(where: { $0.id == id }) {
                SkillDetailView(skill: skill, parentPlugin: parentPlugin(of: skill), entry: nil,
                                accountLastSynced: nil, projectNames: projectNames)
            } else {
                missingSelection
            }
        case .plugin(let id):
            if let entry = library.plugins.first(where: { $0.id == id }) {
                PluginDetailView(plugin: entry.plugin, entry: entry)
            } else {
                missingSelection
            }
        case .note(let id):
            if let file = store.inventory.notes.flatMap(\.files).first(where: { $0.id == id }) {
                NoteDetailView(file: file)
            } else {
                missingSelection
            }
        case .needsAttention:
            NeedsAttentionView(issues: store.inventory.issues,
                               removableFolders: Set(store.addedFolders.map(\.path)),
                               onRemove: { store.removeFolder($0) })
        case nil:
            ContentUnavailableView(
                "Select an Item",
                systemImage: "sidebar.left",
                description: Text("Choose a skill or plugin to see how to use it."))
        }
    }

    private var library: Library { store.inventory.library }

    /// Plugin sub-skills and unconnected shared skills (selected via `.skill`).
    private var allSkills: [Skill] {
        store.inventory.sharedSkills + library.plugins.flatMap(\.plugin.skills)
    }

    private func parentPlugin(of skill: Skill) -> Plugin? {
        guard case .plugin(let pluginID) = skill.source else { return nil }
        return library.plugins.first { $0.id == pluginID }?.plugin
    }

    private var missingSelection: some View {
        ContentUnavailableView(
            "Item No Longer Exists",
            systemImage: "questionmark.folder",
            description: Text("It changed on disk — pick another item."))
    }

    // MARK: Removing hand-added projects

    /// Project folders a row's copies live in.
    private func projectRoots(of entry: SkillEntry) -> [URL] {
        entry.locations.compactMap {
            if case .project(let root, _) = $0.skill.source { return root }
            return nil
        }
    }

    private func projectRoots(of entry: PluginEntry) -> [URL] {
        entry.locations.compactMap {
            if case .project(let root) = $0.plugin.scope { return root }
            return nil
        }
    }

    /// Only folders the user added by hand can be removed — the rest come
    /// from Claude's own records. Removing never touches the disk.
    @ViewBuilder
    private func removeAddedProjectItems(roots: [URL]) -> some View {
        let added = Set(store.addedFolders.map(\.path))
        let rootPaths = Set(roots.map(\.path))
        ForEach(store.inventory.projects.filter { added.contains($0.root.path) && rootPaths.contains($0.root.path) }) { project in
            Button("Remove “\(project.displayName)” from Skills Manager") { store.removeFolder(project.root) }
        }
    }

    // MARK: Filtering

    private var filteredPlugins: [PluginEntry] { library.plugins.filter { matches($0) } }
    private var filteredSkills: [SkillEntry] {
        let matching = library.skills.filter { matches($0) }
        guard usage.isEnabled else { return matching }
        return UsageSort.sorted(matching, by: usage.sort, stats: usage.stats)
    }

    /// The id of the first never-used entry in `filteredSkills`, when both a
    /// used and a never-used group exist under one of the usage sorts — the
    /// divider renders just above it.
    private var usageDividerID: String? {
        guard usage.isEnabled, usage.sort == .lastUsed || usage.sort == .mostUsed else { return nil }
        let skills = filteredSkills
        guard let firstNeverUsedIndex = skills.firstIndex(where: { usage.stats.summary(for: $0.skill) == nil })
        else { return nil }
        guard firstNeverUsedIndex > 0 else { return nil }
        return skills[firstNeverUsedIndex].id
    }
    private var filteredBuiltIn: [SkillEntry] { library.builtIn.filter { matches($0) } }
    private var filteredShared: [Skill] { store.inventory.sharedSkills.filter { matches($0) } }
    private var filteredNotes: [NoteFolder] {
        guard !searchText.isEmpty else { return store.inventory.notes }
        let q = searchText.localizedLowercase
        return store.inventory.notes.compactMap { folder in
            let files = folder.files.filter { $0.name.localizedLowercase.contains(q) }
            if folder.name.localizedLowercase.contains(q) { return folder }
            return files.isEmpty ? nil : NoteFolder(url: folder.url, name: folder.name, files: files)
        }
    }

    private func matchesTags(_ tags: [LocationTag]) -> Bool {
        let q = searchText.localizedLowercase
        return tags.contains { $0.label.localizedLowercase.contains(q) }
    }

    private func matches(_ entry: SkillEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return matches(entry.skill) || matchesTags(entry.tags)
    }

    private func matches(_ entry: PluginEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return matches(entry.plugin) || matchesTags(entry.tags)
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

extension Notification.Name {
    static let showInstallSheet = Notification.Name("SkillsManager.showInstallSheet")
    static let showAddFolder = Notification.Name("SkillsManager.showAddFolder")
}
