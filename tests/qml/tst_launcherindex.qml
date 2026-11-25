import QtQuick
import QtTest
import "../../src/modules/launcher/LauncherSearch.js" as Search

TestCase {
  name: "LauncherWindowIndex"

  function indexWindows(apps, clients) {
    return Search.indexWindows(Search.prepareWindowIndexApps(apps), clients);
  }

  QtObject {
    id: snapshot
    signal succeeded(var clients)
    property list<var> clients: []
    property var manageable: []
    onSucceeded: function(clients) { manageable = Search.manageableClients(clients); }
  }

  function test_snapshot_signal_preserves_manageable_clients() {
    const clients = [
      { address: "0x1", mapped: true, hidden: false },
      { address: "0x2", hidden: true },
      { address: "0x3", mapped: false },
      { address: "" },
      null,
      { address: "0x4" }
    ];
    snapshot.clients = clients;
    compare(Search.manageableClients(snapshot.clients), [clients[0], clients[5]]);
    snapshot.succeeded(snapshot.clients);
    compare(snapshot.manageable, [clients[0], clients[5]]);
    snapshot.succeeded([]);
    compare(snapshot.manageable, []);
    compare(Search.manageableClients(null), []);
  }

  function test_all_matching_apps_keep_counts_but_focus_uses_strongest_identity() {
    const apps = [
      { id: "by-exec", execString: "env FLAG=1 /bin/editor %U" },
      { id: "editor" },
      { id: "by-startup", startupClass: "Editor" }
    ];
    const win = { address: "0x1", class: "editor" };
    const index = indexWindows(apps, [win]);
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
    const index = indexWindows(apps, clients);
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
    const index = indexWindows(apps, clients);
    compare(index.byApp["editor.desktop"], [clients[0]]);
    compare(index.focusCandidates[1].entry.id, "window-browser");
  }

  function test_new_snapshot_removes_stale_matches() {
    const apps = [{ id: "editor" }];
    const win = { address: "0x1", class: "editor" };
    const oldIndex = indexWindows(apps, [win]);
    const newIndex = indexWindows(apps, []);
    compare(oldIndex.byApp["editor.desktop"].length, 1);
    compare(newIndex.byApp["editor.desktop"].length, 0);
    compare(newIndex.focusCandidates.length, 0);
  }

  function test_exec_is_parsed_once_when_preparing_applications() {
    let reads = 0;
    const app = { id: "editor" };
    Object.defineProperty(app, "execString", { get: function() { reads++; return "/bin/editor %U"; } });
    const clients = [];
    for (let i = 0; i < 20; i++)
      clients.push({ address: "0x" + i, class: "editor" });
    const prepared = Search.prepareWindowIndexApps([app]);
    const index = Search.indexWindows(prepared, clients);
    compare(index.byApp["editor.desktop"].length, 20);
    compare(Search.indexWindows(prepared, clients.slice(1)).byApp["editor.desktop"].length, 19);
    compare(reads, 1);
  }

  function test_matches_from_distinct_classes_keep_client_order_without_duplicates() {
    const apps = [{id: "editor", startupClass: "start", execString: "/bin/tool"}];
    const clients = [
      {address: "0xa", class: "tool", initialClass: "editor"},
      {address: "0xb", class: "editor"},
      {address: "0xc", class: "start", initialClass: "tool"}
    ];
    const index = indexWindows(apps, clients);
    compare(index.byApp["editor.desktop"], clients);
    compare(index.focusCandidates.map(candidate => candidate.window), clients);
    compare(index.focusCandidates.map(candidate => candidate.identityScore), [580, 580, 600]);
  }

  QtObject {
    id: state
    property var apps: []
    property var clients: []
    property string query: ""
    readonly property var preparedApps: Search.prepareWindowIndexApps(apps)
    readonly property var index: Search.indexWindows(preparedApps, clients)
  }

  QtObject {
    id: mutableApp
    property string startupClass: ""
    property string execString: ""
  }

  function test_application_identity_changes_refresh_the_window_index() {
    const client = { address: "0x1", class: "new-class" };
    state.apps = [mutableApp];
    state.clients = [client];
    compare(state.index.byApp[""], []);
    mutableApp.startupClass = "New-Class";
    compare(state.index.byApp[""], [client]);
    mutableApp.startupClass = "";
  }

  function test_query_does_not_rebuild_identity_index() {
    state.apps = [{ id: "editor" }];
    state.clients = [{ address: "0x1", class: "editor" }];
    const initial = state.index;
    const prepared = state.preparedApps;
    state.query = "ed";
    verify(state.index === initial);
    state.clients = [];
    verify(state.index !== initial);
    verify(state.preparedApps === prepared);
    compare(state.index.byApp["editor.desktop"].length, 0);
    state.apps = [{ id: "other" }];
    verify(state.preparedApps !== prepared);
    compare(state.index.byApp["other.desktop"].length, 0);
  }
  function test_icon_identity_index_preserves_priority_and_ties() {
    const apps = [
      { id: "exec-first", execString: "env FLAG=1 /bin/editor %U" },
      { id: "editor" },
      { id: "startup-first", startupClass: "EDITOR" },
      { id: "startup-second", startupClass: "other" },
      { id: "constructor", execString: "/bin/special" }
    ];
    const index = Search.applicationIdentityIndex(apps);
    compare(Search.applicationForWindow(index, {class: "editor"}).id, "startup-first");
    compare(Search.applicationForWindow(index, {class: "other", initialClass: "editor"}).id, "startup-first");
    compare(Search.applicationForWindow(index, {class: "constructor"}).id, "constructor");
    compare(Search.applicationForWindow(index, {class: "unknown"}), null);
    compare(Search.applicationForWindow(index, {class: "editor", hidden: true}), null);
    compare(Search.applicationForWindow(Search.applicationIdentityIndex([]), {class: "editor"}), null);
  }

  function test_icon_lookups_do_not_reparse_exec() {
    let reads = 0;
    const app = { id: "test" };
    Object.defineProperty(app, "execString", {get: function() { reads++; return "/bin/editor"; }});
    const index = Search.applicationIdentityIndex([app]);
    for (let i = 0; i < 100; i++)
      compare(Search.applicationForWindow(index, {class: "editor"}), app);
    compare(reads, 1);
  }
}
