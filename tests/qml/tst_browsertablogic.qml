import QtQuick
import QtTest
import "../../src/modules/launcher/BrowserTabLogic.js" as BrowserTabLogic

TestCase {
  name: "BrowserTabLogic"

  function test_resolves_the_only_browser_window() {
    const win = { address: "0xabc", title: "Current tab — LibreWolf" };
    compare(BrowserTabLogic.windowForTab(
      { tabId: 2, windowId: 1 },
      [],
      [win],
      "LibreWolf"
    ), win);
  }

  function test_resolves_window_from_the_active_tab_title() {
    const first = { address: "0xaaa", title: "First current — LibreWolf" };
    const second = { address: "0xbbb", title: "Second current — LibreWolf" };
    const tabs = [
      { tabId: 1, windowId: 10, title: "First current", active: true },
      { tabId: 2, windowId: 10, title: "Target", active: false },
      { tabId: 3, windowId: 20, title: "Second current", active: true }
    ];
    compare(BrowserTabLogic.windowForTab(tabs[1], tabs, [first, second], "LibreWolf"), first);
  }

  function test_does_not_guess_between_ambiguous_windows() {
    const tabs = [
      { tabId: 1, windowId: 10, title: "Same", active: true },
      { tabId: 2, windowId: 10, title: "Target", active: false }
    ];
    compare(BrowserTabLogic.windowForTab(tabs[1], tabs, [
      { address: "0xaaa", title: "Same — LibreWolf" },
      { address: "0xbbb", title: "Same — LibreWolf" }
    ], "LibreWolf"), null);
  }
}
