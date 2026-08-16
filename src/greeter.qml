pragma ComponentBehavior: Bound
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import Quickshell
import "modules/greeter"

ShellRoot {
  Greeter {}
}
