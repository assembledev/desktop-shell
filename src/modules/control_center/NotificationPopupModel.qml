import QtQml.Models

SortFilterProxyModel {
  id: root

  property string outputName: ""

  // Forward row changes without rebuilding untouched toast delegates.
  filters: ValueFilter {
    roleName: "outputName"
    value: root.outputName
  }
}
