import QtQuick
import QtTest
import "../../src/modules/control_center/DisplayGeometry.js" as Geometry

TestCase {
  name: "DisplayGeometry"

  function output(name, mode, scale, at, transform) {
    return { name, mode, scale, position: at, transform: transform || 0, enabled: true };
  }

  function test_single_display_is_centered_on_both_axes() {
    const outputs = [output("one", "2880x1800@120", 2, "420x100")];
    const viewport = Geometry.viewport(outputs, {}, 500, 132, 18);
    const box = Geometry.rect(outputs[0], {});
    fuzzyCompare(viewport.x + box.width * viewport.scale / 2, 250, 0.001);
    fuzzyCompare(viewport.y + box.height * viewport.scale / 2, 66, 0.001);
  }

  function test_scale_and_rotation_use_logical_dimensions() {
    const rotated = output("one", "3840x2160@60", 2, "0x0", 1);
    compare(Geometry.rect(rotated, {}), { x: 0, y: 0, width: 1080, height: 1920 });
    compare(Geometry.rect(rotated, { one: { mode: "1920x1080@60", scale: 1 } }).height, 1920);
  }

  function test_all_three_side_alignments_are_distinct() {
    const tall = { x: 0, y: 0, width: 1920, height: 1200 };
    const short = { width: 1920, height: 1080 };
    compare(Geometry.adjacent(short, tall, "right", "start"), { x: 1920, y: 0 });
    compare(Geometry.adjacent(short, tall, "right", "center"), { x: 1920, y: 60 });
    compare(Geometry.adjacent(short, tall, "right", "end"), { x: 1920, y: 120 });
    compare(Geometry.adjacent(short, tall, "left", "center"), { x: -1920, y: 60 });
  }

  function test_vertical_alignment_and_negative_positions() {
    const wide = { x: -100, y: -50, width: 1920, height: 1080 };
    const narrow = { width: 1080, height: 1920 };
    compare(Geometry.adjacent(narrow, wide, "bottom", "start"), { x: -100, y: 1030 });
    compare(Geometry.adjacent(narrow, wide, "bottom", "center"), { x: 320, y: 1030 });
    compare(Geometry.adjacent(narrow, wide, "top", "end"), { x: 740, y: -1970 });
  }

  function test_drag_chooses_only_exact_edge_alignments() {
    const outputs = [output("tall", "1920x1200@60", 1, "0x0"), output("short", "1920x1080@60", 1, "1920x0")];
    for (const y of [0, 60, 120])
      compare(Geometry.snap(outputs, {}, "short", 1915, y + 3), { x: 1920, y });
    // Free offsets resolve to the closest allowed placement, even far away.
    compare(Geometry.snap(outputs, {}, "short", 2100, 35), { x: 1920, y: 60 });
    compare(Geometry.snap(outputs, {}, "short", 6000, 400), { x: 1920, y: 120 });
    compare(Geometry.snap(outputs, {}, "short", -2100, 35), { x: -1920, y: 60 });
  }

  function test_drag_rejects_positions_occupied_by_a_third_display() {
    const outputs = [output("left", "1920x1080@60", 1, "0x0"), output("right", "1920x1080@60", 1, "1920x0"), output("moving", "1920x1080@60", 1, "0x1080")];
    const snapped = Geometry.snap(outputs, {}, "moving", 1920, 0);
    verify(!(snapped.x === 1920 && snapped.y === 0));
    for (const other of outputs.slice(0, 2)) {
      const box = Geometry.rect(other, {});
      verify(!(snapped.x < box.x + box.width && snapped.x + 1920 > box.x && snapped.y < box.y + box.height && snapped.y + 1080 > box.y));
    }
  }
}
