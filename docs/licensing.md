# Licensing

## Project license

Original Agentic Stack source code and documentation authored by Avidlive are
licensed under the [Apache License 2.0](../LICENSE). This applies to both the
source and compiled forms of that work.

Apache 2.0 does not replace the license of third-party software. A file or
component with an adjacent license or a listing below remains governed by that
license. Agentic Stack does not claim ownership of third-party work.

## Third-party boundaries

| Component | Location or use | License record |
| --- | --- | --- |
| Cavecrew and Caveman skills | `.cursor/skills/cavecrew` and `.cursor/skills/caveman` | Adjacent MIT `LICENSE` files, copyright Julius Brussee |
| SwiftTerm 1.19.0 | Native macOS terminal | Full notice in `apps/macos/THIRD-PARTY-NOTICES.md` |
| Sparkle 2.9.6 | Native macOS updater | Full upstream and external notices in `apps/macos/THIRD-PARTY-NOTICES.md` |
| CPython, pip, and setuptools | Optional bundled macOS runtime | Original license files are retained inside the bundled runtime |
| Remotion and demo dependencies | `docs/demo` development tooling; excluded from the app and server archives | Licenses declared by `docs/demo/package-lock.json`, including Remotion's separate license |

References to external coding tools, services, skills, or repositories in the
documentation do not bundle or relicense those products.

## Using Agentic Stack

You may use, modify, and redistribute the Avidlive-owned portions under Apache
2.0. Follow the license's redistribution requirements, including providing a
copy of the license, marking modified files, and retaining applicable notices.
When redistributing a bundled component, also follow its own license and
preserve the corresponding notice.

If the applicable license for a particular file is unclear, open an issue with
the exact path. Do not assume that the root Apache license overrides an
adjacent third-party license.
