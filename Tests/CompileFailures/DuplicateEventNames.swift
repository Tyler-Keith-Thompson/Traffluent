// Must fail to link: Orders and Checkout each declare an event named OrderPlaced, so the linker
// refuses the program, naming the symbol that stands for the name. Checkout's archive is read on
// demand, as a build that doesn't force an archive in reads it; this reference brings its member in.

import Checkout
import Orders

print(Orders.OrderPlaced.name, Checkout.OrderPlaced.name)
