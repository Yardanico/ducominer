import std / [
    net, httpclient,
    json,
    strutils, strformat, strscans,
    threadpool, atomics,
    os, times
]

when defined(nimcrypto):
    import nimcrypto/sha
else:
    import hashlib/rhash/sha1

var 
    startTime: Time
    acceptedCnt, rejectedCnt, hashesCnt: Atomic[int]

proc recvAll(s: Socket): string = 
    result = s.recv(1, timeout = 15000)
    while s.hasDataBuffered():
        result &= s.recv(1, timeout = 15000)

proc mine(username: string, pool_ip: string, pool_port: Port, difficulty: string, miner_name: string) {.thread.} =
    ## Main mining function
    # Disable socket buffering so that we can do s.recv(1048)
    var soc = newSocket()
    soc.connect(pool_ip, pool_port)
    # Receive and discard the server version
    let serverVer = soc.recvAll()

    echo fmt"Thread #{getThreadId()} connected to {pool_ip}:{pool_port}"

    var sharecount = 0
    # An infinite loop of requesting and solving jobs
    while true:
        # Checking if the difficulty is set to "NORMAL" and sending a job request to the server
        if difficulty == "NORMAL": 
            soc.send(fmt"JOB,{username}")
        else:
            soc.send(fmt"JOB,{username},{difficulty}")
        
        let job = soc.recvAll()

        var 
            prefix, target: string
            diff: int
        # Parse the job from the server
        if not scanf(job, "$+,$+,$i", prefix, target, diff):
            quit("Error: couldn't parse job from the server!")

        when defined(nimcrypto):
            var ctx: sha1
            ctx.init()
            ctx.update(prefix)

        # A loop for solving the job
        for res in 0 .. 100 * diff:
            let data = $res
            # Checking if the hashes of the job matches our hash
            atomicInc hashesCnt

            when defined(nimcrypto):
                var ctxCopy = ctx
                ctxCopy.update(data)

            let isGood = when defined(nimcrypto):
                $ctxCopy.finish() == target
            else:
                $count[RHASH_SHA1](prefix & data) == target

            if isGood:
                # Send the share to the server
                soc.send(fmt"{data},,{miner_name}")

                let feedback = soc.recvAll()
                if feedback == "GOOD":
                    atomicInc acceptedCnt
                elif feedback == "BAD":
                    atomicInc rejectedCnt
                
                inc sharecount
                # Break from the loop because the job was solved
                break

proc monitorThread() {.thread.} = 
    startTime = getTime()
    while true:
        sleep(2000)
        let mils = (getTime() - startTime).inMilliseconds.float

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

        hashesCnt.store(0)
        acceptedCnt.store(0)
        rejectedCnt.store(0)

var config: JsonNode
if paramCount() < 1:
    try:
        echo "Config file location not specified, using default location [./config.json]"
        config = parseFile("./config.json")
    except:
        echo "Config not found at default location. Please specify the config file location."
        echo ""
        echo fmt"Usage: {paramStr(0)} <config file>"
        echo "You can find an example config file at https://github.com/its5Q/ducominer/config.example.json"
        quit(1)
else:
    config = parseFile(paramStr(1))

let client = newHttpClient()
var pool_addr = client.getContent(config["ip_url"].getStr()).splitLines()
var (pool_ip, pool_port) = (pool_addr[0], Port(parseInt(pool_addr[1])))

var username = config["username"].getStr(default = "5Q")
var difficulty = config["difficulty"].getStr(default = "NORMAL")  
var miner_name = config["miner_name"].getStr(default = "DUCOMiner-Nim")
var thread_count = config["thread_count"].getInt(default = 16)

for i in 0 ..< thread_count:  # A loop that spawns new threads executing the mine() function
    spawn mine(username, pool_ip, pool_port, difficulty, miner_name)
spawn monitorThread()

# Wait for threads to complete (actually waits for Ctrl+C or an exception)
sync()