.pragma library

// Flatten expanded groups into independent ListView rows; never truncate stored history.
function entries(groups, expanded) {
  const rows = [];
  for (const group of groups) {
    const items = expanded[group.key] ? group.items : group.items.slice(0, 1);
    for (let i = 0; i < items.length; i++)
      rows.push({item: items[i], group: group, first: i === 0});
  }
  return rows;
}
