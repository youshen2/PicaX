import SwiftUI

extension View {
    func picaxOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        modifier(PicaxOnChangeModifier(value: value, action: action))
    }
}

private struct PicaxOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (_ oldValue: Value, _ newValue: Value) -> Void
    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if previousValue == nil {
                    previousValue = value
                }
            }
            .onChange(of: value) { newValue in
                let oldValue = previousValue ?? newValue
                previousValue = newValue
                guard oldValue != newValue else { return }
                action(oldValue, newValue)
            }
    }
}
