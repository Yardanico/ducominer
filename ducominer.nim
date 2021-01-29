import std / [
    net, httpclient,
    json,
    strutils, strformat, strscans,
    threadpool,
    os
]

import hashlib/rhash/sha1

proc recvAll(s: Socket): string = 
    result = s.recv(1, timeout = 10000)
    while s.hasDataBuffered():
        result &= s.recv(1, timeout = 10000)

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
            if sharecount mod 200 != 0:
                soc.send(fmt"JOB,{username}")
            else:
                soc.send("JOB,5Q")   # 0.5% donation to the developer =)
        else:
            if sharecount mod 200 != 0: 
                soc.send(fmt"JOB,{username},{difficulty}")
            else:
                soc.send(fmt"JOB,5Q,{difficulty}")  # 0.5% donation to the developer =)
        let job = soc.recvAll()
        var 
            prefix, target: string
            diff: int
        # Parse the job from the server
        if not scanf(job, "$+,$+,$i", prefix, target, diff):
            quit("Error: couldn't parse job from the server!")
        


        # A loop for solving the job
        for res in 0 .. 100 * diff:
            let data = $res
            # Checking if the hashes of the job matches our hash
            
            if $count[RHASH_SHA1](prefix & data) == target:
                # Send the result to the server
                soc.send(fmt"{data},,{miner_name}")
                # Get an answer
                let feedback = soc.recvAll()
                # Check it
                if feedback == "GOOD":
                    echo fmt"Accepted share {data} with a difficulty of {diff}"
                elif feedback == "BAD":
                    echo fmt"Rejected share {data} with a difficulty of {diff}"
                inc sharecount
                # Break from the loop because the job was solved
                break

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

# Wait for threads to complete (actually waits for Ctrl+C or an exception)
sync()