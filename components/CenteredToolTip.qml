import QtQuick
import qs.Commons
import "."

// PillToolTip with the below-center placement baked in: horizontally centered
// on the host and offset one spacing step below it. Shared by the hover-disc,
// metric, and accent tooltips so the placement math lives in one place.
// `fontFamily`/`fontSize` default to the shell tooltip values; call sites
// override them when their host uses a different type scale.
PillToolTip {
  x: (parent.width - implicitWidth) / 2
  y: parent.height + Style.spacing.sm
}
