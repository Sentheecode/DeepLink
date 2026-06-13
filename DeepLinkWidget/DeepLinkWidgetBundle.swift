import SwiftUI

@main
struct DeepSeekBalanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeepSeekBalanceWidgetMedium()
        DeepSeekBalanceWidgetSmall()
        DeepSeekBalanceWidgetLarge()
        DeepSeekBalanceWidgetAccessory()
        MonitorLiveActivity()
    }
}
