import Foundation

/// Common supervised-driving requirements. Rules change, so the app always lets the user edit the goals
/// and reminds them to confirm with their DMV.
struct StatePreset: Identifiable, Hashable {
    let code: String
    let name: String
    let totalHours: Double
    let nightHours: Double
    var id: String { code }

    static let all: [StatePreset] = [
        StatePreset(code: "AZ", name: "Arizona", totalHours: 30, nightHours: 10),
        StatePreset(code: "CA", name: "California", totalHours: 50, nightHours: 10),
        StatePreset(code: "CO", name: "Colorado", totalHours: 50, nightHours: 10),
        StatePreset(code: "FL", name: "Florida", totalHours: 50, nightHours: 10),
        StatePreset(code: "GA", name: "Georgia", totalHours: 40, nightHours: 6),
        StatePreset(code: "IL", name: "Illinois", totalHours: 50, nightHours: 10),
        StatePreset(code: "MD", name: "Maryland", totalHours: 60, nightHours: 10),
        StatePreset(code: "MI", name: "Michigan", totalHours: 50, nightHours: 10),
        StatePreset(code: "NY", name: "New York", totalHours: 50, nightHours: 15),
        StatePreset(code: "NC", name: "North Carolina", totalHours: 60, nightHours: 10),
        StatePreset(code: "OH", name: "Ohio", totalHours: 50, nightHours: 10),
        StatePreset(code: "PA", name: "Pennsylvania", totalHours: 65, nightHours: 10),
        StatePreset(code: "TX", name: "Texas", totalHours: 30, nightHours: 10),
        StatePreset(code: "VA", name: "Virginia", totalHours: 45, nightHours: 15),
        StatePreset(code: "WA", name: "Washington", totalHours: 50, nightHours: 10),
    ]
}
