import QtQuick
import QtTest
import "../../src/modules/bar"

TestCase {
  id: suite
  name: "RamDetails"
  width: 320
  height: 300
  visible: true
  when: windowShown

  Component {
    id: detailsCard

    RamDetails {
      width: 280
      height: implicitHeight
      colors: ({
        borderSubtle: "#424a68", borderMuted: "#343b55", accent: "#a78bfa",
        resource: "#9ece6a", textPrimary: "#eef0f8", textSecondary: "#c7ccdc", textMuted: "#929cb2",
        uiFontFamily: "Fira Sans", fontFamily: "FiraCode Nerd Font"
      })
      details: ({ totalKiB: 33554432, usedKiB: 12582912, reclaimableKiB: 6291456, swap: null })
      processes: null
    }
  }

  SignalSpy {
    id: pidCopy
    signalName: "copyPid"
  }

  function test_click_pid() {
    const card = createTemporaryObject(detailsCard, suite, {
      processes: [{ name: "browser", pid: 1001, rssKiB: 1234567 }]
    });
    verify(card);
    pidCopy.target = card;
    const button = findChild(card, "copyPid1001");
    verify(button);
    tryVerify(() => button.width > 0 && button.height > 0);
    mouseClick(button);
    compare(pidCopy.count, 1);
    compare(pidCopy.signalArguments[0][0], "1001");
  }

  function test_process_updates_keep_card_height() {
    const card = createTemporaryObject(detailsCard, suite);
    verify(card);
    wait(30);
    const initialHeight = card.implicitHeight;
    const rows = [
      { name: "browser", pid: 1001, rssKiB: 1234567 },
      { name: "editor", pid: 2002, rssKiB: 512000 },
      { name: "shell", pid: 3003, rssKiB: 256000 }
    ];
    for (const sample of [rows, rows.slice(0, 1), [], null]) {
      card.processes = sample;
      wait(30);
      compare(card.implicitHeight, initialHeight);
    }
  }

  function test_configured_swap_has_room_when_unused() {
    const card = createTemporaryObject(detailsCard, suite);
    verify(card);
    wait(30);
    const withoutSwap = card.implicitHeight;
    card.details = Object.assign({}, card.details, { swap: { totalKiB: 33554432, usedKiB: 0 } });
    tryVerify(() => card.implicitHeight > withoutSwap);
    const idleSwap = card.implicitHeight;
    card.details = Object.assign({}, card.details, { swap: { totalKiB: 33554432, usedKiB: 1024 } });
    wait(30);
    compare(card.implicitHeight, idleSwap);
  }
}
