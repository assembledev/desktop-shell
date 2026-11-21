import QtQuick
import QtTest
import "../../src/modules/bar/RamStatus.js" as RamStatus

TestCase {
  name: "RamStatus"
  function test_available_memory_includes_reclaimable_cache() {
    const sample = RamStatus.parse("MemFree: 1048576 kB\nMemTotal: 8388608 kB\nMemAvailable: 4194304 kB\nCached: 123 kB\n");
    verify(sample.available);
    compare(sample.ram, 0.5);
    compare(sample.ramText, "4.0/8G");
    compare(sample.details.totalKiB, 8388608);
    compare(sample.details.usedKiB, 4194304);
    compare(sample.details.reclaimableKiB, 3145728);
  }
  function test_reclaimable_without_positive_estimate_data() {
    return [
      { tag: "missing MemFree", fields: "" },
      { tag: "kernel reserves", fields: "MemFree: 512 kB\n" },
      { tag: "no additional headroom", fields: "MemFree: 384 kB\n" }
    ];
  }
  function test_reclaimable_without_positive_estimate(row) {
    const sample = RamStatus.parse("MemTotal: 1024 kB\nMemAvailable: 384 kB\n" + row.fields);
    compare(sample.details.usedKiB, 640);
    compare(sample.details.reclaimableKiB, 0);
  }
  function test_unavailable_swap_data() {
    return [
      {tag: "missing", fields: ""},
      {tag: "disabled", fields: "SwapTotal: 0 kB\nSwapFree: 0 kB\n"},
      {tag: "invalid", fields: "SwapTotal: 4096 kB\nSwapFree: 8192 kB\n"}
    ];
  }
  function test_unavailable_swap(row) {
    const sample = RamStatus.parse("MemTotal: 1024 kB\nMemAvailable: 384 kB\n" + row.fields);
    verify(sample.available);
    compare(sample.details.usedKiB, 640);
    compare(sample.details.swap, null);
  }
  function test_swap_occupancy() {
    const sample = RamStatus.parse("MemTotal: 8388608 kB\nMemAvailable: 4194304 kB\nSwapTotal: 1048576 kB\nSwapFree: 786432 kB\n");
    compare(sample.details.swap.totalKiB, 1048576);
    compare(sample.details.swap.usedKiB, 262144);
    const unused = RamStatus.parse("MemTotal: 8388608 kB\nMemAvailable: 4194304 kB\nSwapTotal: 1048576 kB\nSwapFree: 1048576 kB\n");
    compare(unused.details.swap.usedKiB, 0);
  }
  function test_top_processes() {
    const rows = RamStatus.topProcesses("  8 512 browser helper \n 72 320 <app>\nmalformed\n 15 0 idle\n109 64 shell\n114 32 other\n");
    compare(rows, [
      { pid: 8, rssKiB: 512, name: "browser helper" },
      { pid: 72, rssKiB: 320, name: "<app>" },
      { pid: 109, rssKiB: 64, name: "shell" }
    ]);
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
    const sample = RamStatus.parse(row.text);
    compare(sample.available, false);
    compare(sample.ramText, "--");
    compare(sample.details, null);
  }
}
