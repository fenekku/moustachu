import tables
import re
import strutils

type
  ## Context used to render the templates
  Context* = ref ContextObj
  ContextObj = object
    stringContext : Table[string, string]
    subContexts : Table[string, Context]
    listContexts : Table[string, seq[Context]]
    parent : Context

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
  result.stringContext = initTable[string, string](4)
  result.subContexts = initTable[string, Context](2)
  result.listContexts = initTable[string, seq[Context]](2)

proc newContext(c : Context): Context =
  ## Creates a new context from another one
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
  ## Assigns an int to a key in the context
  c.stringContext[key] = $value

proc `[]=`*(c: var Context; key: string, value: string) =
  ## Assigns a string to a key in the context
  c.stringContext[key] = $value

proc `[]=`*(c: var Context; key: string, value: float) =
  ## Assigns a float to a key in the context
  c.stringContext[key] = value.formatFloat(ffDefault, 0)

proc `[]=`*(c: var Context; key: string, value: bool) =
  ## Assigns a bool to a key in the context
  c.stringContext[key] = if value: "true" else: ""

proc `[]=`*(c: var Context; key: string; value: var Context) =
  ## Assigns a context to a key in the context
  ## This builds a subcontext
  value.parent = c
  c.subContexts[key] = value

proc `[]=`*(c: var Context; key: string; value: var openarray[Context]) =
  ## Assigns a list of contexts to a key in the context
  ## This creates a list
  var contextList = newSeq[Context]()
  for v in value:
    v.parent = c
    contextList.add(v)
  c.listContexts[key] = contextList

proc `$`*(c: Context): string =
  ## Returns a string representing the context. Useful for debugging
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
  ## Returns the string associated with the key in the context
  ## Always interpolated at this point
  ## The key can be a nested value where each level of nesting is
  ## delimited by a dot '.'. The key can also be a single '.'' which
  ## represents an implicit iterator i.e. parent context is a list and
  ## '.' iterates over the current element of that list.
  result = ""
  if key == "." and c.stringContext.hasKey(key):
    #Need to account for corner case of single . being a key
    #or is this b/c list element
    result = $c.stringContext[key]
  else:
    var dotIndex = key.find(re"\.")
    if dotIndex != -1:
      #unpack the nested key
      var firstKey = key[0..dotIndex-1]
      if c.subContexts.hasKey(firstKey):
        #go down the hierarchy
        var nc = c.subContexts[firstKey]
        var p = nc.parent                       # make parent nil to
        nc.parent = nil                         # prevent infinite loop
        result = nc[key[dotIndex+1..key.len-1]] # in case of badly formed
        c.subContexts[firstKey].parent = p      # template
      elif not c.parent.isNil():
        #go up the hierarchy
        result = c.parent[key]
      else:
        #when faced with problematic situation, output the empty string
        result = ""
    else:
      #not a nested key
      if c.stringContext.hasKey(key):
        result = $c.stringContext[key]
      elif not c.parent.isNil():
        result = c.parent[key]
      else:
        result = ""

proc getContext(c: Context, key: string, foundContext: var Context): bool =
  ## Assigns to `foundContext` the context associated to `key` in `c`.
  ## Returns whether that context was found.
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
  ## Assigns to `foundList` the seq of Contexts associated to `key` in `c`.
  ## Returns whether that seq was found.
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

proc escapeHTML(s: string): string =
  ## Replaces all html that needs to be escaped by its escaped value
  result = parallelReplace(s, htmlEscapeReplace)

proc findClosingBounds(tagKey: string, tmplate: string,
                       offset: int): tuple[first, last:int] =
  ## Finds the closing tuple for `tagKey` in `tmplate` starting at
  ## `offset`. The returned bounds tuple is absolute (it incorporates
  ## `offset`)
  ## Potential TODO: double check for unbalanced sections
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

  # closingTagBounds.first += pos
  # closingTagBounds.last += pos

  return closingTagBounds

template substitutionImpl(s: string) =
  ## This is a convenience template (the equivalent to a C macro)
  ## used to keep things DRY. it is only used in render.
  ## It appends to the result of render the Moustache tmplate text
  ## from `pos` up to and including the interpreted tag `s`
  ## This piece of code makes use of variables that are in the block
  ## of code calling `substitutionImpl`
  if bounds.first == 0:
    result.add(s)
  else:
    result.add(tmplate[pos..bounds.first-1] & s)

proc render*(tmplate: string, c: Context, inSection: bool = false): string =
  ## Takes a Moustache template `tmplate` and an evaluation context `c`
  ## and returns the rendered string. This is the main procedure.
  ## `insection` is used to specify if the rendering is done from within
  ## a moustache section.
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
    else:
      var tagKey = matches[1].strip()

      case matches[0]
      of "!":
        #Comments tag
        if inSection:
          discard
        else:
          adjustForStandaloneIndentation(bounds, pos, tmplate)
        if bounds.first > 0:
          result.add(tmplate[pos..bounds.first-1])
        pos = bounds.last + 1

      of "{", "&":
        #Triple mustache tag: do not htmlescape
        substitutionImpl(c[tagKey])
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
          # "^" is for inversion: if tagKey exists, don't render
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
        pos = bounds.last + 1


when isMainModule:
  import commandeer
  import json

  proc contextFromValue(node: JsonNode): Context =
    ## Returns a Context for `node` corresponding to a list item
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
      quit "contextFromValue() error, node= " & $node

  proc contextFromPJsonNode(node: JsonNode): Context =
    ## Returns a Context for `node` corresponding to a JSON object
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
