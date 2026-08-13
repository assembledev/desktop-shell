.pragma library
.import "LauncherSearch.js" as LauncherSearch
.import "../common/HyprlandWindow.js" as HyprlandWindow

function applicationForEntryId(applications, entryId) {
  const expected = String(entryId || "");
  return (applications || []).find(function(app) {
    return LauncherSearch.desktopEntryFileId(app) === expected;
  }) || null;
}

function matchingWindows(app, windows) {
  return (windows || []).filter(function(win) {
    return LauncherSearch.appWindowManageableTechnicalIdentityScore(app, win) >= 0;
  });
}

function windowWorkspace(win) {
  const workspace = Number(win?.workspace?.id);
  return Number.isInteger(workspace) ? workspace : 0;
}

function profileReady(entries, applications) {
  return entries.length > 0 && entries.every(function(spec) {
    return applicationForEntryId(applications, spec.id) !== null;
  });
}

function snapshot(entries, applications, windows) {
  let openCount = 0;
  let placedCount = 0;

  for (const spec of entries) {
    const app = applicationForEntryId(applications, spec.id);
    if (!app)
      continue;
    const matches = matchingWindows(app, windows);
    if (matches.length === 0)
      continue;
    openCount++;
    if (matches.every(function(win) { return windowWorkspace(win) === spec.workspace; }))
      placedCount++;
  }

  return {
    open: openCount,
    placed: placedCount,
    total: entries.length
  };
}

function reconcilePlan(entries, applications, windows, leases, now, leaseMs) {
  const moves = [];
  const launches = [];
  const nextLeases = Object.assign({}, leases || {});

  for (const spec of entries) {
    const app = applicationForEntryId(applications, spec.id);
    if (!app)
      continue;

    const matches = matchingWindows(app, windows);
    if (matches.length > 0) {
      for (const win of matches) {
        const address = String(win.address || "");
        if (address.length > 0 && windowWorkspace(win) !== spec.workspace)
          moves.push({ address: address, workspace: spec.workspace });
      }
      continue;
    }

    if (Object.prototype.hasOwnProperty.call(nextLeases, spec.id)) {
      const startedAt = Number(nextLeases[spec.id]);
      if (Number.isFinite(startedAt) && now - startedAt < leaseMs)
        continue;
    }

    nextLeases[spec.id] = now;
    launches.push({ id: spec.id, workspace: spec.workspace });
  }

  return {
    launches: launches,
    moves: moves,
    leases: nextLeases
  };
}

function orderedMoves(moves, activeAddress) {
  const active = HyprlandWindow.normalizedAddress(activeAddress);
  const normalized = (moves || []).map(function(move) {
    return {
      address: HyprlandWindow.normalizedAddress(move?.address),
      workspace: Number(move?.workspace)
    };
  }).filter(function(move) {
    return move.address.length > 0
      && Number.isInteger(move.workspace)
      && move.workspace > 0;
  });

  return normalized.filter(function(move) { return move.address !== active; })
    .concat(normalized.filter(function(move) { return move.address === active; }));
}

function movedWindowEvent(data) {
  const fields = String(data || "").split(",");
  if (fields.length < 2)
    return null;

  const address = HyprlandWindow.normalizedAddress(fields[0]);
  const workspace = Number(fields[1]);
  if (address.length === 0 || !Number.isInteger(workspace) || workspace <= 0)
    return null;
  return { address: address, workspace: workspace };
}

function moveApplied(move, windows) {
  const address = HyprlandWindow.normalizedAddress(move?.address);
  const workspace = Number(move?.workspace);
  if (address.length === 0 || !Number.isInteger(workspace))
    return false;

  return (windows || []).some(function(win) {
    return HyprlandWindow.normalizedAddress(win?.address) === address
      && windowWorkspace(win) === workspace;
  });
}

function movesApplied(moves, windows) {
  return (moves || []).every(function(move) { return moveApplied(move, windows); });
}
