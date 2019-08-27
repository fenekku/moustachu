import unittest

import moustachu

let tmplate = """{{#repos}}<b>{{.}}</b>{{/repos}}"""

suite "test array assignments":
  test "array of strings":
    var c : Context = newContext()
    c["repos"] = ["nimble", "hub", "moustachu"]
    let expected_result = "<b>nimble</b><b>hub</b><b>moustachu</b>"
    check render(tmplate, c) == expected_result

  test "array of ints":
    var c : Context = newContext()
    c["repos"] = [1, 2, 3]
    let expected_result = "<b>1</b><b>2</b><b>3</b>"
    check render(tmplate, c) == expected_result

  test "array of floats":
    var c : Context = newContext()
    c["repos"] = [1.1, 2.2, 3.3]
    let expected_result = "<b>1.1</b><b>2.2</b><b>3.3</b>"
    check render(tmplate, c) == expected_result

  test "array of bools":
    var c : Context = newContext()
    c["repos"] = [true, false, true]
    let expected_result = "<b>true</b><b></b><b>true</b>"
    check render(tmplate, c) == expected_result
