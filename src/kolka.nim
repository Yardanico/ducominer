import std / [
  math, random, algorithm, 
  httpclient, json, strformat
]

randomize()

proc calc(shareTime, rand, diff: int): float = 
  var shareTime = float(shareTime + 60) # emulate ping
  let stSquared = shareTime * shareTime

  if shareTime < 2500:
    result = stSquared / 5_000_000_000'f
  else:
    result = round(stSquared / shareTime) / 5_000_000_000'f

type
  MaxBlock = tuple[diff: int, rand: int, required: int, spent: int, res: float]
  MaxBalance = tuple[offset: int, totalTime: float, totalSum: float]

const
  MaxTime = 1000 * 60 * 60 * 3

proc doIter(startBlockCnt: int): MaxBalance = 
  var blockCnt = startBlockCnt
  result.totalTime = 0.1

  for offset in 1500 .. 2000:
    var 
      maxData: MaxBlock
      totalTime: int
      totalSum: float

    while totalTime < MaxTime:
      let diff = int(ceil(blockCnt.float / 2000.float))
      let rand = rand(1 .. 100 * diff)
      var shareTimeRequired = int(rand / 7500)

      #let shareTimeSpent = rand(shareTimeRequired + 50 .. shareTimeRequired + 2500)
      let shareTimeSpent = shareTimeRequired + offset
      totalTime += shareTimeSpent

      let res = calc(shareTimeSpent, rand, diff)
      totalSum += res

      if maxData.res < res:
        maxData = (diff, rand, shareTimeRequired, shareTimeSpent, res)
      
      inc blockCnt 

    let totalTimeF = totalTime / 1000
    
    if (result.totalSum / result.totalTime) < (totalSum / totalTimeF):
      result = (offset, totalTimeF, totalSum)


proc getBestOffset*(): int = 
  let c = newHttpClient()
  let j = parseJson(c.getContent("https://raw.githubusercontent.com/revoxhere/duco-statistics/master/api.json"))
  let startBlockCnt = j["Mined blocks"].getInt()
  c.close()
  #echo "Got starting block count: ", startBlockCnt

  var data: seq[MaxBalance]
  for i in 0 ..< 25:
    #echo "Iteration " & $i
    data.add doIter(startBlockCnt)
  
  proc mycmp(x, y: MaxBalance): int = 
    cmp(x.totalSum, y.totalSum)
  
  data.sort(mycmp, order = Descending)
  let best = data[0]
  #echo fmt"Best offset: {best.offset}, time spent: {best.totalTime / 60} minutes, balance: {best.totalSum}"
  result = best.offset