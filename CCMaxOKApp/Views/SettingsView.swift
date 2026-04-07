import SwiftUI

struct SettingsView: View {
    @AppStorage("alert_overuse_5h_80") private var overuse5h80 = true
    @AppStorage("alert_overuse_5h_95") private var overuse5h95 = true
    @AppStorage("alert_overuse_7d_70") private var overuse7d70 = true
    @AppStorage("alert_waste_5h") private var waste5h = true
    @AppStorage("alert_waste_7d") private var waste7d = true
    @AppStorage("alert_weekly_report") private var weeklyReport = true

    @AppStorage("threshold_overuse_5h_1") private var threshold5h1 = 80.0
    @AppStorage("threshold_overuse_5h_2") private var threshold5h2 = 95.0
    @AppStorage("threshold_overuse_7d") private var threshold7d = 70.0

    var body: some View {
        Form {
            Section("과다 사용 경고") {
                Toggle("5시간 한도 \(Int(threshold5h1))% 도달", isOn: $overuse5h80)
                Toggle("5시간 한도 \(Int(threshold5h2))% 도달", isOn: $overuse5h95)
                Toggle("7일 한도 \(Int(threshold7d))% 도달", isOn: $overuse7d70)
            }
            Section("낭비 방지 알림") {
                Toggle("5시간 리셋 임박 + 여유 많음", isOn: $waste5h)
                Toggle("7일 리셋 임박 + 사용률 저조", isOn: $waste7d)
                Toggle("주간 리포트 (매주 월요일)", isOn: $weeklyReport)
            }
            Section("임계값 설정") {
                HStack {
                    Text("5시간 경고 1단계")
                    Slider(value: $threshold5h1, in: 50...95, step: 5)
                    Text("\(Int(threshold5h1))%").frame(width: 40)
                }
                HStack {
                    Text("5시간 경고 2단계")
                    Slider(value: $threshold5h2, in: 80...100, step: 5)
                    Text("\(Int(threshold5h2))%").frame(width: 40)
                }
                HStack {
                    Text("7일 경고")
                    Slider(value: $threshold7d, in: 50...90, step: 5)
                    Text("\(Int(threshold7d))%").frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
    }
}
