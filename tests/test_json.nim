import unittest
import json

import moustachu

let objTemplate = "s={{string}},i={{int}},f={{float}}"

suite "test json input":
  test "from string template":
    var j = newJObject()
    j["string"] = newJString("hello")
    j["int"] = newJInt(3)
    j["float"] = newJFloat(3.14)
    let expected_result = "s=hello,i=3,f=3.14"
    check render(objTemplate, j) == expected_result
    
  test "from file":
    var j = newJObject()
    j["string"] = newJString("hello")
    j["int"] = newJInt(3)
    j["float"] = newJFloat(3.14)
    let expected_result = "s=hello,i=3,f=3.14"
    check renderFile("tests/objectTemplate.moustachu", j) == expected_result
