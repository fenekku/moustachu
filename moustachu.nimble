[Package]
name        = "moustachu"
version     = "0.10.0"
author      = "Guillaume Viger"
description = "Mustache templating for Nim"
license     = "MIT"

srcDir = "src"
bin = "moustachu"

[Deps]
Requires: "nim >= 0.12.0 & < 0.14, commandeer >= 0.4.0"
