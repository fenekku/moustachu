# import tables
import re
import strutils
import json

type
  ## Context used to render the templates
  Context* = ref ContextObj
  ContextObj = object
    j : JsonNode
    # stringContext : Table[string, string]
    # subContexts : Table[string, Context]
    # listContexts : Table[string, seq[Context]]
    currentContext : seq[string]

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
  currentContext = @[]
  # result.stringContext = initTable[string, string](4)
  # result.subContexts = initTable[string, Context](2)
  # result.listContexts = initTable[string, seq[Context]](2)

proc newContext(c : Context): Context =
  ## Creates a new context from another one
  result = newContext()
  result.j = copy(c.j)
  result.currentContext = copy(c.currentContext)
  # for key, value in c.stringContext.pairs():
  #   result.stringContext[key] = value
  # for key, value in c.subContexts.mpairs():
  #   value.parent = result
  #   result.subContexts[key] = value
  # for key, value in c.listContexts.mpairs():
  #   for v in value:
  #     v.parent = result
  #   result.listContexts[key] = value

proc `[]=`*(c: var Context; key: string, value: BiggestInt) =
  ## Assigns an int to a key in the context
  ## Convert to string immediately
  c.j[key] = newJString($value)

proc `[]=`*(c: var Context, key: string, value: string) =
  ## Assigns a string to a key in the context
  c.j[key] = newJString($value)

proc `[]=`*(c: var Context, key: string, value: float) =
  ## Assigns a float to a key in the context
  c.j[key] = newJString(value.formatFloat(ffDefault, 0))

proc `[]=`*(c: var Context, key: string, value: bool) =
  ## Assigns a bool to a key in the context
  c.j[key] = newJString(if value: "true" else: "")

proc `[]=`*(c: var Context, key: string, value: Context) =
  ## Assigns the `value` context to `key` in the `c` context
  ## This builds a subcontext.
  c.j[key] = value.j

proc `[]=`*(c: var Context, key: string, value: openarray[Context]) =
  ## Assigns a list of contexts to a key in the context
  ## This creates a list
  var contextList = newJArray()
  for v in value:
    contextList.elems.add(v)
  c.j[key] = contextList

proc `$`*(c: Context): string =
  ## Returns a string representing the context. Useful for debugging
  # result = "{"
  # for key, value in c.stringContext.pairs():
  #   if result.len > 1: result.add(", ")
  #   result.add($key)
  #   result.add(": ")
  #   result.add($value)

  # for key, value in c.subContexts.pairs():
  #   if result.len > 1: result.add(", ")
  #   result.add($key)
  #   result.add(":")
  #   result.add($value)

  # for key, value in c.listContexts.pairs():
  #   if result.len > 1: result.add(", ")
  #   result.add($key)
  #   result.add(":")
  #   result.add("[")
  #   var subresult = ""
  #   for val in value:
  #     if subresult.len > 1: subresult.add(", ")
  #     subresult.add($val)
  #   result.add(subresult)
  #   result.add("]")

  # result.add("}")
  result = pretty(c.j) & "currentContext : " & $c.currentContext

proc getInnerJson(c: Context, key : string): JObject =
  ## Returns the inner Json associated with `relativeKey` in the context
  ## `relativeKey` can be a nested value where each level of nesting is
  ## delimited by a dot '.'. The key can also be a single '.' which
  ## represents an implicit iterator i.e. parent context is a list and
  ## '.' iterates over the current element of that list.
  ## Returns a JNull object if the key is invalid
  var relativeKey : seq[string] = @[]

  #build the relative part
  if key == ".":
    # iterator element
    relativeKey.add(key)
  else:
    for subKey in key.split("."):
      relativeKey.add(subKey)

  var goOn = true
  var nestedSections = copy(c.currentSection)
  result = c.j

  while goOn:
    #build the absolute key path as a sequence of keys
    var absoluteKey = nestedSections & relativeKey

    for subKey in absoluteKey:
      if result.hasKey(subKey):
        result = result[subKey]
      else:
        if nestedSections.len > 0:
          discard nestedSections.pop()
        else:
          goOn = false
        break

    return result

  return newJNull() #key is invalid


proc `[]`(c: Context, key: string): string =
  ## Returns the string associated with the key in the context
  ## The key can be a nested value where each level of nesting is
  ## delimited by a dot '.'. The key can also be a single '.'' which
  ## represents an implicit iterator i.e. parent context is a list and
  ## '.' iterates over the current element of that list.
  ## Returns the empty string if key is invalid.
  var jsonNode = c.getInnerJson(key)

  if jsonNode.kind == json.JString:
    return jsonNode.str
  elif jsonNode.kind != json.JNull:
    return $jsonNode #return string representation of that JsonNode
  else:
    return ""


# proc getContext(c: Context, key: string, foundContext: var Context): bool =
#   ## Assigns to `foundContext` the context associated to `key` in `c`.
#   ## Returns whether that context was found.
#   var dotIndex = key.find(re"\.")
#   if dotIndex != -1:
#     var firstKey = key[0..dotIndex-1]
#     if c.subContexts.hasKey(firstKey):
#       result = c.subContexts[firstKey].getContext(key[dotIndex+1..key.len-1], foundContext)
#     elif not c.parent.isNil():
#       result = c.parent.getContext(key, foundContext)
#     else:
#       #TODO toggle Exception
#       result = false
#   else:
#     if c.subContexts.hasKey(key):
#       foundContext = c.subContexts[key]
#       result = true
#     elif not c.parent.isNil():
#       result = c.parent.getContext(key, foundContext)
#     else:
#       #TODO toggle Exception
#       result = false

# proc getList(c: Context, key: string, foundList: var seq[Context]): bool =
#   ## Assigns to `foundList` the seq of Contexts associated to `key` in `c`.
#   ## Returns whether that seq was found.
#   var dotIndex = key.find(re"\.")
#   if dotIndex != -1:
#     var firstKey = key[0..dotIndex-1]
#     if c.subContexts.hasKey(firstKey):
#       result = c.subContexts[firstKey].getList(key[dotIndex+1..key.len-1], foundList)
#     elif not c.parent.isNil():
#       result = c.parent.getList(key, foundList)
#     else:
#       result = false
#   else:
#     if c.listContexts.hasKey(key):
#       foundList = c.listContexts[key]
#       result = true
#     elif not c.parent.isNil():
#       result = c.parent.getList(key, foundList)
#     else:
#       result = false

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

        var innerJson = c.getInnerJson(tagKey)
        # var currentContext : Context
        # var currentList : seq[Context]

        if matches[0] == "#":
          if innerJson.kind == json.JObject:
            #Render section
            c.currentContext.add(tagKey)
            result.add(render(tmplate[pos..closingBounds.first-1], c, true))
            discard c.currentContext.pop()
          elif innerJson.kind == json.JArray:
            #Render list
            var jsonContainingTagKey = c.getInnerJson("") #must be a ref
            for jsonItem in innerJson.items():
              #redefine the content of the tagKey
              jsonContainingTagKey[tagKey] = jsonItem
              result.add(render(tmplate[pos..closingBounds.first-1], c, true))
            #redefine it back
            jsonContainingTagKey[tagKey] = innerJson
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
