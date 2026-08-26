import QtQuick
import qs.Commons

// Counter-offset wrapper: bodyColumn is inset Style.spacing.lg from each
// side, so full-bleed children (divider, results list, history list) span the
// full bodyScroll width by shifting left by the same inset and widening to the
// caller-supplied `fullWidth`. A Column keeps the vertical flow of bodyColumn
// (its height follows its content) and honors `visible`, so a hidden block
// still collapses out of the layout.
Column {
  required property real fullWidth

  x: -Style.spacing.lg
  width: fullWidth
}
