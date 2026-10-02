# When a replacement takes effect

A replacement is used from the first file uji loads, `boot.lua` included. The
first time a pack that replaces modules is added, uji starts over once while it
starts up, so that the pack's files are used from the beginning. It remembers
those packs for later starts.

`/reload` and `/sync` restart uji with your current files. The
conversation, what you are typing and the screen stay as they are. A turn in
progress has to finish, or be interrupted with Esc, before a reload. Processes
that plugins started, such as MCP servers, are started again.
