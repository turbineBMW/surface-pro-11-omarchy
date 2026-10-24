import QtQuick
import QtQuick.Shapes

// One concave rounded-corner fill: a square with a quarter-disc cut out of the
// inner corner, leaving `fill` against the two outer edges. isTop/isLeft pick
// which screen corner this piece sits in.
Shape {
  id: root

  property bool isTop: true
  property bool isLeft: true
  property color fill: "black"

  readonly property real cornerX: isLeft ? 0 : width
  readonly property real cornerY: isTop ? 0 : height

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeWidth: -1
    fillColor: root.fill
    startX: root.cornerX
    startY: root.cornerY

    PathLine { x: root.isLeft ? root.width : 0; y: root.cornerY }
    PathArc {
      x: root.cornerX
      y: root.isTop ? root.height : 0
      radiusX: root.width
      radiusY: root.height
      direction: root.isTop === root.isLeft ? PathArc.Counterclockwise : PathArc.Clockwise
    }
    PathLine { x: root.cornerX; y: root.cornerY }
  }
}
