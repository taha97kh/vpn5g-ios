// Package core is the Go module vessel for building the sing-box libbox
// XCFramework with gomobile bind.
//
// The blank import below exists for one reason: this module has no other
// Go source, so without it `go mod tidy` would drop the sing-box require
// entirely (nothing in the module imports it) and `gomobile bind` would
// then fail with "updates to go.mod needed". With this import, tidy keeps
// the pin and records every transitive requirement the iOS bind needs.
// Do NOT delete this file, and do NOT run `go mod tidy` after removing it.
//
// sing-box v1.11.8 is pinned: the classic libbox API (Setup / NewService /
// BoxService.Start+Close) still exists in this version. In sing-box 1.14
// that API was removed in favour of CommandServer + gRPC; do not upgrade
// to 1.14 without migrating to CommandServer.
package core

import (
	_ "github.com/sagernet/sing-box/experimental/libbox"
)
