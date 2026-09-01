import QtQuick
import QtTest
import "../../src/modules/bar"

TestCase {
  name: "BarSpacing"

  BarSpacing {
    id: normal
  }

  BarSpacing {
    id: compact
    compact: true
  }

  BarSpacing {
    id: portrait
    compact: true
    portrait: true
  }

  function test_normal_density_uses_semantic_spacing_scale() {
    compare(normal.contentGap, 6);
    compare(normal.itemPadding, 6);
    compare(normal.itemGap, 4);
    compare(normal.groupGap, 12);
    compare(normal.edgeInset, 16);
    compare(normal.centerClearance, 20);
    verify(normal.groupGap > normal.itemGap);
    compare(Math.abs(
      (normal.groupGap + normal.itemPadding)
        - (normal.itemPadding * 2 + normal.itemGap)),
      normal.space1);
  }

  function test_compact_density_preserves_hierarchy() {
    compare(compact.contentGap, 4);
    compare(compact.itemPadding, 4);
    compare(compact.itemGap, 4);
    compare(compact.groupGap, 8);
    compare(compact.trayItemGap, 4);
    compare(compact.actionSize, 28);
    verify(compact.groupGap > compact.itemGap);
    verify(compact.groupGap < normal.groupGap);
    compare(
      compact.groupGap + compact.itemPadding,
      compact.itemPadding * 2 + compact.itemGap);
  }

  function test_portrait_uses_touch_density_even_when_compact_is_requested() {
    compare(portrait.contentGap, normal.contentGap);
    compare(portrait.itemPadding, normal.itemPadding);
    compare(portrait.groupGap, normal.groupGap);
    compare(portrait.actionSize, 36);
  }
}
