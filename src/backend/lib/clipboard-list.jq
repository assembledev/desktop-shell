split("\n")
| map(
    select(length > 0)
    | . as $record
    | (index("\t")) as $separator
    | if $separator == null then
        { entryId: ., label: . }
      else
        {
          entryId: .[0:$separator],
          label: .[$separator + 1:]
        }
      end
    | . as $entry
    | (
        [
          $entry.label
          | capture(
              "^\\[\\[ binary data (?<size>.+) (?<kind>png|jpg|jpeg|webp|bmp|gif) (?<dimensions>[0-9]+x[0-9]+) \\]\\]$"
            )
        ]
        | first // null
      ) as $image
    | {
        entryId: $entry.entryId,
        label: $entry.label,
        record: ($record | @base64),
        preview: "",
        kind: ($image.kind // "text"),
        dimensions: ($image.dimensions // ""),
        size: ($image.size // ""),
        createdAt: 0,
        image: ($image != null)
      }
  )
| map(. as $entry | .createdAt = (
    if (($ages[0] // {})[$entry.entryId].record // "") == $entry.record then
      (($ages[0] // {})[$entry.entryId].createdAt // 0)
    else 0 end
  ))
| if $capturedAt > 0 and length > 0 and .[0].record != $previous then
    .[0].createdAt = $capturedAt
  else . end
