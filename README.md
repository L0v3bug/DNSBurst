# DNSBurst

Test DNS server performance.

## Installation

- `git clone git@github.com:L0v3bug/dnsburst.git`
- `cd dnsburst`
- `perl dnsburst.pl --help`

## Usage

```
Usage: dnsburst [OPTIONS] [FILE...]
Test DNS server performance.

OPTIONS:
   -b <buffer size>
         specify the buffer size which will contain all the running 
         sockets (by default: 10)
   -d
         debug mode, write the logs to standard error output as 
         well to the system log
   -h, --help
         display this help and exit
   -i
         force the dns in iterative mode (by default it's 
         recursive)
   -j
         display the output statistics formated in json
   -m <number of requests>
         send multiple dns requests to the domain(s)
   -s <DNS server ip or name>
         use this server to resolve the domain name
   -t <timeout in seconds>
         change the resolution timeout (by default: 10)
   -v <log priority mask>
         the logs are managed by syslog sets the log priority mask (0 to 7)
         to defined which calls may be logged
   --version
         display dnsburst version
```