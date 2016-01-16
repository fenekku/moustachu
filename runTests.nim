import os
import json
import strutils

import moustachu


for kind, fn in walkDir("specs"):
  if not fn.endsWith(".json"):
    continue

  echo fn
  echo '='.repeat(len(fn))
  var j = parseFile(fn)

  for jn in j["tests"].items():
    var aContext = newContext(jn["data"])
    if jn.hasKey("partials"):
      for key, value in jn["partials"].pairs():
        aContext[key] = value
    try:
      doAssert(render(jn["template"].str, aContext) == jn["expected"].str)
      echo "Pass!"
    except:
      echo ""
      echo "Test '", jn["name"].str, "' failed."
      echo "Template: ", escape(jn["template"].str)
      echo "Template: ", jn["template"].str
      echo "data: ", jn["data"]
      if jn.hasKey("partials"): echo "partials: ", jn["partials"]
      echo "Context: ", aContext
      echo "Render: ", escape(render(jn["template"].str, aContext))
      echo "Expected: ", escape(jn["expected"].str)
      quit(jn["desc"].str)


echo "Tests pass."
