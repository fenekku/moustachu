
## A moustache templating engine written in Nim.

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
  openingTag = r"\{\{"
  closingTag = r"\}\}"
  tagRegex = re(openingTag & r"(\#|&|\^|!|\{)?((.|\s)+?)(\})?" & closingTag)
  htmlEscapeReplace = [(re"&","&amp;"),
                       (re"<","&lt;"),
                       (re">","&gt;"),
                       (re"\\","&#92;"),
                       (re("\""),"&quot;")]

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
  assert(c.kind == CObject)
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

proc merge(c1, c2: Context): Context =
  ## Return a new Context, the result of `c1` merged with `c2`.
  ## If `c2` is a CValue, then a pair (".", c2.val) is added to the
  ## merged context
  assert(c1.kind == CObject and c2.kind != CArray)
  new(result)
  result.kind = CObject
  result.fields = c1.fields #this copies
  if c2.kind == CValue:
    result["."] = c2
  else:
    for key, val in items(c2.fields):
      result[key] = val

proc `$`*(c: Context): string =
  ## Return a string representing the context. Useful for debugging
  result = "Context->["
  result &= "\nkind: " & $c.kind
  case c.kind
  of CValue: result &= "\nval: " & $c.val
  of CArray:
    var strArray = map(c.elems, proc(c: Context): string ="otherContext")
    result &= "\nelems: [" & join(strArray, "") & "]"
  of CObject:
    var strArray : seq[string] = @[]
    for key, val in items(c.fields):
      strArray.add(key & ": otherContext")
    result &= "\nfields: [" & join(strArray, ", ") & "]"
  result &= "\n]"

proc resolveContext(c: Context, tagkey: string): Context =
  ## Return the Context associated with `tagkey` where `tagkey`
  ## can be a dotted tag e.g. a.b.c .
  ## If the Context at `tagkey` does not exist, return nil.
  if tagkey == ".": return c["."]
  let subtagkeys = tagkey.split(".")
  var currCtx = c

  for subtagkey in subtagkeys:
    currCtx = currCtx[subtagkey]
    if currCtx == nil:
      break

  return currCtx

proc toString(j: JsonNode): string =
  ## Return string representation of jsonNode `j` relevant to moustache
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

proc resolveString(c: Context, tagkey: string): string =
  ## Return the string associated with `tagkey` in Context `c`.
  ## If the Context at `tagkey` does not exist, return the empty string.
  let currCtx = c.resolveContext(tagkey)
  if currCtx != nil:
    if currCtx.kind == CValue:
      return currCtx.val.toString()
    else: return $currCtx
  else: return ""

proc adjustForStandaloneIndentation(bounds: var tuple[first, last: int],
                                    pos: int, tmplate: string): void =
  ## Adjust `bounds` to follow how Moustache treats whitespace.
  ## TODO: See if there is a nicer way to do this
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
  ## Find the closing location for `tagKey` in `tmplate` given `offset`.
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
  ## Take a Moustache template `tmplate` and an evaluation Context `c`
  ## and return the rendered string. This is the main procedure.
  ## `inSection` is used to specify if the rendering is done from within
  ## a moustache section.
  var matches : array[4, string]
  var pos = 0
  var bounds : tuple[first, last: int]
  var renderings : seq[string] = @[]

  if not tmplate.contains(tagRegex):
    return tmplate

  while pos != tmplate.len:
    #Find a tag
    bounds = tmplate.findBounds(tagRegex, matches, start=pos)

    if bounds.first == -1:
      #No tag
      renderings.add(tmplate[pos..tmplate.len-1])
      pos = tmplate.len
      continue

    var tagKey = matches[1].strip()

    case matches[0]
    of "!":
      #Comments tag
      if not inSection:
        adjustForStandaloneIndentation(bounds, pos, tmplate)
      if bounds.first > 0:
        renderings.add(tmplate[pos..bounds.first-1])
      pos = bounds.last + 1

    of "{", "&":
      #Triple mustache tag: do not htmlescape
      if bounds.first > 0:
        renderings.add(tmplate[pos..bounds.first-1])
      renderings.add(c.resolveString(tagKey))
      pos = bounds.last + 1

    of "#", "^":
      #section tag
      adjustForStandaloneIndentation(bounds, pos, tmplate)
      if bounds.first > 0:
        #immediately add text before the tag
        renderings.add(tmplate[pos..bounds.first-1])
      pos = bounds.last + 1

      var closingBounds = findClosingBounds(tagKey, tmplate, pos)
      adjustForStandaloneIndentation(closingBounds, pos, tmplate)

      var ctx = c.resolveContext(tagkey)

      if matches[0] == "#" and ctx != nil:
        case ctx.kind
        of CObject:
          #Render section
          ctx = merge(c, ctx)
          renderings.add(render(tmplate[pos..closingBounds.first-1], ctx, true))
        of CArray:
          #Render list
          for ctxItem in ctx.elems:
            if ctxItem.kind != CArray:
              ctx = merge(c, ctxItem)
            else:
              ctx = c
            renderings.add(render(tmplate[pos..closingBounds.first-1], ctx, true))
        of CValue:
          case ctx.val.kind
          of JBool:
            if ctx.val.bval:
              renderings.add(render(tmplate[pos..closingBounds.first-1], c, true))
          of JNull:
            discard #do nothing
          else:
            renderings.add(render(tmplate[pos..closingBounds.first-1], c, true))

      elif matches[0] == "^":
        # "^" is for inversion: if Context exists, don't render
        if ctx == nil:
          renderings.add(render(tmplate[pos..closingBounds.first-1], c, true))
        else:
          case ctx.kind
          of CObject:
            discard #Don't render section
          of CArray:
            if len(ctx.elems) == 0:
              #Empty list is Truthy
              renderings.add(render(tmplate[pos..closingBounds.first-1], c, true))
          of CValue:
            case ctx.val.kind
            of JBool:
              if not ctx.val.bval:
                renderings.add(render(tmplate[pos..closingBounds.first-1], c, true))
            of JNull:
              renderings.add(render(tmplate[pos..closingBounds.first-1], c, true))
            else:
              discard #Don't render section

      pos = closingBounds.last + 1

    else:
      #Normal substitution
      if bounds.first > 0:
        renderings.add(tmplate[pos..bounds.first-1])
      renderings.add(parallelReplace(c.resolveString(tagKey), htmlEscapeReplace))
      pos = bounds.last + 1

  result = join(renderings, "")


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
