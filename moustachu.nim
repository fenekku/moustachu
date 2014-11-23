import tables
import re
import strutils

type
  Context* = ref ContextObj
  ContextObj = object
    stringContext : TTable[string, string]
    subContexts : TTable[string, Context]
    listContexts : TTable[string, seq[Context]]
    parent : Context

  MoustachuParsingError = object of E_Base

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
  new(result)
  result.stringContext = initTable[string, string](4)
  result.subContexts = initTable[string, Context](2)
  result.listContexts = initTable[string, seq[Context]](2)

proc newContext(c : Context): Context =
  result = newContext()
  for key, value in c.stringContext.pairs():
    result.stringContext[key] = value
  for key, value in c.subContexts.mpairs():
    value.parent = result
    result.subContexts[key] = value
  for key, value in c.listContexts.mpairs():
    for v in value:
      v.parent = result
    result.listContexts[key] = value

proc `[]=`*(c: var Context; key: string, value: BiggestInt) =
  c.stringContext[key] = $value

proc `[]=`*(c: var Context; key: string, value: string) =
  c.stringContext[key] = $value

proc `[]=`*(c: var Context; key: string, value: float) =
  c.stringContext[key] = value.formatFloat(ffDefault, 0)

proc `[]=`*(c: var Context; key: string, value: bool) =
  c.stringContext[key] = if value: "true" else: ""

proc `[]=`*(c: var Context; key: string; value: var Context) =
  value.parent = c
  c.subContexts[key] = value

proc `[]=`*(c: var Context; key: string; value: var openarray[Context]) =
  var contextList = newSeq[Context]()
  for v in value:
    v.parent = c
    contextList.add(v)
  c.listContexts[key] = contextList

proc `$`*(c: Context): string =
  result = "{"
  for key, value in c.stringContext.pairs():
    if result.len > 1: result.add(", ")
    result.add($key)
    result.add(": ")
    result.add($value)

  for key, value in c.subContexts.pairs():
    if result.len > 1: result.add(", ")
    result.add($key)
    result.add(":")
    result.add($value)

  for key, value in c.listContexts.pairs():
    if result.len > 1: result.add(", ")
    result.add($key)
    result.add(":")
    result.add("[")
    var subresult = ""
    for val in value:
      if subresult.len > 1: subresult.add(", ")
      subresult.add($val)
    result.add(subresult)
    result.add("]")

  result.add("}")

proc `[]`(c: Context; key: string): string =
  #Always interpolation at this point
  result = ""
  if key == "." and c.stringContext.hasKey(key):
    result = $c.stringContext[key]
  else:
    var dotIndex = key.find(re"\.")
    if dotIndex != -1:
      var firstKey = key[0..dotIndex-1]
      if c.subContexts.hasKey(firstKey):
        var nc = c.subContexts[firstKey]
        var p = nc.parent
        nc.parent = nil
        result = nc[key[dotIndex+1..key.len-1]]
        c.subContexts[firstKey].parent = p
      elif not c.parent.isNil():
        result = c.parent[key]
      else:
        result = ""
    else:
      if c.stringContext.hasKey(key):
        result = $c.stringContext[key]
      elif not c.parent.isNil():
        result = c.parent[key]
      else:
        result = ""

proc getContext(c: Context, key: string, foundContext: var context): bool =
  var dotIndex = key.find(re"\.")
  if dotIndex != -1:
    var firstKey = key[0..dotIndex-1]
    if c.subContexts.hasKey(firstKey):
      result = c.subContexts[firstKey].getContext(key[dotIndex+1..key.len-1], foundContext)
    elif not c.parent.isNil():
      result = c.parent.getContext(key, foundContext)
    else:
      #TODO toggle Exception
      result = false
  else:
    if c.subContexts.hasKey(key):
      foundContext = c.subContexts[key]
      result = true
    elif not c.parent.isNil():
      result = c.parent.getContext(key, foundContext)
    else:
      #TODO toggle Exception
      result = false

proc getList(c: Context, key: string, foundList: var seq[Context]): bool =
  var dotIndex = key.find(re"\.")
  if dotIndex != -1:
    var firstKey = key[0..dotIndex-1]
    if c.subContexts.hasKey(firstKey):
      result = c.subContexts[firstKey].getList(key[dotIndex+1..key.len-1], foundList)
    elif not c.parent.isNil():
      result = c.parent.getList(key, foundList)
    else:
      result = false
  else:
    if c.listContexts.hasKey(key):
      foundList = c.listContexts[key]
      result = true
    elif not c.parent.isNil():
      result = c.parent.getList(key, foundList)
    else:
      result = false

proc adjustForStandaloneIndentation(bounds: var tuple[first, last: int],
                                    pos: int, tmplate: string): void =
  var
    first = bounds.first
    last = bounds.last
  while first-1 >= pos and tmplate[first-1] in Whitespace-NewLines: dec(first)
  while last+1 <= tmplate.len-1 and tmplate[last+1] in Whitespace-NewLines: inc(last)
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

proc escapeHTML(s: string): string =
  result = parallelReplace(s, htmlEscapeReplace)

template substitutionImpl(s: string) =
  #Substitution
  if bounds.first == 0:
    result.add(s)
  else:
    result.add(tmplate[pos..bounds.first-1] & s)
  pos = bounds.last + 1

proc findClosing(tagKey: string, tmplate: string): tuple[first, last:int] =
  #TODO double check for unbalanced sections
  var numOpenSections = 1
  var matches : array[1, string]
  let openCloseTagRegex = re(openingTag & r"(\#|\^|/)\s*" & tagKey & r"\s*" & closingTag)
  var bounds : tuple[first: int, last: int]
  var pos = 0

  while numOpenSections != 0:
    bounds = tmplate.findBounds(openCloseTagRegex, matches, start=pos)
    if matches[0] == "#" or matches[0] == "^":
      inc(numOpenSections)
    else:
      dec(numOpenSections)
    pos = bounds.last+1

  return bounds

proc render*(tmplate: string, c: Context, inSection: bool = false): string =
  var matches : array[4, string]
  var pos = 0
  var bounds : tuple[first, last: int]
  result = ""

  if not tmplate.contains(tagRegex):
    return tmplate

  while pos != tmplate.len:
    bounds = tmplate.findBounds(tagRegex, matches, start=pos)

    if bounds.first == -1:
      result.add(tmplate[pos..tmplate.len-1])
      pos = tmplate.len
    else:
      var tagKey = matches[1].strip()
      case matches[0]
      of "!":
        #Comments
        if inSection:
          discard
        else:
          adjustForStandaloneIndentation(bounds, pos, tmplate)
        if bounds.first > 0:
          result.add(tmplate[pos..bounds.first-1])
        pos = bounds.last + 1

      of "{", "&":
        #Triple mustache: do not htmlescape
        substitutionImpl(c[tagKey])

      of "#", "^":
        adjustForStandaloneIndentation(bounds, pos, tmplate)
        if bounds.first > 0:
          result.add(tmplate[pos..bounds.first-1])

        pos = bounds.last + 1

        #TODO prettify this piece
        var closingBounds = findClosing(tagKey, tmplate[pos..tmplate.len-1])
        closingBounds.first += pos
        closingBounds.last += pos
        #of code
        adjustForStandaloneIndentation(closingBounds, pos, tmplate)

        var currentContext : Context
        var currentList : seq[Context]

        if matches[0] == "#":
          if c.getContext(tagKey, currentContext):
            #Render section
            var nc = newContext(currentContext)
            nc.parent = c
            result.add(render(tmplate[pos..closingBounds.first-1], nc, true))
          elif c.getList(tagKey, currentList):
            #Render list
            for cil in currentList:
              result.add(render(tmplate[pos..closingBounds.first-1], cil, true))
          elif c[tagKey] != "":
            #Truthy
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
          else:
            #Falsey
            discard
        else:
          if c.getContext(tagKey, currentContext):
            #Don't render section
            discard
          elif c.getList(tagKey, currentList):
            if currentList.len == 0:
              result.add(render(tmplate[pos..closingBounds.first-1], c, true))
          elif c[tagKey] == "":
            #Falsey is Truthy
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
          else:
            #Truthy is Falsey
            discard

        pos = closingBounds.last + 1

      else:
        substitutionImpl(escapeHTML(c[tagKey]))


when isMainModule:
  import commandeer
  import json

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

  proc usage(): string =
    result = "Usage: moustachu <context>.json <template>.moustache [--file=<outputFilename>]"

  commandline:
    argument jsonFilename, string
    argument tmplateFilename, string
    option outputFilename, string, "file", "f"
    exitoption "help", "h", usage()

  var c = contextFromPJsonNode(parseFile(jsonFilename))
  var tmplate = readFile(tmplateFilename)

  if outputFilename.isNil():
    echo render(tmplate, c)
  else:
    writeFile(outputFilename, render(tmplate, c))
