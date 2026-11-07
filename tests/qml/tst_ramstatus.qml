import QtQuick
import QtTest
import "../../src/modules/bar/RamStatus.js" as RamStatus

TestCase {
  name: "RamStatus"
  function test_available_memory_includes_reclaimable_cache() {
    const sample = RamStatus.parse("MemFree: 1 kB\nMemTotal: 8388608 kB\nMemAvailable: 4194304 kB\nCached: 123 kB\n");
    verify(sample.available);
    compare(sample.ram, 0.5);
    compare(sample.ramText, "4.0/8G");
  }
  function test_invalid_data_data() {
    return [
      {tag:"missing", text:"MemTotal: 8388608 kB\n"},
      {tag:"zero total", text:"MemTotal: 0 kB\nMemAvailable: 0 kB\n"},
      {tag:"inconsistent", text:"MemTotal: 8 kB\nMemAvailable: 9 kB\n"},
      {tag:"bad units", text:"MemTotal: 8 MB\nMemAvailable: 4 MB\n"},
      {tag:"empty", text:""}
    ];
  }
  function test_invalid_data(row) {
    compare(RamStatus.parse(row.text).available, false);
    compare(RamStatus.parse(row.text).ramText, "--");
  }
}
