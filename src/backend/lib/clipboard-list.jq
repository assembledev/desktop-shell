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
              "^\\[\\[ binary data .+ (?<kind>png|jpg|jpeg|webp|bmp|gif) (?<dimensions>[0-9]+x[0-9]+) \\]\\]$"
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
        image: ($image != null)
      }
  )
