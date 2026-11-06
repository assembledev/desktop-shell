# Persist observed drain from UPower; native readings supply presentation.
def nonnegative: if type == "number" and . >= 0 then . else 0 end;
def decimal1:
  (. * 10 | round) / 10 | tostring | if contains(".") then . else . + ".0" end;
def watts($wh; $seconds):
  if $wh > 0 and $seconds > 0 then ($wh * 3600 / $seconds | decimal1) + " W" else "--" end;

if ($sample | type) != "object"
  or ($sample.now | type) != "number" or $sample.now <= 0
  or ($sample.energyUwh | type) != "number" or $sample.energyUwh < 0
  or ($sample.status | type) != "string"
  or ($sample.continuous | type) != "boolean"
then error("invalid battery sample") else . end |
$sample.now as $now |
$sample.energyUwh as $energy |
$sample.status as $status |
(try ($state | fromjson) catch {}) |
if type == "object" and .bootId == $bootId then . else {} end |
(.lastTs | nonnegative) as $previousTime |
(.lastEnergyUwh | nonnegative) as $previousEnergy |
(.totalWh | nonnegative) as $previousWh |
(.totalSeconds | nonnegative) as $previousSeconds |
(if $sample.continuous and $status == "Discharging" and .lastStatus == "Discharging"
    and $energy > 0 and $previousEnergy >= $energy and $now > $previousTime
 then $now - $previousTime else 0 end) as $seconds |
(if $seconds > 0 then ($previousEnergy - $energy) / 1000000 else 0 end) as $wh |
($previousWh + $wh) as $totalWh |
($previousSeconds + $seconds) as $totalSeconds |
((if $now < $previousTime then []
  else .history // [] | if type == "array" then . else [] end end) |
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
{
  bootId: $bootId, lastTs: $now, lastStatus: $status, lastEnergyUwh: $energy,
  totalWh: $totalWh, totalSeconds: $totalSeconds, history: $history
},
{
  bootAverage: watts($totalWh; $totalSeconds), hourAverage: watts($hour.wh; $hour.seconds),
  bootWh: $totalWh, bootSeconds: $totalSeconds, hourWh: $hour.wh, hourSeconds: $hour.seconds
}
