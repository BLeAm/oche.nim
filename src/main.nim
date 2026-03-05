import oche
import std/options
import os

type
  UserRole {.oche.} = enum
    Admin, Editor, Viewer

  User {.oche.} = object
    id: int
    role: UserRole

proc greet(name: string): string {.oche.} =
  if name == "": raise newException(ValueError, "ชื่อห้ามว่าง!")
  "Hello, " & name

proc checkAccess(user: User): string {.oche.} =
  case user.role
  of Admin: "Full access granted"
  of Editor: "Can update content"
  of Viewer: "Read only"

proc slowCompute(n: int): int {.oche.} =
  os.sleep(1000)
  n * n

# --- Optional Support Test ---
proc getScore(name: string): Option[float] {.oche.} =
  if name == "Bleamz": some(99.9)
  else: none(float)

proc findUserId(name: string): Option[int] {.oche.} =
  if name == "Admin": some(1)
  else: none(int)

generate("nlib.dart")
