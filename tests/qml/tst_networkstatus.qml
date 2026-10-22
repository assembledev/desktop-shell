import QtQuick
import QtTest
import "../../src/modules/network/NetworkStatus.js" as Status

TestCase {
  name: "NetworkStatus"
  function test_signal_levels_data() {
    return [
      { signal: null, icon: "wifi" }, { signal: 0, icon: "wifi-minimal" },
      { signal: 24, icon: "wifi-minimal" }, { signal: 25, icon: "wifi-weak" },
      { signal: 49, icon: "wifi-weak" }, { signal: 50, icon: "wifi-medium" },
      { signal: 74, icon: "wifi-medium" }, { signal: 75, icon: "wifi" },
      { signal: 100, icon: "wifi" }
    ];
  }
  function test_signal_levels(data) { compare(Status.signalLevel(data.signal), data.icon); }
  function test_traffic_handover_reset_and_suspend() {
    const sample = { interface: "wlan0", rxBytes: 1000, txBytes: 2000 };
    const first = Status.traffic(null, sample, 1000);
    compare(first.receive, null);
    const second = Status.traffic(first.baseline, { interface: "wlan0", rxBytes: 5000, txBytes: 3000 }, 3000);
    compare(second.receive, 2000);
    compare(second.transmit, 500);
    compare(Status.traffic(second.baseline, sample, 5000).receive, null);
    compare(Status.traffic(first.baseline, { interface: "eth0", rxBytes: 5000, txBytes: 3000 }, 3000).receive, null);
    compare(Status.traffic(first.baseline, sample, 30000).receive, null);
    compare(Status.traffic(first.baseline, sample, 1000).receive, null);
    compare(Status.traffic(first.baseline, { interface: "wlan0", rxBytes: null, txBytes: null }, 3000).receive, null);
  }
  function test_units_and_unavailable() {
    compare(Status.rate(null), "—");
    compare(Status.rate(0), "0 B/s");
    compare(Status.rate(84000), "84 KB/s");
    compare(Status.rate(1200000), "1.2 MB/s");
    compare(Status.linkRate(null), "—");
    compare(Status.linkRate(866.7), "867 Mb/s");
    compare(Status.linkRate(1000), "1 Gb/s");
    compare(Status.band(2412), "2.4 GHz");
    compare(Status.band(5300), "5 GHz");
    compare(Status.band(6115), "6 GHz");
    compare(Status.band(null), "");
  }
}
