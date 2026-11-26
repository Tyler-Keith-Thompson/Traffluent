// Must not compile: Priority, declared outside the event, isn't Codable, so @Event's requirement
// for `priority` fails, naming the property.

import EventMacros

enum Priority: Int {
    case low
    case high
}

@Event
struct TicketOpened {
    var priority: Priority
}
