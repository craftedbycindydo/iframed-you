#if DEBUG
import SwiftUI
import SkylitCore

struct GalleryScreen: View {
    @Environment(\.theme) private var theme
    @State private var swatch = Palettes.swatches[2]
    @State private var palette = "linen"
    @State private var segment = 0
    @State private var done = true
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let maya = Person(id: "p1", name: "Maya", color: "#00A36C")

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    Text("Screen title").font(.screenTitle)
                    Text("Hero figure").font(.hero)
                    Text("Section title").font(.sectionTitle).foregroundStyle(Theme.secondaryLabel)
                    Text("Row title").font(.rowTitle)
                    Text("Row subtitle").font(.rowSubtitle).foregroundStyle(Theme.secondaryLabel)
                    Text("Status").font(.status).foregroundStyle(Theme.secondaryLabel)
                    Text("Note").font(.note).foregroundStyle(Theme.secondaryLabel)
                } header: {
                    SectionHeader("Type")
                }
                Section {
                    colour("Background", theme.background)
                    colour("Grouped background", theme.groupedBackground)
                    colour("Fill", theme.fill)
                    colour("Tint", theme.tint)
                    colour("Destructive", Theme.destructive)
                    colour("Connected", Theme.connected)
                    RowLabel("Label") { RowValue(text: "Secondary") }
                } header: {
                    SectionHeader("Colour roles")
                }
                Section {
                    HStack(spacing: Space.s) {
                        Button("Prominent") {}.buttonStyle(.borderedProminent)
                        Button("Bordered") {}.buttonStyle(.bordered)
                        Button("Plain") {}
                        Button("Delete", role: .destructive) {}
                    }
                    HStack(spacing: Space.s) {
                        Button("Add", systemImage: "plus") {}.headerAction(prominent: true)
                        Button("People", systemImage: "person.2") {}.headerAction()
                        Spacer()
                        Button("Capsule") {}.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    Picker("Segment", selection: $segment) {
                        Text("One").tag(0)
                        Text("Two").tag(1)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SectionHeader("Buttons")
                }
                Section {
                    Button {
                        done.toggle()
                    } label: {
                        RowLabel(title: "Toggle row", emoji: "🛏️", isDimmed: done) { DoneMark(isOn: done) } trailing: { EmptyView() }
                    }
                    .buttonStyle(RowButtonStyle())
                    RowLabel("Value row", subtitle: "With a subtitle", symbol: "calendar", symbolTint: theme.tint) { RowValue(text: "×2") }
                    RowLabel("Navigation row", emoji: "") { RowChevron() }
                    RowLabel(title: "Avatar row") { Avatar(person: maya) } trailing: { EmptyView() }
                    InlineAddField(prompt: "Add an item", text: $draft, focus: $focused, limit: 80) {}
                    ProgressSummary(done: 2, total: 6, caption: "Sunday, October 11", headline: "4 chores to go")
                } header: {
                    SectionHeader("Maya", person: maya, showsAvatar: true, count: "1/2")
                } footer: {
                    Text("Rows share one anatomy: control, glyph, title, subtitle, value.")
                }
                Section {
                    SwatchPicker(selection: $swatch)
                    PaletteGrid(selected: palette) { palette = $0 }
                } header: {
                    SectionHeader("Pickers")
                }
                Section {
                    FrameHero().frame(maxWidth: .infinity)
                } header: {
                    SectionHeader("Illustration")
                }
                Section {
                    ContentUnavailableView("Empty state", systemImage: "checklist", description: Text("One short sentence."))
                } header: {
                    SectionHeader("Empty")
                }
            }
            .listSectionSpacing(Space.l)
            .screenHeader("Gallery", status: "Kitchen frame", statusSymbol: "wifi") {
                Button("Secondary", systemImage: "person.2") {}.headerAction()
                Button("Primary", systemImage: "plus") {}.headerAction(prominent: true)
            }
        }
    }

    private func colour(_ name: String, _ color: Color) -> some View {
        RowLabel(name) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(color)
                .frame(width: Size.touch, height: Size.control)
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.separator))
        }
    }
}
#endif
