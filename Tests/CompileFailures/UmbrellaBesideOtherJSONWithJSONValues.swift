// The control's file importing JSONValues too: `JSON` is then ambiguous. So the control compiles
// only while the umbrella leaves JSONValues out, not because the compiler can't see two types of
// one name.

import JSONValues
import OtherJSON
import Traffluent

let body: JSON = JSON(text: "{}")
let tracker = Tracker()
