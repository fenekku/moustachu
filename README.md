#Moustachu

[![Build Status](https://circleci.com/gh/fenekku/moustachu/tree/master.png?style=shield&circle-token=d918d8055e112fb5661e85eba92691e39d1d4d12)](https://circleci.com/gh/fenekku/moustachu)

Moustachu is a([N im](https://github.com/Araq/Nim))plementation of [Mustache](https://github.com/mustache/mustache) (get it?). Mustache is "logic-less templating".

##Usage

**In code**

```nimrod

import moustachu


var tmplate = """Hello {{name}}
You have just won {{value}} dollars!
{{#in_ca}}
Well, {{taxed_value}} dollars, after taxes.
{{/in_ca}}"""

var c : Context = newContext()
c["name"] = "Chris"
c["value"] = 10000
c["taxed_value"] = 10000 - (10000 * 0.4)
c["in_ca"] = true

echo render(tmplate, c)
```

For other examples look at the `specs` directory

**On the command line**

```
$ moustachu <context>.json <template>.moustache
$ moustachu <context>.json <template>.moustache --file=<output>
```

The first version will print to stdout and the second will generate a file.

##Installation

The recommended way to install moustachu is through [nimble](https://github.com/nim-lang/nimble):

Install [nimble](https://github.com/nim-lang/nimble). Then do:

    $ nimble install moustachu

This will install the latest tagged version of moustachu.

The moustachu package includes the moustachu binary to use on the command line and the moustachu library to use in your code.

##Design

- Make the interfaces with the data structures as dynamic-like as possible
- No lambdas, nor partials, nor set delimiters. At least for now. Let's keep it simple please.

##Test

Get the source code:

	$ git clone https://github.com/fenekku/moustachu.git
    $ cd moustachu
    $ nim c -r runTests.nim

This will test against the selected specs copied from [mustache/spec](https://github.com/mustache/spec)

##TODO

- Turn this:

```nim
  context["array"] = newArrayContext()
  for e in array:
    context["array"].elems.add(string_from_e(e))
```

into this:

```nim
  context["array"] = map(string_from_e, array)
```

- lots of code refactorings
- assumes well-formed template: remove that assumption
- Exception throwing toggle
- Use to see what else to do/fix
- make faster