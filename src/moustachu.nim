
## A mustache templating engine written in Nim.

import strutils
import sequtils
import os
import json

import moustachupkg/context
import moustachupkg/tokenizer

export context

proc lookupContext(contextStack: seq[Context], tagkey: string): Context =
  ## Return the Context associated with `tagkey` where `tagkey`
  ## can be a dotted tag e.g. a.b.c
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

proc lookupString(contextStack: seq[Context], tagkey: string): string =
 ## Return the string associated with `tagkey` in Context `c`.
 ## If the Context at `tagkey` does not exist, return the empty string.
 result = lookupContext(contextStack, tagkey).toString()

proc ignore(tag: string, tokens: seq[Token], index: int): int =
  #ignore
  var i = index + 1
  var nexttoken = tokens[i]
  var openedsections = 1
  let lentokens = len(tokens)

  while i < lentokens and openedsections > 0:
    if nexttoken.value == tag:
      if nexttoken.tokentype in [TokenType.section, TokenType.invertedsection]:
        openedsections += 1
      elif nexttoken.tokentype == TokenType.ender:
        openedsections -= 1
      else: discard
    else: discard

    i += 1
    if i < lentokens:
      nexttoken = tokens[i]

  return i

proc parallelReplace(str: string,
                     substitutions: openArray[tuple[pattern: string, by: string]]): string =
  ## Returns a modified copy of `str` with the `substitutions` applied
  result = str
  for sub in substitutions:
    result = result.replace(sub[0], sub[1])

proc render*(tmplate: string, contextStack: seq[Context], partialsDir="."): string =
  ## Take a mustache template `tmplate`, a seq of evaluation Context's, and an optional
  ## path `partialsDir` (by default set to the current directory) which may contain partial files
  ## and return the rendered string. This is the main procedure.
  let
    htmlReplaceBy = [("&", "&amp;"),
                     ("<", "&lt;"),
                     (">", "&gt;"),
                     ("\\", "&#92;"),
                     ("\"", "&quot;")]

  var renderings : seq[string] = @[]

  #Object
  var sections : seq[string] = @[]
  var contextStack = contextStack

  #Array
  var loopStartPositions : seq[int] = @[]
  var loopCounters : seq[int] = @[]

  #Indentation
  var indentation = ""

  let tokens = toSeq(tokenizer.tokenize(tmplate))
  let lentokens = len(tokens)

  var index = 0

  while index < lentokens:
    let token = tokens[index]

    case token.tokentype
    of TokenType.comment:
      discard

    of TokenType.escapedvariable:
      var viewvalue = contextStack.lookupString(token.value)
      viewvalue = viewvalue.parallelReplace(htmlReplaceBy)
      renderings.add(viewvalue)

    of TokenType.unescapedvariable:
      var viewvalue = contextStack.lookupString(token.value)
      renderings.add(viewvalue)

    of TokenType.section:
      let ctx = contextStack.lookupContext(token.value)
      if ctx == nil:
        index = ignore(token.value, tokens, index)
        continue
      elif ctx.kind == CObject:
        # enter a new section
        if ctx.len == 0:
          index = ignore(token.value, tokens, index)
          continue
        else:
          contextStack.add(ctx)
          sections.add(token.value)
      elif ctx.kind == CArray:
        # update the array loop stacks
        if ctx.len == 0:
          index = ignore(token.value, tokens, index)
          continue
        else:
          #do looping
          index += 1
          loopStartPositions.add(index)
          loopCounters.add(ctx.len)
          sections.add(token.value)
          contextStack.add(ctx[ctx.len - loopCounters[^1]])
          continue
      elif ctx.kind == CValue:
        if not ctx:
          index = ignore(token.value, tokens, index)
          continue
        else: discard #we will render the text inside the section

    of TokenType.invertedsection:
      let ctx = contextStack.lookupContext(token.value)
      if ctx != nil:
        if ctx.kind == CObject:
          index = ignore(token.value, tokens, index)
          continue
        elif ctx.kind == CArray:
          if ctx.len != 0:
            index = ignore(token.value, tokens, index)
            continue
        elif ctx.kind == CValue:
          if ctx:
            index = ignore(token.value, tokens, index)
            continue
          else: discard #we will render the text inside the section

    of TokenType.ender:
      var ctx = contextStack.lookupContext(token.value)
      if ctx != nil:
        if ctx.kind == CObject:
          discard contextStack.pop()
          discard sections.pop()
        elif ctx.kind == CArray:
          if ctx.len > 0:
            loopCounters[^1] -= 1
            discard contextStack.pop()
            if loopCounters[^1] == 0:
              discard loopCounters.pop()
              discard loopStartPositions.pop()
              discard sections.pop()
            else:
              index = loopStartPositions[^1]
              contextStack.add(ctx[ctx.len - loopCounters[^1]])
              continue

    of TokenType.indenter:
      if token.value != "":
        indentation = token.value
        renderings.add(indentation)

    of TokenType.partial:
      var partialTemplate = contextStack.lookupString(token.value)
      if partialTemplate == "":
        var partialsFileName = partialsDir.joinPath(token.value & ".mustache")
        partialTemplate = (try: readFile(partialsFileName) except: "")
      partialTemplate = partialTemplate.replace("\n", "\n" & indentation)
      if indentation != "":
        partialTemplate = partialTemplate.strip(leading=false, chars={' '})
      indentation = ""
      renderings.add(render(partialTemplate, contextStack, partialsDir))

    else:
      renderings.add(token.value)

    index += 1

  result = join(renderings, "")

proc render*(tmplate: string, c: Context, partialsDir="."): string =
  ## Take a mustache template `tmplate`, an evaluation Context `c`, and an optional
  ## path `partialsDir` (by default set to the current directory) which may contain partial files
  ## and return the rendered string.
  var contextStack = @[c]
  result = tmplate.render(contextStack, partialsDir)

proc render*(tmplate: string, jsonContext: JsonNode, partialsDir="."): string =
  ## Take a mustache template `tmplate`, an evaluation context as a JsonNode, and an optional
  ## path `partialsDir` (by default set to the current directory) which may contain partial files
  ## and return the rendered string.
  let nc = newContext(jsonContext)
  var contextStack = @[nc]
  result = tmplate.render(contextStack, partialsDir)

proc renderFile*(filepath: string, ctx: Context, partialsDir: string=""): string =
  ## renders a mustache template from a file
  ##
  ## @param filepath
  ## @param ctx           the values passed into the template
  ## @param partialsDir   if not set; pulls path from filepath
  var
    dir, name, ext, finalDir: string
    content: string = ""
  result = ""
  if partialsDir == "":
    (dir, name, ext) = splitFile(filepath)
    if dir != "":
      finalDir = dir
    else:
      finalDir = "."
  else:
    finalDir = partialsDir

  if fileExists(filepath):
    content = readFile(filepath)
  result = render(content, ctx, partialsDir=finalDir)

proc renderFile*(filepath: string, jsonContext: JsonNode, partialsDir: string=""): string =
  ## renders a mustache template from a file
  ##
  ## @param filepath
  ## @param jsonContext   the values passed into the template (as JSON)
  ## @param partialsDir   if not set; pulls path from filepath
  let nc = newContext(jsonContext)
  result = renderFile(filepath, nc, partialsDir)

when isMainModule:
  import json
  import commandeer

  proc usage(): string =
    result = "Usage! moustachu <context>.json <template>.mustache [--file=<outputFilename>]"

  commandline:
    argument jsonFilename, string
    argument tmplateFilename, string
    option outputFilename, string, "file", "f"
    exitoption "help", "h", usage()
    exitoption "version", "v", "0.13.0"
    errormsg usage()

  var c = newContext(parseFile(jsonFilename))
  var tmplate = readFile(tmplateFilename)
  var pwd = parentDir(tmplateFileName)

  if outputFilename.len == 0:
    echo render(tmplate, c, pwd)
  else:
    writeFile(outputFilename, render(tmplate, c, pwd))
