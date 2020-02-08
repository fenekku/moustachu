import json
import sequtils
import strutils
import tables


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
      val: JsonNode
    of CArray:
      elems: seq[Context]
    of CObject:
      fields: Table[string, Context]

## Builders

proc newContext*(j : JsonNode = nil): Context =
  ## Create a new Context based on a JsonNode object
  new(result)
  if j == nil:
    result = Context(kind: CObject)
    result.fields = initTable[string, Context](4)
  else:
    case j.kind
    of JObject:
      result = Context(kind: CObject)
      result.fields = initTable[string, Context](4)
      for key, val in pairs(j.fields):
        result.fields[key] = newContext(val)
    of JArray:
      result = Context(kind: CArray)
      result.elems = @[]
      for val in j.elems:
        result.elems.add(newContext(val))
    else:
      result = Context(kind: CValue)
      result.val = j

proc newContext*(c: Context): Context =
  ## Create a new Context based on an existing context. The new Context
  ## is an unconnected copy of the existing context simply containing the
  ## values of the original.
  ## 
  ## Some code to demonstrate:
  ## 
  ## .. code:: nim
  ## 
  ##     import moustachu
  ## 
  ##     var a = newContext()
  ##     a["test"] = "original"
  ## 
  ##     var b = a              # copy the pointer to b
  ##     var c = newContext(a)  # copy the content to c
  ##
  ##     b["test"] = "changed"
  ## 
  ##     echo a["test"].toString()  # -> "changed"
  ##     echo b["test"].toString()  # -> "changed"
  ##     echo c["test"].toString()  # -> "original"
  new(result)
  if c == nil:
    result.kind = CObject
    result.fields = initTable[string, Context](4)
  else:
    result.kind = c.kind
    case c.kind
    of CValue:
      result.val = c.val
    of CArray:
      result.elems = @[]
      for item in c.elems:
        result.elems.add(newContext(item))
    of CObject:
      result.fields = initTable[string, Context](4)
      for key, val in pairs(c.fields):
        result.fields[key] = newContext(val)

proc newArrayContext*(): Context =
  ## Create a new Context of kind CArray
  result = Context(kind: CArray)
  result.elems = @[]

proc internal_set(value: string): Context =
  newContext(newJString(value))

proc internal_set(value: int): Context =
  newContext(newJInt(value))

proc internal_set(value: float): Context =
  newContext(newJFloat(value))

proc internal_set(value: bool): Context =
  newContext(newJBool(value))

## ## Getters

proc `[]`*(c: Context, key: string): Context =
  ## Return the Context associated with `key`.
  ## If the Context at `key` does not exist, return nil.
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  if c.kind != CObject: return nil
  if c.fields.hasKey(key): return c.fields[key] else: return nil

proc `[]`*(c: Context, index: int): Context =
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  if c.kind != CArray: return nil else: return c.elems[index]

## Setters

proc `[]=`*(c: var Context, key: string, value: Context) =
  ## Assign a context `value` to `key` in context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c.fields[key] = value

proc `[]=`*(c: var Context, key: string, value: JsonNode) =
  ## Convert and assign `value` to `key` in `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = newContext(value)

proc `[]=`*(c: var Context; key: string, value: BiggestInt) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = newContext(newJInt(value))

proc `[]=`*(c: var Context; key: string, value: string) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = newContext(newJString(value))

proc `[]=`*(c: var Context; key: string, value: float) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = newContext(newJFloat(value))

proc `[]=`*(c: var Context; key: string, value: bool) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = newContext(newJBool(value))

proc `[]=`*(c: var Context, key: string, value: openarray[Context]) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  var contextList = newArrayContext()
  for v in value:
    contextList.elems.add(v)
  c[key] = contextList

proc `[]=`*(c: var Context, key: string, value: openarray[string]) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = map(value, proc(x: string): Context = newContext(newJString(x)))

proc `[]=`*(c: var Context, key: string, value: openarray[int]) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = map(value, proc(x: int): Context = newContext(newJInt(x)))

proc `[]=`*(c: var Context, key: string, value: openarray[float]) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = map(value, proc(x: float): Context = newContext(newJFloat(x)))

proc `[]=`*(c: var Context, key: string, value: openarray[bool]) =
  ## Assign `value` to `key` in Context `c`
  assert(c != nil, "Context is nil. Did you forget to initialize with newContext()?")
  assert(c.kind == CObject)
  c[key] = map(value, proc(x: bool): Context = newContext(newJBool(x)))

proc add*(c: Context, value: Context) =
  ## Add 'value' object to array.
  assert(c.kind == CArray)
  c.elems.add(value)

proc add*[T: string, int, float, bool](c: Context, value: T) =
  ## Add 'value' to array. Reference later with dot substitution "{{.}}"
  assert(c.kind == CArray)
  c.elems.add(internal_set(value))

## Printers

proc `$`*(c: Context): string =
  ## Return a string representing the context. Useful for debugging
  if c == nil:
    result = "Context->nil"
    return
  result = "Context->[kind: " & $c.kind
  case c.kind
  of CValue:
    if c.val.str == "":
      result &= "\nval: "
    else:
      result &= "\nval: " & $c.val
  of CArray:
    if c.elems == @[]:
      result &= "\nnot initialized"
    else:
      var strArray = map(c.elems, proc(c: Context): string = $c)
      result &= "\nelems: [" & join(strArray, ", ") & "]"
  of CObject:
    var strArray : seq[string] = @[]
    for key, val in pairs(c.fields):
      strArray.add(key & ": " & $val)
    result &= "\nfields: {" & join(strArray, ", ") & "}"
  result &= "\n]"

proc toString*(c: Context): string =
  ## Return string representation of `c` relevant to mustache
  if c != nil:
    if c.kind == CValue:
      case c.val.kind
      of JString:
        if c.val.str == "":
          return ""
        return c.val.str
      of JFloat:
       return c.val.fnum.formatFloat(ffDefault, -1)
      of JInt:
       return $c.val.num
      of JNull:
       return ""
      of JBool:
       return if c.val.bval: "true" else: ""
      else:
       return $c.val
    else:
      return $c
  else:
    return ""

proc len*(c: Context): int =
  if c.kind == CArray: 
    result = c.elems.len
  elif c.kind == CObject:
    result = c.fields.len
  else: discard

converter toBool*(c: Context): bool =
  assert(c.kind == CValue)
  case c.val.kind
  of JBool: result = c.val.bval
  of JNull: result = false
  of JString: result = c.val.str != ""
  else: result = true

proc newContext*[T: string | int | bool | float](d: openarray[tuple[key: string, value: T ]]): Context =
  ## Create a new Context based on an array of [string, T] tuples
  ## 
  ## For example, you could do:
  ##     var c = NewContext({"x": 7, "y": -20})
  ## or,
  ##     var c = NewContext({"r": "apple", "b": "bike"})
  ## or, if you must:
  ##     var c = NewContext([("r", "apple"), ("b", "tunnel")])
  var c = newContext()
  for entry in d:
    c[entry.key] = entry.value
  return c
