import oche

type
  User {.oche.} = object 
    id: int
    name: string 

proc initUser(id: int, name: string): User {.oche.} = 
  result.id = id 
  result.name = toOcheStr(name)

proc pname(u: User) {.oche.} =
  echo u.name

generate("ntoc1.dart")
# generatePython("ntoc1.py")