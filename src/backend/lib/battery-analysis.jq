# One sample updates persisted drain history and the existing UI JSON contract.
def nonnegative: if type == "number" and . >= 0 then . else 0 end;
def integer: nonnegative | floor;
def decimal1:
  (. * 10 | round) / 10 | tostring | if contains(".") then . else . + ".0" end;
def watts($wh; $seconds):
  if $wh > 0 and $seconds > 0 then ($wh * 3600 / $seconds | decimal1) + " W" else "--" end;
def duration:
  if . <= 0 then "--"
  else (. / 60 | round) as $minutes |
    if $minutes >= 60 then
      "\($minutes / 60 | floor)h " + ("0" + ($minutes % 60 | tostring))[-2:] + "m"
    else "\($minutes)m" end
  end;

(try ($state | fromjson) catch {}) |
if type == "object" and .bootId == $bootId then . else {} end |
(.lastTs | integer) as $previousTime |
(.lastEnergyUwh | integer) as $previousEnergy |
(.totalWh | nonnegative) as $previousWh |
(.totalSeconds | integer) as $previousSeconds |
(if $status == "Discharging" and .lastStatus == "Discharging"
    and $energy > 0 and $previousEnergy > $energy
    and $now > $previousTime and $now - $previousTime <= 120
 then $now - $previousTime else 0 end) as $seconds |
(if $seconds > 0 then ($previousEnergy - $energy) / 1000000 else 0 end) as $wh |
($previousWh + $wh) as $totalWh |
($previousSeconds + $seconds) as $totalSeconds |
((.history // [] | if type == "array" then . else [] end) |
  if $seconds > 0 then . + [{start: $previousTime, end: $now, seconds: $seconds, wh: $wh}] else . end |
  map(select(type == "object") | select((.end // 0) >= $now - 3600))) as $history |
(reduce $history[] as $sample ({wh: 0, seconds: 0};
  ($sample.start // (($sample.end // 0) - ($sample.seconds // 0))) as $start |
  ($sample.end // 0) as $end |
  if $end > $now - 3600 and $end > $start then
    ($end - ([$start, $now - 3600] | max)) as $overlap |
    .wh += (($sample.wh // 0) * $overlap / ($end - $start)) |
    .seconds += $overlap
  else . end)) as $hour |
(if $status == "Discharging" and $energy > 0 then
  if $hour.wh > 0 and $hour.seconds > 0 then ($energy / 1000000 * $hour.seconds / $hour.wh | round)
  elif $powerUw > 0 then ($energy * 3600 / $powerUw | round)
  else 0 end
 else 0 end) as $estimate |
{
  bootId: $bootId, lastTs: $now, lastStatus: $status, lastEnergyUwh: $energy,
  totalWh: $totalWh, totalSeconds: $totalSeconds, history: $history
},
{
  available: true, capacity: $capacity, status: $status, power: (if $hasPower then ($powerUw / 1000000 | decimal1) + "W" else "" end),
  analysis: {
    estimateText: (if $status == "Charging" then "charging" elif $status == "Full" then "full" else ($estimate | duration) end),
    estimateSeconds: $estimate,
    currentDraw: (if $status == "Discharging" and $powerUw > 0 then ($powerUw / 1000000 | decimal1) + " W" else "--" end),
    bootAverage: watts($totalWh; $totalSeconds), hourAverage: watts($hour.wh; $hour.seconds),
    bootWh: $totalWh, bootSeconds: $totalSeconds, hourWh: $hour.wh, hourSeconds: $hour.seconds
  }
}
