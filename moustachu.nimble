[Package]
name        = "moustachu"
version     = "0.3.3"
author      = "Guillaume Viger"
description = "Mustache templating for Nim"
license     = "MIT"

InstallFiles = "moustachu.nim"
bin = "moustachu"

[Deps]
Requires: "nim >= 0.10.2, commandeer >= 0.4.0"
