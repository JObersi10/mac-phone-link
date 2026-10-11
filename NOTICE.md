# NOTICE — provenance & clean-room statement

This project is an independent, open-source effort to build a native macOS
client that interoperates with the Microsoft Phone Link / "Link to Windows"
ecosystem. It is **not affiliated with, endorsed by, or derived from Microsoft
source code.**

## Schemas (`Protos/`)
The `.proto` files here are **clean-room** definitions, authored independently
for this project. They describe the *interface* (message field numbers and
wire types) needed for binary compatibility — facts about an interface, not a
copy of any vendor's source. **No** Microsoft source text, file headers, package
names, namespaces, or comments are reproduced. All files are MIT-licensed.

Vendor package names (`com.microsoft.*`) and namespaces (`YourPhone.*`,
`CrossDevice.*`) are intentionally **not** used; this project uses its own
`maclink.*` packages.

## Not included
Microsoft's application binaries (MSIX/APK/DLL), their original `.proto` files,
and any verbatim vendor text are **excluded from this repository** (see
`.gitignore`) and are used only for local interoperability analysis.

## Interoperability intent
Reverse engineering for interoperability is undertaken in good faith. Microsoft
cloud services enforce their own authentication and Terms of Use; this project
does not circumvent those controls and cannot grant access to them.
