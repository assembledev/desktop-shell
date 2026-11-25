import QtQuick
import QtTest
import "../../src/modules/common/HyprlandWindow.js" as HyprlandWindow

TestCase {
  name: "SwitcherWorkspaceIndex"

  QtObject {
    id: state

    property var windows: []
    property var workspaces: [1, 2]
    readonly property var index: HyprlandWindow.indexWindowsByWorkspace(windows, validWindow)

    function validWindow(win) {
      const workspace = Number(win?.workspace?.id || 0);
      return String(win?.address || "").length > 0 && workspaces.indexOf(workspace) >= 0 && !win?.hidden;
    }
  }

  function test_preserves_membership_and_window_order() {
    const first = { address: "0xb", workspace: { id: "2" } };
    const second = { address: "0xa", workspace: { id: 2 } };
    const ignored = { address: "0xc", workspace: { id: 3 } };
    state.windows = [first, null, { workspace: { id: 2 } },
      { address: "0xd", workspace: { id: 2 }, hidden: true }, ignored, second];

    compare(state.index[2], [first, second]);
    compare(state.index[3], undefined);
    const initial = state.index;
    verify(state.index === initial);

    state.workspaces = [1, 3];
    compare(state.index[2], undefined);
    compare(state.index[3], [ignored]);
    verify(state.index !== initial);

    state.windows = [];
    compare(state.index[3], undefined);
    state.workspaces = [1, 2];
  }
}
