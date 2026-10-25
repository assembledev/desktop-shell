import QtQuick
import QtTest
import "../../src/modules/tailscale/TailscaleStatus.js" as Status

TestCase {
  name: "TailscaleStatus"
  function test_routes_are_distinct() {
    compare(Status.route("direct", "abc"), "Direct");
    compare(Status.route("relay", "abc"), "Relay · ABC");
    compare(Status.route("peer-relay", "abc"), "Peer relay");
    compare(Status.route("idle", "abc"), "Idle");
    compare(Status.route("unknown", "abc"), "Unknown");
    compare(Status.route("offline", "abc"), "Offline");
  }
  function test_late_or_stale_peer_probe_is_not_displayed() {
    const probe = {peerId:"a",observedAt:10000};
    verify(Status.probeMatches(probe, "a", 12000));
    verify(!Status.probeMatches(probe, "b", 12000));
    verify(!Status.probeMatches(probe, "a", 18000));
    verify(!Status.probeMatches(null, "a", 12000));
  }
  function test_paths_are_local_and_decoded_once() {
    compare(Status.localPath("file:///home/user/name%20%23%2520.txt"), "/home/user/name #%20.txt");
    compare(Status.localPath("https://example.invalid/file"), "");
    compare(Status.localPath("file://otherhost/file"), "");
    compare(Status.localPath("file:///bad%ZZ"), "");
  }
  function test_zero_last_seen_is_not_ancient_date() {
    compare(Status.lastSeen("0001-01-01T00:00:00Z", Date.now()), "Offline");
    compare(Status.lastSeen("", Date.now()), "Offline");
  }
  function test_inbox_notifications_follow_new_completed_files() {
    const old = {name:"old.txt",size:3};
    const fresh = {name:"new.txt",size:4};
    let delta = Status.inboxUpdate(null, [old], true);
    compare(delta.added.length, 0);
    delta = Status.inboxUpdate(delta.known, [old, fresh], true);
    compare(delta.added.length, 1);
    compare(delta.added[0].name, "new.txt");
    const known = delta.known;
    compare(Status.inboxUpdate(known, [old, fresh], true).added.length, 0);
    delta = Status.inboxUpdate(known, [], false);
    compare(delta.known, known);
    compare(Status.inboxUpdate(delta.known, [old, fresh], true).added.length, 0);
    delta = Status.inboxUpdate(known, [old], true);
    compare(Status.inboxUpdate(delta.known, [old, fresh], true).added.length, 1);
    compare(Status.inboxUpdate(known, [old, {name:"new.txt",size:9}], true).added.length, 1);
    compare(Status.inboxUpdate(Status.inboxUpdate(null, [], false).known, [old], true).added.length, 0);
  }
  function test_waiting_files_validate_the_daemon_response() {
    compare(Status.waitingFiles(null).length, 0);
    compare(Status.waitingFiles([]).length, 0);
    compare(Status.waitingFiles([{Name:"photo.jpg",Size:12}])[0].name, "photo.jpg");
    for (const value of [{}, [null], [{Name:"bad"}], [{Name:"bad",Size:-1}], [{Name:3,Size:1}], [{Name:"",Size:1}]])
      compare(Status.waitingFiles(value), null);
  }
  function test_notification_uses_literal_names_and_bounded_body() {
    const files = [{name:'<a href="https://example.invalid">&file</a>' ,size:1}, {name:"two",size:2}, {name:"three",size:3}, {name:"four",size:4}];
    const command = Status.receivedNotification(files, "/icon.svg");
    compare(command[0], "notify-send");
    compare(command[3], "/icon.svg");
    compare(command[4], "--action=save=Save");
    compare(command[5], "--");
    compare(command[6], "4 files received");
    verify(command[7].startsWith('&lt;a href="https://example.invalid"&gt;&amp;file&lt;/a&gt;'));
    verify(command[7].endsWith("+2 more"));
    compare(command[7].split("<br/>").length, 3);
    verify(command[7].indexOf("four") < 0);
    compare(Status.receivedNotification([{name:"--option",size:1}], "")[6], "File received");
  }

}
