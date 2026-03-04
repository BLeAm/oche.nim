import oche

proc add(a, b:int):int {.oche.} = 
  a + b

proc mul(a, b:int):int {.oche.} = 
  a * b

proc tdiv(a, b, c:int):int {.oche.} = 
  a div b

generate("nlib.dart")
