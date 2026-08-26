import QtQuick
import qs.Commons
import qs.Ui

// Round-ended (pill) tooltip with the themed tooltip background, used by the
// PostCard hover-disc buttons via CenteredToolTip and by EngagementMetric
// (both override `fontFamily`/`fontSize`). The header/folder hover buttons use
// AccentToolTip instead.
PanelToolTip {
  background: Rectangle { color: Color.tooltip.background; radius: 9999 }
}
