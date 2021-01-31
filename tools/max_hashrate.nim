import std / [httpclient, json, tables, algorithm, strutils]


let c = newHttpClient()
let data = parseJson(c.getContent("https://raw.githubusercontent.com/revoxhere/duco-statistics/master/api.json"))

proc getHs(hs: float): string = 
  # Calculate amount of hashes per second
  let hashesSec = hs
  let khsec = hashesSec / 1000
  let mhsec = khsec / 1000
  if mhsec >= 1:
    mhsec.formatFloat(ffDecimal, 2) & " MH/s"
  elif khsec >= 1:
    khsec.formatFloat(ffDecimal, 2) & " KH/s"
  else:
    hashesSec.formatFloat(ffDecimal, 2) & " H/s"

var 
  maxUsername = ""
  maxHashrate = 0.0

var res = initOrderedTable[string, float]()

for id, miner in data["Miners"]:
  let name = miner["User"].getStr()
  let hs = miner["Hashrate"].getFloat()

  if name in res:
    res[name] += hs
  else:
    res[name] = hs

proc mycmp(a, b: (string, float)): int = cmp(a[1], b[1])

res.sort(mycmp, order = Descending)

for name, hs in res:
  echo "User ", name, " - ", getHs(hs)