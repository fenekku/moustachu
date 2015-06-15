[Package]
name        = "moustachu"
version     = "0.4.0"
author      = "Guillaume Viger"
description = "Mustache templating for Nim"
license     = "MIT"

InstallFiles = "moustachu.nim"
bin = "moustachu"

[Deps]
Requires: "nim >= 0.11.2, commandeer >= 0.4.0"
