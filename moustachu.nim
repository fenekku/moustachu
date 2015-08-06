
## A mustache templating engine written in Nim.

import re
import strutils
import json

type
  ContextKind* = enum ## possible Context types
    CArray,
    CObject,
    CValue

  ## Context used to render a mustache template
  Context* = ref ContextObj
  ContextObj = object
    case kind*: ContextKind
    of CValue:
      val*: JsonNode
    of CArray:
      elems*: seq[Context]
    of CObject:
      fields*: seq[tuple[key: string, val: Context]]

let
  tagOpening = r"\{\{"
  tagClosing = r"\}\}"
  tagRegex = re(tagOpening & r"(\#|&|\^|!|\{|/)?((?:.|\s)+?)\}?" & tagClosing)
  htmlEscapeReplace = [(re"&", "&amp;"),
                       (re"<", "&lt;"),
                       (re">", "&gt;"),
                       (re"\\", "&#92;"),
                       (re("\""), "&quot;")]

proc newContext*(j : JsonNode = nil): Context =
  ## Create a new Context based on a JsonNode object
  new(result)
  if j == nil:
    result.kind = CObject
    result.fields = @[]
  else:
    case j.kind
    of JObject:
      result.kind = CObject
      result.fields = @[]
      for key, val in items(j.fields):
        result.fields.add((key, newContext(val)))
    of JArray:
      result.kind = CArray
      result.elems = @[]
      for val in j.elems:
        result.elems.add(newContext(val))
    else:
      result.kind = CValue
      result.val = j

proc newArrayContext*(): Context =
  ## Create a new Context of kind CArray
  new(result)
  result.kind = CArray
  result.elems = @[]

proc `[]`*(c: Context, key: string): Context =
  ## Return the Context associated with `key`.
  ## If the Context at `key` does not exist, return nil.
  assert(c != nil)
  if c.kind != CObject: return nil
  for name, item in items(c.fields):
    if name == key:
      return item
  return nil

# -------------- proc to manually build a Context ----------------
proc `[]=`*(c: var Context, key: string, value: Context) =
  ## Assign a context `value` to `key` in context `c`
  assert(c.kind == CObject)
  for i in 0..len(c.fields)-1:
    if c.fields[i].key == key:
      c.fields[i].val = value
      return
  c.fields.add((key, value))

proc `[]=`*(c: var Context; key: string, value: BiggestInt) =
  ## Assign `value` to `key` in Context `c`
  assert(c.kind == CObject)
  c[key] = newContext(newJInt(value))

proc `[]=`*(c: var Context; key: string, value: string) =
  ## Assign `value` to `key` in Context `c`
  assert(c.kind == CObject)
  c[key] = newContext(newJString(value))

proc `[]=`*(c: var Context; key: string, value: float) =
  ## Assign `value` to `key` in Context `c`
  assert(c.kind == CObject)
  c[key] = newContext(newJFloat(value))

proc `[]=`*(c: var Context; key: string, value: bool) =
  ## Assign `value` to `key` in Context `c`
  assert(c.kind == CObject)
  c[key] = newContext(newJBool(value))

proc `[]=`*(c: var Context, key: string, value: openarray[Context]) =
  ## Assign `value` to `key` in Context `c`
  assert(c.kind == CObject)
  var contextList = newArrayContext()
  for v in value:
    contextList.elems.add(value)
  c[key] = contextList

# -----------------------------------------------------------------

proc `$`*(c: Context): string =
  ## Return a string representing the context. Useful for debugging
  result = "Context->["
  result &= "\nkind: " & $c.kind
  case c.kind
  of CValue: result &= "\nval: " & $c.val
  of CArray:
    var strArray = map(c.elems, proc(c: Context): string ="otherContext")
    result &= "\nelems: [" & join(strArray, ", ") & "]"
  of CObject:
    var strArray : seq[string] = @[]
    for key, val in items(c.fields):
      strArray.add(key & ": otherContext")
    result &= "\nfields: [" & join(strArray, ", ") & "]"
  result &= "\n]"

proc resolveContext(contextStack: seq[Context], tagkey: string): Context =
  ## Return the Context associated with `tagkey` where `tagkey`
  ## can be a dotted tag e.g. a.b.c .
  ## If the Context at `tagkey` does not exist, return nil.
  var currCtx = contextStack[contextStack.high]
  if tagkey == ".": return currCtx
  let subtagkeys = tagkey.split(".")
  for i in countDown(contextStack.high, contextStack.low):
    currCtx = contextStack[i]

    for subtagkey in subtagkeys:
      currCtx = currCtx[subtagkey]
      if currCtx == nil:
        break

    if currCtx != nil:
      return currCtx

  return currCtx

proc toString(j: JsonNode): string =
  ## Return string representation of jsonNode `j` relevant to mustache
  case j.kind
  of JString:
    return j.str
  of JFloat:
    return j.fnum.formatFloat(ffDefault, 0)
  of JInt:
    return $j.num
  of JNull:
    return ""
  of JBool:
    return if j.bval: "true" else: ""
  else:
    return $j

proc resolveString(contextStack: seq[Context], tagkey: string): string =
  ## Return the string associated with `tagkey` in Context `c`.
  ## If the Context at `tagkey` does not exist, return the empty string.
  let currCtx = resolveContext(contextStack, tagkey)
  if currCtx != nil:
    if currCtx.kind == CValue:
      return currCtx.val.toString()
    else: return $currCtx
  else: return ""

proc adjustForStandaloneIndentation(bounds: var tuple[first, last: int],
                                    tmplate: string) =
  ## Adjust `bounds` to follow how mustache treats whitespace.
  var first = bounds.first
  var index = bounds.first - 1

  #Check if the left side is empty
  var ls_empty = false
  while index > -1 and tmplate[index] in {' ', '\t'}: dec(index)
  if index == -1:
    first = 0
    ls_empty = true
  elif tmplate[index] == '\l':
    first = index + 1
    ls_empty = true

  #Check if the right side is empty
  if ls_empty:
    index = bounds.last + 1
    while index < tmplate.len and tmplate[index] in {' ', '\t'}: inc(index)
    if index == tmplate.len:
      bounds.first = first
      bounds.last = index - 1
    elif tmplate[index] == '\c':
      if tmplate[index+1] == '\l':
        inc(index)
      bounds.first = first
      bounds.last = index
    elif tmplate[index] == '\l':
      bounds.first = first
      bounds.last = index

proc findClosingBounds(tagKey: string, tmplate: string,
                       offset: int): tuple[first, last:int] =
  ## Find the closing location for `tagKey` in `tmplate` given `offset`.
  var numOpenSections = 1
  var matches : array[1, string]
  #TODO: take this out
  let openingOrClosingTagRegex = re(tagOpening & r"(\#|\^|/)\s*" &
                                    tagKey & r"\s*" & tagClosing)
  var closingTagBounds : tuple[first, last: int]
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

proc render*(tmplate: string, c: Context): string =
  ## Take a mustache template `tmplate` and an evaluation Context `c`
  ## and return the rendered string. This is the main procedure.
  var matches : array[2, string]
  var renderings : seq[string] = @[]
  var sections : seq[string] = @[]
  var contexts : seq[Context] = @[]
  #TODO: join those two together
  var loopCounters : seq[int] = @[]
  var loopPositions : seq[int] = @[]

  var pos = 0

  var tag = (bounds: (first: -1, last:0), key: "", symbol: "")

  contexts.add(c)

  while pos < tmplate.len:
    #Find a tag
    tag.bounds = tmplate.findBounds(tagRegex, matches, start=pos)
    tag.symbol = matches[0]
    tag.key = if matches[1] != nil: matches[1].strip() else: matches[1]

    #No tag
    if tag.bounds.first == -1:
      renderings.add(tmplate[pos..tmplate.len-1])
      pos = tmplate.len
      continue

    # A tag
    if tag.symbol in @["!", "#", "^", "/"]:
      # potentially standalone tag
      adjustForStandaloneIndentation(tag.bounds, tmplate)

    # output raw text before tag
    if tag.bounds.first > 0:
      renderings.add(tmplate[pos..tag.bounds.first-1])

    pos = tag.bounds.last + 1

    case tag.symbol
    of "!":
      # Comment
      continue

    of "{", "&":
      # Triple mustache tag: do not htmlescape
      renderings.add(resolveString(contexts, tag.key))

    of "#", "^":
      # Section tag
      var ctx = resolveContext(contexts, tag.key)

      if tag.symbol == "#":
        # Context or list
        if ctx == nil:
          var closingBounds = findClosingBounds(tag.key, tmplate, pos)
          pos = closingBounds.last+1

        elif ctx.kind == CObject:
          # enter a new section
          contexts.add(ctx)
          sections.add(tag.key)

        elif ctx.kind == CArray:
          # update the array loop stacks
          if ctx.elems.len > 0:
            loopCounters.add(ctx.elems.len)
            loopPositions.add(tag.bounds.last + 1)
            sections.add(tag.key)
            contexts.add(ctx.elems[ctx.elems.len - loopCounters[^1]])
          else:
            var closingBounds = findClosingBounds(tag.key, tmplate, pos)
            pos = closingBounds.last+1

        elif ctx.kind == CValue:
          case ctx.val.kind
          of JBool:
            if not ctx.val.bval:
              var closingBounds = findClosingBounds(tag.key, tmplate, pos)
              pos = closingBounds.last+1
          of JNull:
            var closingBounds = findClosingBounds(tag.key, tmplate, pos)
            pos = closingBounds.last+1
          else: discard #we will render the text inside the section

      elif tag.symbol == "^":
        # "^" is for inversion:
        # if Context exists, don't render
        # if Context does not exist, render
        if ctx != nil:
          case ctx.kind
          of CObject:
            var closingBounds = findClosingBounds(tag.key, tmplate, pos)
            pos = closingBounds.last+1
          of CArray:
            if len(ctx.elems) != 0:
              # Non-empty list is falsy
              var closingBounds = findClosingBounds(tag.key, tmplate, pos)
              pos = closingBounds.last+1
          of CValue:
            case ctx.val.kind
            of JBool:
              if ctx.val.bval:
                var closingBounds = findClosingBounds(tag.key, tmplate, pos)
                pos = closingBounds.last+1
            of JNull: discard #we will render the text inside the section
            else:
              var closingBounds = findClosingBounds(tag.key, tmplate, pos)
              pos = closingBounds.last+1

    of "/":
      # Closing section tag
      var ctx = resolveContext(contexts, tag.key)

      if ctx != nil:
        # account for empty inverted section
        if ctx.kind == CObject:
          if sections[^1] == tag.key:
            discard contexts.pop()
            discard sections.pop()

        elif ctx.kind == CArray:
          if loopCounters.len == 0:
            # if closing an inverted section
            continue

          dec(loopCounters[^1])

          if loopCounters[^1] == 0:
            discard contexts.pop()
            discard sections.pop()
            discard loopCounters.pop()
            discard loopPositions.pop()
          else:
            discard contexts.pop()
            contexts.add(ctx.elems[ctx.elems.len - loopCounters[^1]])
            pos = loopPositions[^1]

    else:
      #Normal substitution
      renderings.add(parallelReplace(resolveString(contexts, tag.key),
                                     htmlEscapeReplace))

  result = join(renderings, "")


when isMainModule:
  import commandeer

  proc usage(): string =
    result = "Usage: moustachu <context>.json <template>.mustache [--file=<outputFilename>]"

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
