# DNSBurst

Test DNS server performance.

## Usage

```
Usage: dnsburst [OPTIONS] [FILE...]

Test DNS server performance.

OPTIONS:
   -b <buffer size>
         specify the buffer size which will ontain all the running
         sockets (by default: 10)

   -h, --help
         display this help and exit
   -i
         force the dns in iterative mode, (by default it's 
         recursive)
   -j
         display the output statistics formated in json
   -m <number of requests>
         send multiple dns requests to the domain(s)
   -s <DNS server ip or name>
         use this server to resolve the domain name
   -t <timeout in seconds>
         change the resolution timeout (by default: 10)
   -v
         active verbose mode
   --version
         display dnsburst version
```