.pragma library

function rowWidth(count, itemWidth, spacing) {
  const safeCount = Math.max(0, Number(count) || 0);
  if (safeCount === 0)
    return 0;
  return safeCount * itemWidth + (safeCount - 1) * spacing;
}

function workspaceRowWidth(count, compactWidth, expandedWidth, spacing, expandActive) {
  const compact = rowWidth(count, compactWidth, spacing);
  if (!expandActive || count <= 0)
    return compact;
  return compact + Math.max(0, expandedWidth - compactWidth);
}

function minimumTrayWidth(itemCount, iconWidth, overflowWidth) {
  if (itemCount <= 0)
    return 0;
  return itemCount === 1 ? iconWidth : overflowWidth;
}

function availableSideWidth(barWidth, centerWidth, outerMargin, centerGap) {
  return Math.max(0, barWidth / 2 - centerWidth / 2 - outerMargin - centerGap);
}

function shouldUseCompactClock(barWidth, fullClockWidth, minimumLeftWidth,
                               minimumRightWidth, outerMargin, centerGap) {
  const available = availableSideWidth(barWidth, fullClockWidth, outerMargin, centerGap);
  return Math.max(minimumLeftWidth, minimumRightWidth) > available;
}

function shouldExpandActiveWorkspace(availableWidth, count, compactWidth,
                                     expandedWidth, spacing) {
  return workspaceRowWidth(count, compactWidth, expandedWidth, spacing, true) <= availableWidth;
}

function inlineTrayCount(itemCount, widthBudget, iconWidth, expandedSpacing,
                         compactSpacing, overflowWidth) {
  if (itemCount <= 0)
    return 0;

  if (itemCount === 1)
    return 1;

  if (rowWidth(itemCount, iconWidth, expandedSpacing) <= widthBudget)
    return itemCount;

  const roomForIcons = widthBudget - overflowWidth;
  let visibleCount = Math.max(0, Math.min(itemCount - 1,
    Math.floor(roomForIcons / (iconWidth + compactSpacing))));

  if (itemCount - visibleCount === 1 && visibleCount > 0)
    visibleCount--;

  return visibleCount;
}

// Include the irreducible tray footprint even when its budget has run out.
function shouldCompactNetwork(availableWidth, fullStatusWidth, minimumTrayWidth, groupGap) {
  return fullStatusWidth + (minimumTrayWidth > 0 ? minimumTrayWidth + groupGap : 0) > availableWidth;
}
