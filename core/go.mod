module github.com/taha97kh/vpn5g-ios/core

go 1.23

// sing-box v1.11.8 پین شده است: در این نسخه API کلاسیک libbox
// (Setup / NewService / BoxService.Start+Close) هنوز برقرار است.
// در sing-box 1.14 این API حذف و به CommandServer + gRPC منتقل شده است؛
// بدون مهاجرت به CommandServer به 1.14 ارتقا ندهید.
require github.com/sagernet/sing-box v1.11.8
