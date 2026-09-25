import SwiftUI

/// **Settings → About → Licences.** Every channel: the kit's three open-source dependencies
/// compile into all three (`ios/WingFoilKit/Package.swift`), so their licences travel with all
/// three. Only the Connect IQ Mobile SDK is narrower — the release channel never links it
/// (`ios/project.yml`, `WingFoilRelease` carries `WingFoilKit` alone, no `ConnectIQ` package),
/// so its entry is `#if BETA`, the same flag that keeps the rest of the Garmin door out of
/// that build.
///
/// A place for this was missing rather than deliberately absent: the App Store review
/// guidelines expect a shipped app to carry the licences of what it is built from, and until
/// this screen the only copy of any of them was the dependency's own GitHub page.
struct LicencesView: View {
    var body: some View {
        Form {
            Section {
                Text("CleanJibe is built on a few open-source libraries. Their own licences, "
                     + "in full, and CleanJibe's own.")
            }

            licenceSection(
                name: "CleanJibe",
                summary: "This app, the watch app and the website are one project.",
                creditLine: "Apache License, Version 2.0",
                noticeText: Self.apacheNotice,
                sourceURL: URL(string: "https://github.com/JanLahmann/WingFoil")!)

            licenceSection(
                name: "FitFileParser",
                summary: "Reads the .fit file a Garmin, a Suunto or a COROS records.",
                creditLine: "MIT License · © 2020 Brice",
                noticeText: Self.mitNotice(year: "2020", holder: "Brice"),
                sourceURL: URL(string: "https://github.com/roznet/FitFileParser")!)

            licenceSection(
                name: "GRDB.swift",
                summary: "The database your session library is kept in.",
                creditLine: "MIT License · © 2015 to 2025 Gwendal Roué",
                noticeText: Self.mitNotice(year: "2015–2025", holder: "Gwendal Roué"),
                sourceURL: URL(string: "https://github.com/groue/GRDB.swift")!)

            licenceSection(
                name: "ZIPFoundation",
                summary: "Reads and writes the .zip files a Garmin export and a library "
                    + "backup use.",
                creditLine: "MIT License · © 2017 to 2026 Thomas Zoechling",
                noticeText: Self.mitNotice(year: "2017–2026", holder: "Thomas Zoechling"),
                sourceURL: URL(string: "https://github.com/weichsel/ZIPFoundation")!)

            #if BETA
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Talks to a Garmin watch over Bluetooth, through the Garmin "
                             + "Connect app. Garmin's own SDK licence, not an open-source "
                             + "one.")
                            .font(.footnote)
                        Link("Read the licence at developer.garmin.com",
                             destination: URL(string: "https://developer.garmin.com/connect-iq/sdk/")!)
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect IQ Mobile SDK")
                        Text("Garmin's watch link, dev and beta only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #endif

            Section {
                Text("Maps on this phone come from Apple's MapKit, under Apple's terms. "
                     + "The browser app uses OpenStreetMap, credited on the map.")
            } footer: {
                Text("The full source for the phone app, the watch app and the website is "
                     + "public.")
            }
        }
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - One dependency, collapsed by default

    private func licenceSection(name: String, summary: String, creditLine: String,
                                 noticeText: String, sourceURL: URL) -> some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text(noticeText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Link("View the source", destination: sourceURL)
                        .font(.footnote)
                }
                .padding(.vertical, 4)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(creditLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - The licence texts, verbatim

    private static func mitNotice(year: String, holder: String) -> String {
        """
        MIT License

        Copyright (c) \(year) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in \
        all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING \
        FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
        DEALINGS IN THE SOFTWARE.
        """
    }

    private static let apacheNotice = """
        Licensed under the Apache License, Version 2.0 (the "License"); you may not \
        use this file except in compliance with the License. You may obtain a copy \
        of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software \
        distributed under the License is distributed on an "AS IS" BASIS, WITHOUT \
        WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the \
        License for the specific language governing permissions and limitations \
        under the License.
        """
}

#Preview {
    NavigationStack { LicencesView() }
}
