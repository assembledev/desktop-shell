.pragma library

function normalizedTitle(value) {
  return String(value || "").trim().replace(/\s+/g, " ").toLowerCase();
}

function windowDisplaysTab(win, tab, browserName) {
  const windowTitle = normalizedTitle(win?.title || win?.initialTitle);
  const tabTitle = normalizedTitle(tab?.title);
  if (windowTitle.length === 0 || tabTitle.length === 0)
    return false;
  if (windowTitle === tabTitle)
    return true;

  const name = normalizedTitle(browserName);
  if (name.length === 0)
    return false;
  return [" — ", " – ", " - "].some(function(separator) {
    return windowTitle === tabTitle + separator + name;
  });
}

function windowForTab(tab, tabs, browserWindows, browserName) {
  const candidates = (browserWindows || []).filter(function(win) {
    return String(win?.address || "").length > 0;
  });
  if (candidates.length === 0)
    return null;
  if (candidates.length === 1)
    return candidates[0];

  const windowId = Number(tab?.windowId);
  if (!Number.isInteger(windowId))
    return null;
  const activeTab = (tabs || []).find(function(candidate) {
    return Number(candidate?.windowId) === windowId && candidate?.active === true;
  });
  if (!activeTab)
    return null;

  const matches = candidates.filter(function(win) {
    return windowDisplaysTab(win, activeTab, browserName);
  });
  return matches.length === 1 ? matches[0] : null;
}
