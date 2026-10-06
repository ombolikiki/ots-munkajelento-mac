import SwiftUI
import AppKit

/// Javaslatok gépelés közben (Munkahely, Kiindulás, Cél, Tevékenység típusa és szövege). A logika tiszta függvényekből áll (tesztelhető),
/// a felület a `SuggestTextField` és a `TypeSuggestField`. A Beállítások › Rögzítés alatt kapcsolható ("suggest.enabled", alapból be).
enum Suggest {
    /// Kisbetű- és ékezetfüggetlen forma (az `ügy` és az `ugy` is az „Ügyintézés”-t adja).
    static func norm(_ s: String) -> String { CalendarParser.fold(s) }

    /// A beírt szövegre illő jelöltek, legfeljebb `limit` darab: előbb az, amelyik azzal kezdődik, utána amelyikben egy szó azzal kezdődik,
    /// végül amelyikben bárhol benne van. A pontosan egyező és az ismétlődő jelöltet kihagyja; üres szövegre nincs javaslat.
    static func matches(query: String, candidates: [String], limit: Int = 5) -> [String] {
        let q = norm(query)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var starts: [String] = [], words: [String] = [], inside: [String] = []
        for c in candidates {
            let n = norm(c)
            guard !n.isEmpty, n != q, seen.insert(n).inserted else { continue }
            if n.hasPrefix(q) { starts.append(c) }
            else if n.split(separator: " ").dropFirst().contains(where: { $0.hasPrefix(q) }) { words.append(c) }
            else if n.contains(q) { inside.append(c) }
        }
        return Array((starts + words + inside).prefix(max(0, limit)))
    }

    /// Listás mezőnél (Cél): a szöveg a legutolsó elválasztó (`,`, `;` vagy ` - `) előtti része (az elválasztóval együtt) és az éppen írt rész.
    static func split(_ text: String) -> (prefix: String, segment: String) {
        let chars = Array(text)
        var end = 0   // az utolsó elválasztó utáni pozíció
        var i = 0
        while i < chars.count {
            if chars[i] == "," || chars[i] == ";" { end = i + 1 }
            else if chars[i].isWhitespace, i + 2 < chars.count, "-–—".contains(chars[i + 1]), chars[i + 2].isWhitespace { end = i + 3 }
            i += 1
        }
        let prefix = String(chars[..<end])
        let segment = String(chars[end...]).trimmingCharacters(in: .whitespaces)
        return (prefix, segment)
    }

    /// Az elfogadott javaslat beillesztése: egyszerű mezőnél a teljes szöveg helyére, listás mezőnél az éppen írt rész helyére.
    static func apply(_ choice: String, to text: String, list: Bool) -> String {
        guard list else { return choice }
        let (prefix, _) = split(text)
        if prefix.isEmpty { return choice }
        return prefix + (prefix.hasSuffix(" ") ? "" : " ") + choice
    }

    /// A javaslatok a mezőhöz: listás mezőnél csak az éppen írt részre, és csak ha az nem cím (utca, házszám) és a jelölt még nincs a listában.
    static func suggestions(text: String, candidates: [String], list: Bool, limit: Int = 5) -> [String] {
        if !list { return matches(query: text, candidates: candidates, limit: limit) }
        let (prefix, segment) = split(text)
        guard !segment.isEmpty, !CalendarParser.looksLikeStreet(segment) else { return [] }
        let used = Set(prefix.split(whereSeparator: { ",;-–—".contains($0) }).map { norm(String($0)) })
        return matches(query: segment, candidates: candidates.filter { !used.contains(norm($0)) }, limit: limit)
    }
}

// MARK: - Javaslatlista

/// A legördülő javaslatlista kirajzolása (kattintásra elfogadja a javaslatot).
struct SuggestionList: View {
    let items: [String]
    let highlighted: Int
    let onPick: (String) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button { onPick(item) } label: {
                    Text(item)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(i == highlighted ? Color.white : Color.primary)
                        .background(i == highlighted ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
}

// MARK: - Szövegmező javaslatokkal

/// Szövegmező, amely gépelés közben javaslatokat ad. A lista a mező alatt, a tartalomra rátakarva jelenik meg (nem növeli az ablak magasságát).
/// Billentyűk: ↓ és ↑ lépked, Enter az éppen kijelöltet fogadja el, Tab a kijelöltet (ha nincs, az elsőt), Esc bezárja.
/// Ha a javaslatok ki vannak kapcsolva (Beállítások › Rögzítés), sima szövegmező.
struct SuggestTextField: View {
    let prompt: String
    @Binding var text: String
    let candidates: () -> [String]
    /// Listás mező (Cél): a javaslat az éppen írt részre vonatkozik.
    var list = false
    /// Ha megadott, az elfogadott javaslatot ez kapja meg (a szöveg nem íródik át): a Tevékenység típusa mező használja.
    var onPick: ((String) -> Void)?
    var focusState: Binding<Bool>?
    /// Csak teszthez: a lista fókusz nélkül is látszik.
    var forceOpen = false

    @AppStorage("suggest.enabled") private var enabled = true
    @FocusState private var focused: Bool
    @State private var highlight = -1
    @State private var closed = false

    private var items: [String] {
        guard enabled, focused || forceOpen, !closed else { return [] }
        return Suggest.suggestions(text: text, candidates: candidates(), list: list)
    }

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onChange(of: text) { closed = false; highlight = -1 }
            .onChange(of: focused) { focusState?.wrappedValue = focused; if !focused { highlight = -1 } }
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.escape) { if items.isEmpty { return .ignored }; closed = true; return .handled }
            .onKeyPress(.tab) {
                let list = items
                guard !list.isEmpty else { return .ignored }
                pick(list[min(max(highlight, 0), list.count - 1)])
                return .handled
            }
            .onSubmit {
                let list = items
                if highlight >= 0, highlight < list.count { pick(list[highlight]) }
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let shown = items
                    if !shown.isEmpty {
                        SuggestionList(items: shown, highlighted: highlight, onPick: pick)
                            .frame(width: max(geo.size.width, 140), alignment: .leading)
                            .offset(y: geo.size.height + 2)
                    }
                }
            }
            .zIndex(items.isEmpty ? 0 : 100)
    }

    private func move(_ d: Int) -> KeyPress.Result {
        let n = items.count
        guard n > 0 else { return .ignored }
        highlight = highlight < 0 ? (d > 0 ? 0 : n - 1) : (highlight + d + n) % n
        return .handled
    }

    private func pick(_ item: String) {
        if let onPick = onPick { onPick(item); text = "" }
        else { text = Suggest.apply(item, to: text, list: list) }
        closed = true
        highlight = -1
    }
}

// MARK: - Tevékenység típusa

/// A Tevékenység típusa mező: gépelve szűr („ügy” → Ügyintézés), a nyílra kattintva a teljes csoportosított lista nyílik.
/// Kikapcsolt javaslatoknál a régi legördülő lista.
struct TypeSuggestField: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("suggest.enabled") private var enabled = true
    @State private var query = ""
    @State private var focused = false

    var body: some View {
        if enabled { suggestField } else { classicPicker }
    }

    private var classicPicker: some View {
        Picker("", selection: $m.selectedType) {
            Text("Válassz típust…").tag(ActivityType?.none)
            ForEach(ActivityType.groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.types) { t in Text(t.label).tag(Optional(t)) }
                }
            }
        }
        .labelsHidden()
    }

    private var suggestField: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                SuggestTextField(prompt: "", text: $query, candidates: { ActivityType.all.map { $0.label } },
                                 onPick: { label in
                                     if let t = ActivityType.all.first(where: { $0.label == label }) { m.selectedType = t }
                                 }, focusState: $focused)
                // a kiválasztott típus (amíg nem gépelsz)
                if query.isEmpty && !focused {
                    Text(m.selectedType?.label ?? "Válassz típust…")
                        .font(.system(size: 13))
                        .foregroundStyle(m.selectedType == nil ? Color.secondary : Color.primary)
                        .padding(.leading, 7)
                        .allowsHitTesting(false)
                }
            }
            Menu {
                ForEach(ActivityType.groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.types) { t in Button(t.label) { m.selectedType = t; query = "" } }
                    }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .help("A teljes lista")
        }
    }
}
