/// A Swift type's name as `String(reflecting:)` spells it, parsed into its qualified name and its
/// generic arguments: `SwiftUI.ModifiedContent<MyApp.CheckoutView, SwiftUI._PaddingLayout>` is
/// `SwiftUI.ModifiedContent` with two arguments.
///
/// Automatic screen tracking names a SwiftUI screen from the type of the view its hosting
/// controller shows, which SwiftUI wraps in types of its own: modifiers, `AnyView`, a navigation
/// destination's lazy view. Public API gives only that type, as `String(reflecting:)` spells it,
/// so the name is read from the spelling.
// Spike, on the iOS 26.2 simulator and macOS 27.0.1 (TRAF-22), of what a hosting controller shows:
// - A view pushed by a `NavigationStack` on iOS is a `SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>`,
//   a `UIHostingController<AnyView>` subclass, a child of a `SwiftUI.UIKitNavigationController`
//   (a `UINavigationController`). The `AnyView`'s first child in a `Mirror` is its storage,
//   `SwiftUI.(unknown context at $…).AnyViewStorage<…>`, whose type spells the destination:
//   `ModifiedContent<ModifiedContent<ModifiedContent<ParameterizedLazyView<Swift.Int, MyApp.DetailView>, …>, …>, …>`
//   for `navigationDestination(for: Int.self) { DetailView(id: $0) }`. The destination's type is
//   the lazy view's last argument; the first is the path's value type.
// - A destination closure that picks its view with an `if` or a `switch` is a
//   `ParameterizedLazyView<Route, _ConditionalContent<A, B>>`: every branch is in the type, and
//   which one was built isn't, as the lazy view holds a closure. Its `Mirror` does hold the
//   presented value, as its child `value`, which names the screen instead.
// - The stack's root view is hosted the same way, but its content is type-erased
//   (`_VariadicView.Tree<_VStackLayout, _VariadicView_Children>`), so its name isn't recoverable
//   from its type: the screen takes the name of the hosting controller around the stack.
// - A `UIHostingController` the app makes spells its root view's type in full:
//   `UIHostingController<ModifiedContent<MyApp.DetailView, SwiftUI._PaddingLayout>>`.
// - On macOS, a `NavigationStack` makes no view controller and no view for what it pushes: the
//   whole stack draws inside its one `NSHostingView`, so its pushes aren't discoverable without
//   private API or swizzling. An `NSHostingController`'s root view is, as on iOS.
package struct TypeName: Hashable, Sendable, CustomStringConvertible {
    /// The type's name with its module and the types it is nested in, without its generic
    /// arguments: `SwiftUI.ModifiedContent`.
    package var qualifiedName: String

    /// The type's generic arguments, in order.
    package var arguments: [TypeName]

    /// The type named `qualifiedName`, given `arguments`.
    ///
    /// - Parameters:
    ///   - qualifiedName: The name with its module, without generic arguments.
    ///   - arguments: The generic arguments, in order.
    package init(qualifiedName: String, arguments: [TypeName] = []) {
        self.qualifiedName = qualifiedName
        self.arguments = arguments
    }

    /// The type name `text` spells, as `String(reflecting:)` writes one.
    ///
    /// It never fails: text that isn't a type's name parses to some name, which no screen has.
    /// Nesting deeper than 64 generic arguments is kept as text in the innermost name.
    ///
    /// - Parameter text: A type's name.
    /// - Complexity: O(*n*), where *n* is the length of `text`.
    package init(parsing text: String) {
        var parser = Parser(characters: Array(text))
        self = parser.typeName(depth: 0)
    }

    /// The module the type is declared in, or the empty string for a tuple or function type,
    /// whose name starts with a parenthesis.
    package var module: String {
        isTupleOrFunction ? "" : components.first ?? ""
    }

    /// The type's own name, without its module, the types it is nested in or its generic
    /// arguments: `ModifiedContent`. A type declared inside a function, which
    /// `String(reflecting:)` spells `(CheckoutView in _4F1A…)`, is `CheckoutView`; a tuple or
    /// function type is its whole name.
    package var baseName: String {
        guard let last = components.last else { return qualifiedName }
        guard last.first == "(", let local = last.firstRange(of: " in ") else { return last }
        return String(last[last.index(after: last.startIndex)..<local.lowerBound])
    }

    /// The type's name as a person reads it: its base name, and its arguments' the same way,
    /// `DetailView<Item>`.
    package var description: String {
        arguments.isEmpty ? baseName : "\(baseName)<\(arguments.map(\.description).joined(separator: ", "))>"
    }

    /// The name of the screen a view of this type draws: the first type in it that the app
    /// declared, rather than SwiftUI or the standard library, read as ``description``; `nil` if
    /// every type in it is SwiftUI's, or if it picks between views when it is built.
    ///
    /// A SwiftUI wrapper (`ModifiedContent`, a stack, `AnyView`'s storage) is skipped for its
    /// arguments, the first that names the app's type winning, except a navigation destination's
    /// `ParameterizedLazyView<Value, Content>`, whose content is its last argument. An `if` or a
    /// `switch` (`_ConditionalContent`) names no screen: its type holds every branch.
    package var screenName: String? {
        guard !qualifiedName.isEmpty, !isTupleOrFunction else { return nil }
        guard Self.frameworkModules.contains(module) else { return description }
        if baseName == "ParameterizedLazyView" {
            return arguments.last?.screenName
        }
        if baseName == "_ConditionalContent" {
            return nil
        }
        return arguments.lazy.compactMap(\.screenName).first
    }

    /// The name of the screen `view` draws.
    ///
    /// Where SwiftUI holds the view inside a value (`AnyView`, a modifier's content, the branch an
    /// `if` or `switch` took), it is read from the value inside; otherwise from its type, as
    /// ``screenName``. A navigation destination not yet built whose type picks between views is
    /// named after the value it presents: an enumeration's type and case, without its associated
    /// values (`"Route.settings"`), or another type's name.
    ///
    /// - Parameter view: A hosting controller's root view.
    /// - Returns: The screen's name, or `nil` if no type in it is the app's.
    package static func screenName(ofView view: Any) -> String? {
        var value = view
        // Each step reads a part of the value before, so this ends; the bound is a guard.
        for _ in 0..<64 {
            let name = TypeName(parsing: String(reflecting: type(of: value)))
            guard name.isSwiftUI else { return name.screenName }
            if Self.viewHolders.contains(name.baseName) {
                guard let inner = Mirror(reflecting: value).children.first?.value else { return nil }
                value = inner
            } else if name.baseName == "ParameterizedLazyView", name.screenName == nil {
                // The destination's view is chosen as it is built, from the value it presents.
                guard let presented = Mirror(reflecting: value).children.first(where: { $0.label == "value" })?.value else {
                    return nil
                }
                return screenName(ofPresented: presented)
            } else {
                return name.screenName
            }
        }
        return nil
    }

    /// The name of a navigation destination presenting `value`: an enumeration's type and case,
    /// such as `"Route.settings"`, leaving out its associated values, which may identify a person
    /// or vary without bound; another value's type.
    private static func screenName(ofPresented value: Any) -> String {
        let typeName = TypeName(parsing: String(reflecting: type(of: value))).description
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .enum else { return typeName }
        // A case with associated values is the label of its one child; one without has none,
        // and describes itself by its name.
        let caseName = mirror.children.first?.label ?? String(describing: value)
        return "\(typeName).\(caseName)"
    }

    /// Modules whose types wrap a screen's view rather than name it.
    private static let frameworkModules: Set<String> = [
        "Swift", "_Concurrency", "SwiftUI", "SwiftUICore", "Foundation", "CoreFoundation",
        "CoreGraphics", "Combine", "Observation", "UIKit", "AppKit",
    ]

    /// SwiftUI's types that hold the view they show as the first of their children in a mirror:
    /// `AnyView` its storage and the storage its view, a modifier its content, a conditional its
    /// storage and the storage the branch taken, as its case's payload.
    private static let viewHolders: Set<String> = ["AnyView", "AnyViewStorage", "ModifiedContent", "_ConditionalContent"]

    /// Whether the name is a tuple's or a function's, which starts with a parenthesis.
    private var isTupleOrFunction: Bool {
        qualifiedName.first == "("
    }

    /// Whether this is one of SwiftUI's types.
    private var isSwiftUI: Bool {
        module == "SwiftUI" || module == "SwiftUICore"
    }

    /// The qualified name's dot-separated parts, ignoring dots inside parentheses:
    /// `SwiftUI.(unknown context at $1dbb9a8a4).AnyViewStorage` is three.
    private var components: [String] {
        var parts: [String] = []
        var part = ""
        var depth = 0
        for character in qualifiedName {
            switch character {
            case "(": depth += 1
            case ")": depth = max(depth - 1, 0)
            case "." where depth == 0:
                parts.append(part)
                part = ""
                continue
            default: break
            }
            part.append(character)
        }
        parts.append(part)
        return parts
    }
}

/// Reads a type name, one character at a time.
private struct Parser {
    let characters: [Character]
    var position = 0

    /// The type name from `position`: its qualified name up to a `<`, `,` or `>` outside
    /// parentheses and brackets, then its generic arguments, if a `<` follows.
    mutating func typeName(depth: Int) -> TypeName {
        var name = ""
        var nesting = 0
        while position < characters.count {
            let character = characters[position]
            // Past the depth bound, the rest is text, read without recursing further.
            if depth < 64, nesting == 0, character.endsName(after: name) {
                break
            }
            switch character {
            case "(", "[": nesting += 1
            case ")", "]": nesting = max(nesting - 1, 0)
            default: break
            }
            name.append(character)
            position += 1
        }
        var arguments: [TypeName] = []
        if position < characters.count, characters[position] == "<" {
            position += 1
            while position < characters.count {
                arguments.append(typeName(depth: depth + 1))
                guard position < characters.count else { break }
                let separator = characters[position]
                position += 1
                if separator == ">" {
                    break
                }
            }
        }
        return TypeName(qualifiedName: name.trimmingSpaces(), arguments: arguments)
    }
}

extension Character {
    /// Whether this character ends a type's name read so far as `name`: a `<` opening its
    /// arguments, or the `,` or `>` after it in a list of arguments, but not the `>` of a
    /// function type's `->`.
    fileprivate func endsName(after name: String) -> Bool {
        switch self {
        case "<", ",": true
        case ">": name.last != "-"
        default: false
        }
    }
}

extension String {
    /// The string without leading or trailing spaces.
    fileprivate func trimmingSpaces() -> String {
        String(drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
    }
}
