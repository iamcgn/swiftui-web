# SQLite3

SQLite 3.53.4's amalgamation (`sqlite3.c`, `include/sqlite3.h`, `include/sqlite3ext.h`), copied
unchanged from sqlite.org's release. SQLite is in the public domain.

The target is the module Apple's SDK names `SQLite3`, so an app's `import SQLite3` (and packages
such as GRDB and SQLite.swift that wrap it) builds for the web. SQLite builds for WASI itself
(`SQLITE_WASI`: no loadable extensions, no threads, no shared-memory WAL). The defines in
Package.swift turn on what Apple's build of SQLite has: FTS3/4/5, R*Tree, the dbstat table, column metadata and
snapshots.

Depend on it on Linux and WASI only: on Apple's platforms the SDK's own `SQLite3` is there.

To update, copy the three files from the new amalgamation and change the version above.
