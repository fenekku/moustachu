import re
import strutils
import json

type
  ## Context used to render a mustache template
  Context* = ref ContextObj
  ContextObj = object
    j : JsonNode
    nestedSections : seq[seq[string]]

  #TODO allow this to be used
  MoustachuParsingError = object of Exception

let
  openingTag = r"\{\{"
  closingTag = r"\}\}"
  tagRegex = re(openingTag & r"(\#|&|\^|!|\{)?((.|\s)+?)(\})?" & closingTag)
  htmlEscapeReplace = [(re"&","&amp;"),
                       (re"<","&lt;"),
                       (re">","&gt;"),
                       (re"\\","&#92;"),
                       (re("\""),"&quot;")]

proc newContext*(): Context =
  ## Creates an empty Context to be filled and used for rendering
  new(result)
  result.j = newJObject()
  result.nestedSections = @[]

proc newContext*(c : Context): Context =
  ## Creates a new context from another one
  result = newContext()
  result.j = copy(c.j)
  result.nestedSections = c.nestedSections

proc toDotIterator(node: var JsonNode) =
  ## Add an intermediate JObject with key "." for JArray elements
  ## of kind JInt, JString, JBool, JFloat
  if node.kind == json.JObject:
    for pair in node.mpairs():
      case pair.val.kind
      of json.JObject:
        toDotIterator(pair.val)
      of json.JArray:
        var modifiedJsonArray : seq[JsonNode] = @[]
        for n in pair.val.mitems():
          case n.kind
          of json.JFloat, json.JBool, json.JInt, json.JString:
            var j = newJObject()
            j["."] = n
            modifiedJsonArray.add(j)
          else:
            n.toDotIterator()

        if modifiedJsonArray.len > 0:
          pair.val.elems = modifiedJsonArray
      else:
        discard

proc newContext*(j : JsonNode): Context =
  ## Creates a new context from a JsonNode
  result = newContext()
  result.j = copy(j)
  result.j.toDotIterator()

proc `[]=`*(c: var Context; key: string, value: BiggestInt) =
  ## Assigns an int to a key in the context
  ## Converts to string immediately
  c.j[key] = newJString($value)

proc `[]=`*(c: var Context, key: string, value: string) =
  ## Assigns a string to a key in the context
  c.j[key] = newJString($value)

proc `[]=`*(c: var Context, key: string, value: float) =
  ## Assigns a float to a key in the context
  ## Converts to string immediately
  c.j[key] = newJString(value.formatFloat(ffDefault, 0))

proc `[]=`*(c: var Context, key: string, value: bool) =
  ## Assigns a bool to a key in the context
  ## Converts to string immediately
  c.j[key] = newJString(if value: "true" else: "")

proc `[]=`*(c: var Context, key: string, value: Context) =
  ## Assigns the `value` context to `key` in the `c` context
  ## This builds a subcontext.
  c.j[key] = value.j

proc `[]=`*(c: var Context, key: string, value: openarray[Context]) =
  ## Assigns a list of contexts to a key in the context
  ## This creates a list.
  var contextList = newJArray()
  for v in value:
    contextList.elems.add(v.j)
  c.j[key] = contextList

proc `$`*(c: Context): string =
  ## Returns a string representing the context. Useful for debugging
  result = "j = " & pretty(c.j) & "\nnestedSections : " & $c.nestedSections

proc getInnerJson(c: Context, absoluteKey: seq[string]): JsonNode =
  ## Returns the inner Json associated with `absoluteKey` in the context
  ## Returns a JNull object if `absoluteKey` is nil
  if absoluteKey.isNil():
    result = newJNull()
  else:
    result = c.j
    for subKey in absoluteKey:
      if result.hasKey(subKey):
        result = result[subKey]
      else:
        result = newJNull()
        break

proc getAbsKey(c: Context, relativeKey: string): seq[string] =
  ## Returns the seq[string] that leads to and includes this relativeKey
  ## Returns nil if there is no such path to this key
  ## e.g. key="aa" inside section "a" returns @["a", "aa"]
  result = nil
  var keySections : seq[string]
  if relativeKey == ".":
    keySections = @["."]
  else:
    keySections = relativeKey.split(".")

  var keyFound = false

  if c.nestedSections.len > 0:
    for i in countdown(c.nestedSections.high, c.nestedSections.low):
      var j = c.j
      var inThisSection = true
      for subKey in c.nestedSections[i]:
        j = j[subKey]
      for subKey in keySections:
        if j.hasKey(subKey):
          j = j[subKey]
        else:
          inThisSection = false
          break
      if inThisSection:
        keyFound = true
        result = c.nestedSections[i] & keySections
        break

  if not keyFound:
    var j = c.j
    keyFound = true
    for subKey in keySections:
      if j.hasKey(subKey):
        j = j[subKey]
      else:
        keyFound = false
        break
    if keyFound:
      result = keySections

proc toString(c: Context, absoluteKey: seq[string]): string =
  ## Returns the string associated with the key in the context.
  ## Returns the empty string if key is invalid.
  var jsonNode = c.getInnerJson(absoluteKey)

  if jsonNode.kind == json.JString:
    return jsonNode.str
  elif jsonNode.kind != json.JNull:
    return $jsonNode
  else:
    return ""

proc adjustForStandaloneIndentation(bounds: var tuple[first, last: int],
                                    pos: int, tmplate: string): void =
  ## Adjusts `bounds` to follow how Moustache treats whitespace
  ## TODO: Make this more readable
  var
    first = bounds.first
    last = bounds.last

  while first-1 >= pos and tmplate[first-1] in Whitespace-NewLines:
    dec(first)
  while last+1 <= tmplate.len-1 and tmplate[last+1] in Whitespace-NewLines:
    inc(last)
  if last < tmplate.len-1:
    inc(last)

  #Need to account for \r\n
  #would be nice to be able to do this prettily
  if last+1 <= tmplate.len-1 and tmplate[last] == '\x0D' and tmplate[last+1] == '\x0A':
    inc(last)

  if ((first == 0) or (first > 0 and tmplate[first-1] in NewLines)) and
     ((last == tmplate.len-1) or (last < tmplate.len-1 and tmplate[last] in NewLines)):
    bounds.first = first
    bounds.last = last

proc findClosingBounds(tagKey: string, tmplate: string,
                       offset: int): tuple[first, last:int] =
  ## Finds the closing tuple for `tagKey` in `tmplate` starting at
  ## `offset`. The returned bounds tuple is absolute (it incorporates
  ## `offset`)
  var numOpenSections = 1
  var matches : array[1, string]
  let openingOrClosingTagRegex = re(openingTag & r"(\#|\^|/)\s*" &
                                    tagKey & r"\s*" & closingTag)
  var closingTagBounds : tuple[first: int, last: int]
  var pos = offset

  while numOpenSections != 0:
    closingTagBounds = tmplate.findBounds(openingOrClosingTagRegex,
                                          matches, start=pos)
    if matches[0] == "#" or matches[0] == "^":
      inc(numOpenSections)
    else:
      dec(numOpenSections)
    pos = closingTagBounds.last+1

  return closingTagBounds

proc render*(tmplate: string, c: Context, inSection: bool=false): string =
  ## Takes a Moustache template `tmplate` and an evaluation context `c`
  ## and returns the rendered string. This is the main procedure.
  ## `inSection` is used to specify if the rendering is done from within
  ## a moustache section. TODO: use c information instead of `inSection`
  var matches : array[4, string]
  var pos = 0
  var bounds : tuple[first, last: int]
  result = ""

  if not tmplate.contains(tagRegex):
    return tmplate

  while pos != tmplate.len:
    #Find a tag
    bounds = tmplate.findBounds(tagRegex, matches, start=pos)

    if bounds.first == -1:
      #No tag
      result.add(tmplate[pos..tmplate.len-1])
      pos = tmplate.len
      continue

    var tagKey = matches[1].strip()
    var absoluteKey = getAbsKey(c, tagKey)
    var innerJson = c.getInnerJson(absoluteKey)

    case matches[0]
    of "!":
      #Comments tag
      if not inSection:
        adjustForStandaloneIndentation(bounds, pos, tmplate)
      if bounds.first > 0:
        result.add(tmplate[pos..bounds.first-1])
      pos = bounds.last + 1

    of "{", "&":
      #Triple mustache tag: do not htmlescape
      var s = c.toString(absoluteKey)
      if bounds.first == 0:
        result.add(s)
      else:
        result.add(tmplate[pos..bounds.first-1] & s)
      pos = bounds.last + 1

    of "#", "^":
      #section tag
      adjustForStandaloneIndentation(bounds, pos, tmplate)
      if bounds.first > 0:
        #immediately add text before the tag to final result
        result.add(tmplate[pos..bounds.first-1])
      pos = bounds.last + 1

      var closingBounds = findClosingBounds(tagKey, tmplate, pos)
      adjustForStandaloneIndentation(closingBounds, pos, tmplate)

      if matches[0] == "#":
        if innerJson.kind == json.JObject:
          #Render section
          c.nestedSections.add(absoluteKey)
          result.add(render(tmplate[pos..closingBounds.first-1], c, true))
          discard c.nestedSections.pop()
        elif innerJson.kind == json.JArray:
          #Render list
          var parentKey : seq[string]
          if absoluteKey.len > 1: parentKey = absoluteKey[0..^2]
          else: parentKey = @[]
          var parentJson = c.getInnerJson(parentKey) #is a ref
          var baseKey = absoluteKey[^1]

          for jsonItem in innerJson.items():
            #redefine the content of the tagKey
            parentJson[baseKey] = jsonItem
            c.nestedSections.add(absoluteKey)
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
            discard c.nestedSections.pop()
          #redefine it back
          parentJson[baseKey] = innerJson
        elif innerJson.kind == json.JBool:
          if innerJson.bval:
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
        elif innerJson.kind != json.JNull:
          #Truthy
          result.add(render(tmplate[pos..closingBounds.first-1], c, true))
        else:
          #Falsey
          discard
      else:
        # "^" is for inversion: if tagKey exists, don't render
        if innerJson.kind == json.JObject:
          #Don't render section
          discard
        elif innerJson.kind == json.JArray:
          if innerJson.elems.len == 0:
            #Empty list is Truthy
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
        elif innerJson.kind == json.JNull:
          #Falsey is Truthy
          result.add(render(tmplate[pos..closingBounds.first-1], c, true))
        elif innerJson.kind == json.JBool:
          if not innerJson.bval:
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
        else:
          #Truthy is Falsey
          discard

      pos = closingBounds.last + 1

    else:
      #Normal substitution
      var s = parallelReplace(c.toString(absoluteKey), htmlEscapeReplace)
      if bounds.first == 0:
        result.add(s)
      else:
        result.add(tmplate[pos..bounds.first-1] & s)
      pos = bounds.last + 1


when isMainModule:
  import commandeer

  proc usage(): string =
    result = "Usage: moustachu <context>.json <template>.moustache [--file=<outputFilename>]"

  commandline:
    argument jsonFilename, string
    argument tmplateFilename, string
    option outputFilename, string, "file", "f"
    exitoption "help", "h", usage()

  var c = newContext(parseFile(jsonFilename))
  var tmplate = readFile(tmplateFilename)

  if outputFilename.isNil():
    echo render(tmplate, c)
  else:
    writeFile(outputFilename, render(tmplate, c))
