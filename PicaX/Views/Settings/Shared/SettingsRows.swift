import SwiftUI

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
        }
    }
}

struct IntegerSettingsInputRow: View {
    let title: String
    @Binding var value: Int
    var unit: String?
    var lowerBound: Int?
    var upperBound: Int?

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .picaxKeyboardType(.numberPad)
                    .focused($isFocused)
                    .frame(width: 92)
                    .onChange(of: text, perform: updateValue)

                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(title)
        }
        .onAppear {
            text = "\(value)"
        }
        .onChange(of: value) { newValue in
            guard !isFocused else { return }
            text = "\(bounded(newValue))"
        }
        .onChange(of: isFocused) { focused in
            guard !focused else { return }

            let nextValue = bounded(value)
            if nextValue != value {
                value = nextValue
            }
            text = "\(nextValue)"
        }
    }

    private func updateValue(from newValue: String) {
        let filtered = String(newValue.filter(\.isNumber))
        if filtered != newValue {
            text = filtered
            return
        }

        guard let rawValue = Int(filtered) else { return }
        let nextValue = upperBound.map { min(rawValue, $0) } ?? rawValue
        if nextValue != value {
            value = nextValue
        }
        if nextValue != rawValue {
            text = "\(nextValue)"
        }
    }

    private func bounded(_ rawValue: Int) -> Int {
        var result = rawValue
        if let lowerBound {
            result = max(result, lowerBound)
        }
        if let upperBound {
            result = min(result, upperBound)
        }
        return result
    }
}
