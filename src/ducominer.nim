import std / [
  net,
  strutils, strformat, strscans,
  threadpool, atomics,
  os, times
]

import nimcrypto/sha

import kolka

const
  Username = "kalaros"
  MinerName = "test"
  Difficulty = "NORMAL"
  ThreadCount = 40

  PoolIp = "51.15.127.80"
  PoolPort = Port(2811)

  MonitorMs = 15000

  DoFakeSleep = true

var 
  startTime: Time
  acceptedCnt, rejectedCnt, hashesCnt: Atomic[int]
  sleepOffset: Atomic[int]

sleepOffset.store(1800)

proc recvAll(s: Socket): string = 
  result = s.recv(1, timeout = 15000)
  while s.hasDataBuffered():
    result &= s.recv(1, timeout = 15000)

proc minerThread() {.thread.} =
  ## Main mining function
  # Disable socket buffering so that we can do s.recv(1048)
  var soc = newSocket()
  soc.connect(PoolIp, PoolPort)
  # Receive and discard the server version
  let serverVer = soc.recvAll()

  #echo fmt"Thread #{getThreadId()} connected to {PoolIp}:{PoolPort}"
  # An infinite loop of requesting and solving jobs
  while true:
    # Checking if the difficulty is set to "NORMAL" and sending a job request to the server
    when Difficulty == "NORMAL": 
      soc.send(fmt"JOB,{Username}")
    else:
      soc.send(fmt"JOB,{Username},{difficulty}")
    
    let job = soc.recvAll()
    let start = getTime()
    
    var 
      prefix, target: string
      diff: int
    # Parse the job from the server
    if not scanf(job, "$+,$+,$i", prefix, target, diff):
      quit("Error: couldn't parse job from the server!")

    # Initialize the sha1 context and add prefix
    var ctx: sha1
    ctx.init()
    ctx.update(prefix)
    
    # A loop for solving the job
    for res in 0 .. 100 * diff:
      let data = $res
      # Checking if the hashes of the job matches our hash
      atomicInc hashesCnt
      # Copy the initialized context and add the value
      var ctxCopy = ctx
      ctxCopy.update(data)

      # The result is correct
      if $ctxCopy.finish() == target:
        # Calculate the amount of time we spent calculatign the sahre (in ms)
        let spent = (getTime() - start).inMilliseconds
        # Calculate the required amount of time:
        # If the submit a share with less amount of time spent than this value,
        # then it won't get accepted
        let shareTimeRequired = int(res / 7500)

        # Calculate the amount of time we need to sleep for:
        var sleepFor = clamp(sleepOffset.load() - spent, 0, 2500)
        # Actually sleep
        when DoFakeSleep:
          sleep(sleepFor.int)
        soc.send(fmt"{data},,{MinerName}")

        let feedback = soc.recvAll()
        if feedback == "GOOD":
          atomicInc acceptedCnt
        elif feedback == "BAD":
          atomicInc rejectedCnt
        elif feedback == "BLOCK":
          
        
        # Break from the loop because the job was solved
        break

proc monitorThread() {.thread.} = 
  startTime = getTime()
  while true:
    sleep(MonitorMs)
    # Get time diff in milliseconds
    let mils = (getTime() - startTime).inMilliseconds.float

    # Calculate amount of hashes per second
    let hashesSec = (hashesCnt.load().float / mils) * 1000
    let khsec = hashesSec / 1000
    let mhsec = khsec / 1000
    let toShow = if mhsec >= 1:
      mhsec.formatFloat(ffDecimal, 2) & " MH/s"
    elif khsec >= 1:
      khsec.formatFloat(ffDecimal, 2) & " KH/s"
    else:
      hashesSec.formatFloat(ffDecimal, 2) & " H/s"

    startTime = getTime()
    let strTime = startTime.format("HH:mm:ss")
    echo fmt"{strTime} Hash rate: {toShow}, Accepted: {acceptedCnt.load()}, Rejected: {rejectedCnt.load()}"

    # Reset the counters
    hashesCnt.store(0)
    acceptedCnt.store(0)
    rejectedCnt.store(0)

proc offsetThread {.thread.} = 
  while true:
    try:
      let oldOffset = sleepOffset.load()
      var offset = getBestOffset()
      sleepOffset.store(offset)
      echo fmt"Updated old offset {oldOffset} to {offset}"
    except:
      echo getCurrentExceptionMsg()
    # Sleep one minute
    sleep(60000)

proc main = 
  spawn offsetThread()
  sleep(2000)
  for i in 0 ..< ThreadCount:  # A loop that spawns new threads executing the mine() function
    spawn minerThread()
  spawn monitorThread()

  # Wait for threads to complete (actually waits for Ctrl+C or an exception)
  sync()

main()