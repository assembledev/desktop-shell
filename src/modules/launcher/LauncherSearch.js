.pragma library

function normalize(value) {
  return String(value || "").toLowerCase();
}

function desktopEntryFileId(app) {
  const id = String(app?.id || "");
  // Quickshell derives DesktopEntry.id from completeBaseName(), which removes
  // exactly the final .desktop suffix. Restore that suffix unconditionally so
  // IDs such as org.telegram.desktop map back to org.telegram.desktop.desktop.
  return id.length > 0 ? id + ".desktop" : "";
}

function execTokens(value) {
  const matches = String(value || "").match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) || [];
  return matches.map(function(token) {
    if (token.length >= 2
        && ((token[0] === '"' && token[token.length - 1] === '"')
            || (token[0] === "'" && token[token.length - 1] === "'")))
      return token.slice(1, -1);
    return token;
  });
}

function executableName(value) {
  const tokens = execTokens(value);
  if (tokens.length === 0)
    return "";

  let index = 0;
  const first = normalize(tokens[0]).split("/").pop();
  if (first === "env") {
    index++;
    while (index < tokens.length) {
      const token = tokens[index];
      if (token === "-u" || token === "--unset") {
        index += 2;
        continue;
      }
      if (token.startsWith("--unset=")
          || token.startsWith("-")
          || /^[A-Za-z_][A-Za-z0-9_]*=/.test(token)) {
        index++;
        continue;
      }
      break;
    }
  }

  if (index >= tokens.length)
    return "";
  return normalize(tokens[index]).split("/").pop().replace(/\.desktop$/, "");
}

function appWindowIdentityScore(app, win) {
  if (!win || win.hidden)
    return -1;

  const startup = normalize(app?.startupClass);
  const name = normalize(app?.name);
  const id = normalize(String(app?.id || "").replace(/\.desktop$/, ""));
  const exec = executableName(app?.execString);
  const cls = normalize(win.class || win.initialClass);
  const title = normalize(win.title || win.initialTitle);

  if (startup.length > 0 && cls === startup)
    return 600;
  if (id.length > 0 && cls === id)
    return 580;
  if (exec.length > 0 && cls === exec)
    return 560;
  if (id.length > 0 && cls.indexOf(id) >= 0)
    return 520;
  if (name.length > 0 && cls === name)
    return 500;
  if (name.length > 0 && title.indexOf(name) >= 0)
    return 100;
  return -1;
}

function applicationForWindow(applications, win) {
  let best = null;
  let bestScore = -1;

  for (const app of applications || []) {
    const score = appWindowIdentityScore(app, win);
    if (score > bestScore) {
      best = app;
      bestScore = score;
    }
  }

  return best;
}

function fuzzySubsequenceScore(query, target) {
  if (query.length < 2)
    return -1;

  let queryIndex = 0;
  let spread = 0;
  let firstMatch = -1;
  let lastMatch = -1;
  for (let i = 0; i < target.length && queryIndex < query.length; i++) {
    if (target[i] === query[queryIndex]) {
      if (firstMatch < 0)
        firstMatch = i;
      if (lastMatch >= 0)
        spread += i - lastMatch - 1;
      lastMatch = i;
      queryIndex++;
    }
  }

  if (queryIndex !== query.length)
    return -1;

  // Fuzzy matches should resemble a compact abbreviation, not letters spread
  // across an unrelated sentence or generated path.
  const span = lastMatch - firstMatch + 1;
  if (span > query.length * 3)
    return -1;

  return Math.max(0, 90 - spread - target.length * 0.15);
}

function fieldScore(query, value, exact, prefix, wordPrefix, contains, fuzzy) {
  const target = normalize(value).trim();
  if (target.length === 0)
    return -1;

  if (target === query)
    return exact;
  if (target.startsWith(query))
    return prefix;

  const words = target.split(/[\s._:/-]+/);
  for (const word of words) {
    if (word.startsWith(query))
      return wordPrefix;
  }

  const index = target.indexOf(query);
  if (index >= 0)
    return contains - Math.min(index, 99);

  if (fuzzy < 0)
    return -1;
  const fuzzyResult = fuzzySubsequenceScore(query, target);
  return fuzzyResult < 0 ? -1 : fuzzy + fuzzyResult;
}

function appMatchScore(query, app) {
  if (query.length === 0)
    return 0;

  // Only human-facing names get fuzzy matching. Technical identifiers use
  // literal matching, and Exec is reduced to its executable basename so Nix
  // store hashes and wrapper environment variables never become search text.
  let best = fieldScore(query, app?.name, 7000, 6800, 6600, 6400, 6100);
  best = Math.max(best, fieldScore(query, app?.genericName, 5900, 5700, 5500, 5300, 5000));
  best = Math.max(best, fieldScore(query, app?.id, 4900, 4700, 4500, 4300, -1));
  best = Math.max(best, fieldScore(query, app?.startupClass, 4900, 4700, 4500, 4300, -1));
  best = Math.max(best, fieldScore(query, executableName(app?.execString), 4800, 4600, 4400, 4200, -1));
  best = Math.max(best, fieldScore(query, app?.comment, 3800, 3600, 3400, 3200, -1));
  return best;
}

function windowMatchScore(query, win) {
  if (query.length === 0)
    return 0;

  let best = fieldScore(query, win?.title, 6900, 6700, 6500, 6300, 6000);
  best = Math.max(best, fieldScore(query, win?.initialTitle, 6800, 6600, 6400, 6200, 5900));
  return best;
}

function tabMatchScore(query, tab) {
  if (query.length === 0)
    return 0;

  let best = fieldScore(query, tab?.title, 6900, 6700, 6500, 6300, 6000);
  best = Math.max(best, fieldScore(query, tab?.group, 5900, 5700, 5500, 5300, 5000));
  // Hosts are technical identifiers: literal matching keeps fuzzy search from
  // manufacturing matches while still making an explicit port searchable.
  best = Math.max(best, fieldScore(query, tab?.host, 5600, 5400, 5200, 5000, -1));
  return best;
}
