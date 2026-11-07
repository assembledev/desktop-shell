import QtQuick
import QtQuick.Controls

Button {
  id: button

  // Qt handles Space. Enter uses the same native click path, including
  // checkable state and press/release signals, once per physical key press.
  function activateFromKey(event) {
    if (!event.isAutoRepeat)
      button.click();
  }
  Keys.onReturnPressed: event => button.activateFromKey(event)
  Keys.onEnterPressed: event => button.activateFromKey(event)
}
