import SwiftUI
import ScriptaCore

/// "Personaggi" sheet: speeches and words per character, gender breakdown and highlight colours.
struct CharacterAnalysisView: View {
    let statistics: [CharacterStat]
    @ObservedObject var store: CharacterProfileStore
    @Environment(\.dismiss) private var dismiss

    private var totalSpeeches: Int { statistics.reduce(0) { $0 + $1.speeches } }
    private var totalWords: Int { statistics.reduce(0) { $0 + $1.words } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if statistics.isEmpty {
                ContentUnavailableView {
                    Label("Nessun personaggio", systemImage: "person.2")
                } description: {
                    Text("I personaggi sono riconosciuti dalle intestazioni in MAIUSCOLO seguite da una battuta, o dai balloon **NOME**: testo.")
                }
                .frame(maxHeight: .infinity)
            } else {
                GenderBreakdown(rows: genderRows)
                    .padding(16)
                Divider()
                characterList
            }
            Divider()
            HStack {
                Text("Il genere e i colori sono salvati per questo documento.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fine") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Personaggi").font(.title2.weight(.semibold))
            Spacer()
            Text("\(statistics.count) personaggi · \(totalSpeeches) battute · \(totalWords.formatted()) parole")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(16)
    }

    private var characterList: some View {
        List {
            HStack(spacing: 12) {
                Text("Evidenzia").frame(width: 76, alignment: .leading)
                Text("Personaggio").frame(maxWidth: .infinity, alignment: .leading)
                Text("Battute").frame(width: 56, alignment: .trailing)
                Text("Parole").frame(width: 64, alignment: .trailing)
                Text("% parole").frame(width: 60, alignment: .trailing)
                Text("Genere").frame(width: 130, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(statistics) { stat in
                CharacterRow(stat: stat, totalWords: totalWords, store: store)
            }
        }
        .listStyle(.inset)
    }

    private var genderRows: [GenderBreakdown.Row] {
        Gender.allCases.compactMap { gender in
            let members = statistics.filter { store.profile(for: $0.name).gender == gender }
            guard !members.isEmpty else { return nil }
            return GenderBreakdown.Row(
                gender: gender, characters: members.count,
                speeches: members.reduce(0) { $0 + $1.speeches }, words: members.reduce(0) { $0 + $1.words },
                totalSpeeches: totalSpeeches, totalWords: totalWords)
        }
    }
}

private struct CharacterRow: View {
    let stat: CharacterStat
    let totalWords: Int
    @ObservedObject var store: CharacterProfileStore

    private var profile: CharacterProfile { store.profile(for: stat.name) }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(get: { profile.highlightHex != nil },
                                         set: { store.setHighlighted(stat.name, $0) }))
                    .labelsHidden()
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: profile.highlightHex.flatMap(NSColor.init(hex:)) ?? .clear) },
                    set: { color in store.update(stat.name) { $0.highlightHex = NSColor(color).hexString } }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .disabled(profile.highlightHex == nil)
                    .opacity(profile.highlightHex == nil ? 0.3 : 1)
            }
            .frame(width: 76, alignment: .leading)

            Text(stat.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(stat.speeches)").frame(width: 56, alignment: .trailing)
            Text(stat.words.formatted()).frame(width: 64, alignment: .trailing)
            Text(GenderBreakdown.percent(stat.words, of: totalWords)).frame(width: 60, alignment: .trailing)
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(get: { profile.gender },
                                          set: { gender in store.update(stat.name) { $0.gender = gender } })) {
                ForEach(Gender.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130, alignment: .leading)
        }
        .monospacedDigit()
    }
}

/// Share of speeches and words per gender, as stacked bars with a legend.
struct GenderBreakdown: View {
    struct Row: Identifiable {
        let gender: Gender
        let characters: Int
        let speeches: Int
        let words: Int
        let totalSpeeches: Int
        let totalWords: Int

        var id: Gender { gender }
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analisi di genere").font(.headline)
            bar(title: "Battute", value: \.speeches)
            bar(title: "Parole", value: \.words)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Circle().fill(row.gender.chartColor).frame(width: 8, height: 8)
                    Text(row.gender.displayName).frame(width: 110, alignment: .leading)
                    Text("\(row.characters) pers.").frame(width: 60, alignment: .leading)
                    Text("\(row.speeches) battute (\(Self.percent(row.speeches, of: row.totalSpeeches)))")
                        .frame(width: 150, alignment: .leading)
                    Text("\(row.words.formatted()) parole (\(Self.percent(row.words, of: row.totalWords)))")
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }

    private func bar(title: String, value: KeyPath<Row, Int>) -> some View {
        let total = max(1, rows.reduce(0) { $0 + $1[keyPath: value] })
        return HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(rows) { row in
                        Rectangle()
                            .fill(row.gender.chartColor)
                            .frame(width: segmentWidth(row[keyPath: value], of: total, in: proxy.size.width))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func segmentWidth(_ value: Int, of total: Int, in width: CGFloat) -> CGFloat {
        let share = CGFloat(value) / CGFloat(total)
        return max(0, width * share - 1) // 1pt gap between segments
    }

    static func percent(_ value: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(value) / Double(total) * 100).rounded()))%"
    }
}
