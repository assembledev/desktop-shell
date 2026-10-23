import QtQuick

ListModel {
  id: root

  property var entries: []
  property string outputName: ""

  onEntriesChanged: reconcile()
  onOutputNameChanged: reconcile()

  function reconcile() {
    const rows = entries.filter(entry => entry.outputName === outputName);
    const kinds = rows.map(entry => entry.kind);
    // Update roles in place so repeated steps retain their animated delegates.
    for (let i = count - 1; i >= 0; i--) {
      if (kinds.indexOf(get(i).kind) < 0)
        remove(i);
    }
    for (let i = 0; i < rows.length; i++) {
      let existing = -1;
      for (let j = i; j < count; j++) {
        if (get(j).kind === rows[i].kind) {
          existing = j;
          break;
        }
      }
      if (existing < 0)
        insert(i, rows[i]);
      else {
        if (existing !== i)
          move(existing, i, 1);
        set(i, rows[i]);
      }
    }
  }
}
