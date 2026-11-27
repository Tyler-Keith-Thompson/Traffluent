// `import Traffluent` beside another module's top-level `JSON`: the name is that module's,
// unqualified, as the umbrella declares no `JSON` of its own.

import OtherJSON
import Traffluent

let body: JSON = JSON(text: "{}")
let tracker = Tracker()
