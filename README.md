#Moustachu

Moustachu is a([N im](https://github.com/Araq/nimrod))plementation of [Mustache](https://github.com/mustache/mustache) (get it?). Mustache is "logic-less templating".

##Usage

**In code**

```nimrod

import moustachu

var tmplate : string
var c : Context = newContext()
var m : Mustache

tmplate = """Hello {{name}}
You have just won {{value}} dollars!
{{#in_ca}}
Well, {{taxed_value}} dollars, after taxes.
{{/in_ca}}"""

c["name"] = "Chris"
c["value"] = 10000
c["taxed_value"] = 10000 - (10000 * 0.4)
c["in_ca"] = true

echo m.render(tmplate, c)
```

For other examples look at the `specs` directory

**On the command line**

```
$ moustachu <context>.json <template>.moustache
$ moustachu <context>.json <template>.moustache --file=<output>
```

The first version will print to stdout and the second will generate a file.

##Installation

The recommended way to install moustachu is through [babel](https://github.com/nim-lang/babel):

Install [babel](https://github.com/nim-lang/babel). Then do:

    $ babel install moustachu

This will install the latest tagged version of moustachu.

The moustachu package includes the moustachu binary to use on the command line and the moustachu library to use in your code.

##Design

- Make the interfaces with the data structures as dynamic-like as possible
- No lambdas, nor partials, nor set delimiters. At least for now. Let's keep it simple please.

##Test

Get the source code:

	$ git clone https://github.com/fenekku/moustachu.git
    $ cd moustachu
    $ nimrod c -r runTests.nim

This will test against the selected specs copied from [mustache/spec](https://github.com/mustache/spec)

##TODO

- Exception throwing toggle
- Clean up some parts
- Use to see what else to do/fix
- Adjust for Nimrod -> Nim transition when 0.10.0 hits