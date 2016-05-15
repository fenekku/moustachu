
## Simple benchmarking using a template similar to
## https://github.com/mustache/mustache/blob/master/benchmarks/render_template_profile.rb

import json
import times

import moustachu


let templ = """
{{#products}}
  <div class='product_brick'>
    <div class='container'>
      <div class='element'>
        <img src='images/{{image.file}}' class='{{image.class}}' />
      </div>
      <div class='element description'>
        <a href="{{url}}" class='product_name block bold'>
          {{external_index}}
        </a>
      </div>
    </div>
  </div>
{{/products}}
"""

let product = %* {
  "external_index": "product",
  "url": "/products/7",
  "image": {
    "file": "products/product.jpg",
    "class": "product_miniature"
  }
}

var data = parseJson(""" { "products": [] } """)

for i in 1..200:
  data["products"].add(product)

let start = epochTime()
var result = ""

for i in 1..2000:
  var ctx = newContext(data)
  result = templ.render(ctx)

let t =  epochTime() - start
# echo result
echo "Avg context creation and render time (s): ", t / 2000.0


# 0.07263176703453064s nested sections
# 0.0699 merge
# 0.066979 no recursion
# 0.15766 with pcre (sometimes 0.1618221524953842)
# 0.135369 with tokenizer
# 0.02034837448596954 w/ tokenizer on release
