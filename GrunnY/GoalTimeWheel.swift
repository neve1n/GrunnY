import SwiftUI
import UIKit

/// Two native wheel components keep the 24-hour appearance of the design.
struct GoalTimeWheel: UIViewRepresentable {
    @Binding var date: Date
    var onSelection: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        // Use the full content width so both columns and the colon share one center.
        CGSize(width: proposal.width ?? 350, height: proposal.height ?? 172)
    }
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        picker.backgroundColor = .clear
        picker.accessibilityLabel = "출발 시각"
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        if picker.selectedRow(inComponent: 0) != parts.hour { picker.selectRow(parts.hour ?? 0, inComponent: 0, animated: false) }
        if picker.selectedRow(inComponent: 1) != parts.minute { picker.selectRow(parts.minute ?? 0, inComponent: 1, animated: false) }
        picker.reloadAllComponents()
    }
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: GoalTimeWheel
        init(_ parent: GoalTimeWheel) { self.parent = parent }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { component == 0 ? 24 : 60 }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { min(120, pickerView.bounds.width / 2) }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 36 }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = String(format: "%02d", row)
            label.textAlignment = .center
            let selected = pickerView.selectedRow(inComponent: component) == row
            label.font = .systemFont(ofSize: selected ? 24 : 20, weight: selected ? .bold : .regular)
            label.textColor = UIColor(named: selected ? "GrunnYPrimary" : "GrunnYSecondary")
            label.accessibilityLabel = "\(row)\(component == 0 ? "시" : "분")"
            return label
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let hour = pickerView.selectedRow(inComponent: 0)
            let minute = pickerView.selectedRow(inComponent: 1)
            // A time-only control denotes the next occurrence, including tomorrow.
            let calendar = Calendar.current
            var parts = calendar.dateComponents([.year, .month, .day], from: Date())
            parts.hour = hour; parts.minute = minute; parts.second = 0
            guard var chosen = calendar.date(from: parts) else { return }
            if chosen <= Date() { chosen = calendar.date(byAdding: .day, value: 1, to: chosen) ?? chosen }
            parent.date = chosen
            parent.onSelection()
            pickerView.reloadAllComponents()
        }
    }
}
