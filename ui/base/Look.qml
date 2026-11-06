pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../../js/entries.mjs" as Entries

// x.com's look: palette, type scale, post geometry, image scale, stacking, asset URLs and fills, plus DHH's identity.
QtObject {
  id: look

  // x.com's colours and post geometry are fixed CSS pixels, never scaled
  // with the shell's spacing, so the panel's posts and the rendered images
  // (ui/render) are x.com's on every machine. The shell supplies the rest:
  // the theme's text colour (`themeText`), the bar's foreground
  // (`barForeground`, which BarWidget assigns), the fills derived from them,
  // and the panel-chrome sizes written as Style.space.

  // The bar's foreground, for the hover and selection fills from Style.
  property color barForeground: Color.foreground
  readonly property color themeText: Color.foreground

  // x.com's Chirp, which only x.com may serve, stood in for by Adwaita Sans
  // (Inter; GTK and Plymouth depend on it, so every Omarchy install has it),
  // the installed sans closest to Chirp's proportions.
  readonly property string fontFamily: "Adwaita Sans"
  // Its letters close up to Chirp's widths, fitted by least squares to three
  // sentences measured in x.com's computed styles: within 2px over 400-550px
  // regular, 4px bold (Noto Sans, the next best, misses by 15px either way).
  function letterSpacingFor(weight) { return weight >= Font.DemiBold ? -0.208 : -0.294 }

  // DHH's identity, as js/entries.mjs holds it.
  readonly property string dhhName: Entries.DHH.name
  readonly property string dhhFullName: Entries.DHH.fullName
  readonly property string dhhHandle: Entries.DHH.handle

  readonly property color accent: "#1D9BF0"
  readonly property color repostGreen: "#00BA7C"
  readonly property color likePink: "#F91880"
  // Text on x.com's fixed surfaces, and the secondary grey (handles, counts).
  readonly property color surfaceText: "#E7E9EA"
  readonly property color muted: "#71767B"
  readonly property color divider: "#2F3336"
  readonly property color mutedBorder: "#536471"
  // The light pill button (the filled "Follow" pill, the dialog's primary).
  readonly property color buttonFill: "#EFF3F4"
  readonly property color buttonFillHover: "#D7DBDC"
  readonly property color buttonText: "#0F1419"
  readonly property color danger: "#F4212E"
  // The disc behind the search field's clear mark.
  readonly property color clearButtonFill: "#FFFFFF"
  readonly property color surface: "#000000"
  // Dark overlays: the collapsed profile header, and the modal dialog's
  // scrim. Fixed, so they read the same on every theme (a themed foreground
  // would invert the tint on dark themes).
  readonly property color headerScrim: Util.alpha(look.surface, 0.45)
  readonly property color modalScrim: Util.alpha(look.surface, 0.4)
  // The panel's border: x.com's hairline in place of the theme's border colour.
  readonly property int panelBorderWidth: Math.max(1, Style.space(2))
  // x.com's 1px rules: dividers, the context card's border.
  readonly property int hairline: 1

  // Post text mirrors x.com's 15px/20px; captions (the repost header, the
  // counts, the post count) take the 13px scale, and the profile name and
  // the dialog title 20px.
  readonly property int textSize: 15
  readonly property int bodyLineHeight: 20
  readonly property int captionSize: 13
  readonly property int titleSize: 20
  readonly property real secondaryOpacity: 0.62

  // A post's geometry, measured off x.com's timeline: a 598px column (600
  // with its borders), 16px sides, 12px above and below, a 40px avatar 8px
  // from the 518px text column, a 20px author line 4px over the body.
  readonly property int columnWidth: 598
  readonly property int postSidePadding: 16
  readonly property int postTopPadding: 12
  readonly property int postBottomPadding: 12
  readonly property int avatarSize: 40
  readonly property int avatarGap: 8
  readonly property int contentIndent: avatarSize + avatarGap
  readonly property int authorLineHeight: 20
  readonly property int bodyGap: 4
  // The author line: the verified seal 2px after the name, the affiliate
  // logo 4.8px after the seal and 2.8px before its box ends, the handle 4px
  // on.
  readonly property real sealSize: 18.75
  readonly property real sealGap: 2
  readonly property real affiliateSize: 14.34
  readonly property real affiliateGap: 4.8
  readonly property real affiliateTrailing: 2.8
  readonly property real handleGap: 4
  // The Grok mark (19.33 x 18.75) 8px before the 18.75px "..." mark.
  readonly property real grokWidth: 19.33
  readonly property real headIconSize: 18.75
  readonly property real headIconGap: 8
  // The quoted or replied-to post: a bordered card 12px under the body,
  // padded 12px, with a 24px avatar 4px before its author line (the same
  // line as the post's) and 4px over its body.
  readonly property int contextCardGap: 12
  readonly property int contextCardPadding: 12
  readonly property int contextAvatarSize: 24
  readonly property int contextAvatarGap: 4
  readonly property int contextBodyGap: 4
  readonly property int contextCardRadius: 16
  // The action row: 12px under the content, on a 20px line. Four engagement
  // counts share what the bookmark and share icons (12px apart) leave, 4px
  // apart and 4px before the icons; each count (13px) starts 4px after its
  // icon.
  readonly property int actionRowGap: 12
  readonly property int actionRowHeight: 20
  readonly property int engagementGap: 4
  readonly property int countGap: 4
  readonly property int trailIconGap: 12

  // Action icons are 18.75px square on x.com, in 34.75px hover discs that
  // overlap into one cluster. A disc row's spacing centres each disc where
  // x.com draws its icon: the head's Grok and "..." marks, and the trailing
  // bookmark and share icons (30.75px apart).
  readonly property real actionIconSize: 18.75
  readonly property real discSize: 34.75
  readonly property real headDiscSpacing: (grokWidth + headIconSize) / 2 + headIconGap - discSize
  readonly property real trailDiscSpacing: actionIconSize + trailIconGap - discSize
  // Opacity the share icon drops to while its entry renders.
  readonly property real renderingIconOpacity: 0.4
  // "DHH reposted", 4px over the author line: a 16px icon 3px before the
  // 13px label, which starts 4px left of the author name.
  readonly property int repostIconSize: 16
  readonly property int repostIconGap: 3
  readonly property int repostLabelLead: 4
  readonly property int repostHeaderIndent: contentIndent - repostLabelLead - repostIconGap - repostIconSize
  readonly property int repostHeaderGap: 4

  // The saved images are drawn at twice their CSS-pixel size on any screen.
  readonly property int imageScale: 2

  // Stacking inside the panel body: the search dropdowns over the scrolling
  // body, the modal dialog over both.
  readonly property int zDropdown: 100
  readonly property int zModal: 200

  // Icons live in assets/icons as single-path SVGs with their colour baked
  // in. Each action icon has a resting (#71767B) and a hover variant
  // pre-rendered in its x.com hover colour, so hover never recolours at draw
  // time.
  function icon(name, hoverVariant) {
    return Qt.resolvedUrl("../../assets/icons/" + name + (hoverVariant ? "-hover" : "") + ".svg")
  }

  // Each image in assets/images is named after its token.
  readonly property string dhhAvatar: Qt.resolvedUrl("../../assets/images/dhh-avatar.png")
  readonly property string dhhPortrait: Qt.resolvedUrl("../../assets/images/dhh-portrait.png")
  readonly property string fallbackAvatar: Qt.resolvedUrl("../../assets/images/fallback-avatar.png")
  readonly property string avatarMask: Qt.resolvedUrl("../../assets/images/avatar-mask.png")
  readonly property string affiliateLogo: Qt.resolvedUrl("../../assets/images/affiliate-logo.png")

  function hoverFill(color) { return Style.hoverFillFor(look.barForeground, color) }
  readonly property color selectedRowFill: Style.selectedFillFor(look.barForeground, look.accent)
  readonly property color textSelectionColor: Style.selectionFillFor(look.themeText, look.accent)
}
