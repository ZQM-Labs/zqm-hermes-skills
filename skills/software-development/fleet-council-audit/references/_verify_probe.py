# verify-only probe (not persisted)
import os
p=r"C:\Users\zqmco\AppData\Local\hermes\skills\software-development\fleet-council-audit\references\redis-version-lifecycle.md"
t=open(p,encoding="utf-8").read()
print("VERSION AGE section present:", "VERSION AGE ≠ INSTALL AGE" in t)
print("INSTALLER ATTRIBUTION section present:", "INSTALLER ATTRIBUTION" in t)
print("redis-msi fingerprint present:", "redis-msi" in t)
print("bytes:", len(t))
