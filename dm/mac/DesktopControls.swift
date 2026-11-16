// TonTon presentation of NX2Apple's per-game mapping protocol. See desktop-controls-upstream.md.
import SwiftUI

private func ct(_ text: String) -> String {
    Bundle.main.localizedString(forKey: text, value: text, table: "Launcher")
}
func desktopKeyLabel(_ name: String) -> String { name.count == 1 ? name : ct(name) }

struct DesktopControlsView: View {
    @ObservedObject var model: LauncherModel
    let rows: [[String]]
    let movement: String
    @State private var expanded = false
    // Physical macOS positions, matching input_map.h; Escape, F1 and F8 remain recovery shortcuts.
    static let keys: [(String, Int)] = [
        ("A",0),("S",1),("D",2),("F",3),("H",4),("G",5),("Z",6),("X",7),("C",8),("V",9),
        ("Q",12),("W",13),("E",14),("R",15),("Y",16),("T",17),("1",18),("2",19),("3",20),("4",21),
        ("6",22),("5",23),("9",25),("7",26),("8",28),("0",29),("O",31),("U",32),("I",34),("P",35),
        ("+",24),("-",27),("Numpad+",69),("Numpad-",78),("Enter",36),("L",37),("J",38),("K",40),("N",45),("M",46),("Tab",48),("Space",49),("Escape",53),
        ("Shift",56),("Alt",58),("Ctrl",59),("Left",123),("Right",124),("Down",125),("Up",126),
        ("MouseLeft",128),("MouseRight",129),("MouseMiddle",130)
    ]
    private var base: [String: Int] {
        var byKey = Dictionary(uniqueKeysWithValues: ControllerMap.defaultKeys.filter { ControllerMap.buttons.contains($0.key) }.map { ($0.value, $0.key) })
        for row in rows {
            if let code = Self.keys.first(where: { $0.0 == row[0] })?.1 {
                byKey[code] = ControllerMap.functions.first(where: { $0.caseInsensitiveCompare(row[1]) == .orderedSame })
            }
        }
        if movement == "stick" || movement == "steering" {
            byKey[0] = "LLeft"; byKey[2] = "LRight"
            if movement == "stick" { byKey[13] = "LUp"; byKey[1] = "LDown" }
        } else if movement == "dpad" {
            byKey[0] = "Left"; byKey[2] = "Right"; byKey[13] = "Up"; byKey[1] = "Down"
        }
        var result: [String: Int] = [:]
        for code in byKey.keys.sorted() { result[byKey[code]!] = code }
        for row in rows {
            if let code = Self.keys.first(where: { $0.0 == row[0] })?.1, let name = byKey[code] { result[name] = code }
        }
        return result
    }
    private var effective: [String: Int] { ControllerMap.keys(model.values["DM_KEYMAP"], base: base) }
    private func label(_ function: String) -> String {
        let note = rows.last(where: { $0[1].caseInsensitiveCompare(function) == .orderedSame })?.last
        if let note { return ct(note) }
        let labels = ["LUp":"Move forward", "LDown":"Move backward", "LLeft":"Strafe left", "LRight":"Strafe right",
                      "RUp":"Look up", "RDown":"Look down", "RLeft":"Look left", "RRight":"Look right",
                      "Left":"D-pad left", "Right":"D-pad right", "Up":"D-pad up", "Down":"D-pad down"]
        return ct(labels[function] ?? function)
    }
    private func bind(_ function: String, _ code: Int) {
        var keys = effective
        keys[function] = nil
        if code >= 0 {
            keys = keys.filter { $0.value != code }
            keys[function] = code
        }
        model.values["DM_KEYMAP"] = ControllerMap.functions.compactMap { name -> String? in
            guard keys[name] != base[name] else { return nil }
            return name + "=" + (keys[name].map(String.init) ?? "none")
        }.joined(separator: ",")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                Label(ct("Customize keyboard and mouse"), systemImage: expanded ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            if expanded {
            Text(ct("Each game keeps its own bindings. Assigning a key moves its previous action. Changes apply on the next launch."))
                .font(.footnote).foregroundStyle(.secondary)
            ForEach([("Movement", ["LUp","LDown","LLeft","LRight"]),
                     ("Camera directions", ["RUp","RDown","RLeft","RRight"]),
                     ("Actions and menus", ControllerMap.buttons + ["Shake","Run"])], id: \.0) { group in
                Text(ct(group.0)).font(.headline).padding(.top, 8)
                ForEach(group.1, id: \.self) { name in
                Picker(selection: Binding(get: { effective[name] ?? -1 }, set: { bind(name, $0) })) {
                    Text(ct("Unassigned")).tag(-1)
                    ForEach(Self.keys, id: \.1) { key in Text(desktopKeyLabel(key.0)).tag(key.1) }
                } label: {
                    Text(label(name) + " · " + ct(name))
                }
                .disabled(model.fixed.contains("DM_KEYMAP"))
            }
            }
            Button(ct("Restore this game's keyboard defaults")) { model.values["DM_KEYMAP"] = "" }
                .disabled(model.fixed.contains("DM_KEYMAP"))
            }
        }
    }
}

struct ControllerButtonsView: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        DisclosureGroup(ct("Customize controller buttons")) {
            ForEach(ControllerMap.buttons, id: \.self) { name in
                Picker(ct(name), selection: Binding(get: {
                    ControllerMap.pad(model.values["DM_PAD_MAP"])[name] ?? name
                }, set: { target in
                    var map = ControllerMap.pad(model.values["DM_PAD_MAP"])
                    map[name] = target == name ? nil : target
                    model.values["DM_PAD_MAP"] = ControllerMap.buttons.compactMap { button in map[button].map { button + "=" + $0 } }.joined(separator: ",")
                })) {
                    Text(ct("Unassigned")).tag("none")
                    ForEach(ControllerMap.buttons, id: \.self) { Text(ct($0)).tag($0) }
                }
                .disabled(model.fixed.contains("DM_PAD_MAP"))
            }
            Button(ct("Restore controller button defaults")) { model.values["DM_PAD_MAP"] = "" }
                .disabled(model.fixed.contains("DM_PAD_MAP"))
        }
    }
}
