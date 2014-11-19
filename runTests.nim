import os
import json
import strutils

import moustachu


proc contextFromValue(node: PJsonNode): Context =
  result = newContext()
  case node.kind
  of JString:
    result["."] = node.str.split({'"','\''})[0]
  of JInt:
    result["."] = node.num
  of JFloat:
    result["."] = node.fnum
  of JBool:
    result["."] = node.bval
  of JNull:
    discard
  else:
    echo "should not be here"
    quit QuitFailure

proc contextFromPJsonNode(node: PJsonNode): Context =
  result = newContext()
  for key, value in node.pairs():
    case value.kind
    of JString:
      result[key] = value.str
    of JInt:
      result[key] = value.num
    of JFloat:
      result[key] = value.fnum
    of JBool:
      result[key] = value.bval
    of JNull:
      discard
    of JObject:
      var val = contextFromPJsonNode(value)
      result[key] = val
    of JArray:
      var val : seq[Context]
      if value.elems.len != 0:
        case value.elems[0].kind
        of JObject:
          val = map(value.elems, contextFromPJsonNode)
        else:
          val = map(value.elems, contextFromValue)
      else:
        val = map(value.elems, contextFromPJsonNode)
      result[key] = val


var aContext : Context = newContext()
var m : Mustache

for kind, fn in walkDir("specs"):
  if not fn.endsWith(".json"):
    continue

  echo fn
  echo repeatChar(fn.len, '=')
  var j = parseFile(fn)

  for jn in j["tests"].items():
    var aContext = contextFromPJsonNode(jn["data"])
    try:
      doAssert(m.render(jn["template"].str, aContext) == jn["expected"].str)
      echo "Pass!"
    except:
      echo ""
      echo "Test '", jn["name"].str, "' failed."
      echo "Template: ", escape(jn["template"].str)
      echo "Template: ", jn["template"].str
      echo "Context: ", aContext
      echo "Render: ", escape(m.render(jn["template"].str, aContext))
      echo "Expected: ", escape(jn["expected"].str)
      quit(jn["desc"].str)

  echo ""
