import Foundation

/// The hardening both XML doors wear, spelled once.
///
/// A GPX and a TCX are **files from strangers**: a co-rider's export, an intervals.icu
/// original, a member of a ZIP somebody sent. XML is the one recording format with a
/// programmable header — a `<!DOCTYPE>` may declare entities, and an entity may name a
/// *file* or expand into a gigabyte of itself. Neither is a thing a recording ever needs,
/// and both are things a parser will do if nobody says otherwise:
///
/// * **External entities (XXE).** `<!ENTITY x SYSTEM "file:///…">` asks the parser to read
///   something off the phone and substitute it into the document — and everything the
///   document holds is then a string the app is willing to store, print and put on a share
///   card. Foundation's default is already not to resolve them, but "already, by default,
///   on this platform" is not a property a security boundary should rest on, so the two
///   switches are set explicitly.
/// * **Entity expansion (the billion laughs).** Ten nested entities, each ten copies of the
///   one below, is three kilobytes of file and a gigabyte of string. The app does not crash
///   gracefully out of that; it is killed.
///
/// The answer to both is the same and it is blunt, because the alternative — a budget, a
/// depth counter, a nesting limit — is a thing to get subtly wrong: **a recording with an
/// entity declaration in it is refused**. GPX 1.1 and TCX v2 have schemas, neither schema
/// has a DTD subset in it, and no exporter in the corpus writes one. The parse aborts, and
/// the file arrives at the rider as the `malformed` it is.
///
/// Subclass this rather than `NSObject` and the three methods come along; `SafeXML.parser`
/// is what wires the switches on the parser itself.
class SafeXMLCollector: NSObject, XMLParserDelegate {

    /// True once a declaration was seen and the parse was stopped. Read by the tests; the
    /// parsers themselves need only the `false` that `parse()` returns.
    private(set) var refusedDeclaration = false

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String,
                value: String?) {
        refuse(parser)
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        refuse(parser)
    }

    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?, notationName: String?) {
        refuse(parser)
    }

    /// The belt to the brace: even with the policy set, an entity that reached resolution
    /// gets nothing.
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String,
                systemID: String?) -> Data? {
        refuse(parser)
        return nil
    }

    private func refuse(_ parser: XMLParser) {
        refusedDeclaration = true
        parser.abortParsing()
    }
}

/// Builds the one `XMLParser` this kit is allowed to build.
enum SafeXML {
    static func parser(data: Data, delegate: SafeXMLCollector) -> XMLParser {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // Local names only: GPX 1.0/1.1 and either TCX namespace, under any prefix.
        parser.shouldProcessNamespaces = true
        // Explicit rather than inherited. Both of these are Foundation's defaults today on
        // both platforms this kit builds for; a default is a thing that changes, and a file
        // from a stranger is not where we want to find out that one did.
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        return parser
    }
}
