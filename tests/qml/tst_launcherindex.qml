import QtQuick
import QtTest
import "../../src/modules/launcher/LauncherSearch.js" as Search

TestCase {
  name: "LauncherWindowIndex"

  function test_all_matching_apps_keep_counts_but_focus_uses_strongest_identity() {
    const apps = [
      { id: "by-exec", execString: "env FLAG=1 /bin/editor %U" },
      { id: "editor" },
      { id: "by-startup", startupClass: "Editor" }
    ];
    const win = { address: "0x1", class: "editor" };
    const index = Search.indexWindows(apps, [win]);
    for (const app of apps)
      compare(index.byApp[Search.desktopEntryFileId(app)], [win]);
    compare(index.focusCandidates.length, 1);
    compare(index.focusCandidates[0].entry.id, "by-startup");
  }

  function test_equal_scores_preserve_app_order_and_unknown_windows() {
    const apps = [{ id: "first", startupClass: "editor" }, { id: "second", startupClass: "editor" }];
    const clients = [
      { address: "0x1", class: "editor" },
      { address: "0x2", class: "unknown", title: "A window" }
    ];
    const index = Search.indexWindows(apps, clients);
    compare(index.focusCandidates[0].entry.id, "first");
    compare(index.focusCandidates[1].entry.name, "unknown");
    compare(index.focusCandidates[1].window.address, "0x2");
  }

  function test_initial_class_and_unrelated_titles() {
    const apps = [{ id: "editor" }];
    const clients = [
      { address: "0x1", class: "changed", initialClass: "editor" },
      { address: "0x2", class: "browser", title: "editor" }
    ];
    const index = Search.indexWindows(apps, clients);
    compare(index.byApp["editor.desktop"], [clients[0]]);
    compare(index.focusCandidates[1].entry.id, "window-browser");
  }

  function test_new_snapshot_removes_stale_matches() {
    const apps = [{ id: "editor" }];
    const win = { address: "0x1", class: "editor" };
    const oldIndex = Search.indexWindows(apps, [win]);
    const newIndex = Search.indexWindows(apps, []);
    compare(oldIndex.byApp["editor.desktop"].length, 1);
    compare(newIndex.byApp["editor.desktop"].length, 0);
    compare(newIndex.focusCandidates.length, 0);
  }

  function test_exec_is_parsed_once_per_app_per_snapshot() {
    let reads = 0;
    const app = { id: "editor" };
    Object.defineProperty(app, "execString", { get: function() { reads++; return "/bin/editor %U"; } });
    const clients = [];
    for (let i = 0; i < 20; i++)
      clients.push({ address: "0x" + i, class: "editor" });
    const index = Search.indexWindows([app], clients);
    compare(index.byApp["editor.desktop"].length, 20);
    compare(reads, 1);
  }

  QtObject {
    id: state
    property var apps: []
    property var clients: []
    property string query: ""
    readonly property var index: Search.indexWindows(apps, clients)
  }

  function test_query_does_not_rebuild_identity_index() {
    state.apps = [{ id: "editor" }];
    state.clients = [{ address: "0x1", class: "editor" }];
    const initial = state.index;
    state.query = "ed";
    verify(state.index === initial);
    state.clients = [];
    verify(state.index !== initial);
    compare(state.index.byApp["editor.desktop"].length, 0);
  }
}
