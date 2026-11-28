// Must fail to link: Orders' OrderPlaced and Fulfillment's PlacedOrder share the name OrderPlaced at
// versions 1 and 2. A store refuses two types of one name whatever their versions, so the version
// isn't part of the name's symbol, and the linker refuses the program.

import Fulfillment
import Orders

print(Orders.OrderPlaced.schemaVersion, Fulfillment.PlacedOrder.schemaVersion)
