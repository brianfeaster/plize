#!/bin/bash
. plize.bash
set -e

fun2 () { sleep 2; printf "fun2\ndone\n";      sleep 0; return 0; }
fun3 () { sleep 3; printf "fun3\ndone\n" 1>&2; sleep 0; return 0; }
fun4 () { sleep 4; printf "fun4\ndone\n";      sleep 0; return -88; }
funx () { sleep $1; printf "funx$1\ndone\n";   sleep 1; return 0; }

## create non-related processes
#fun () { sleep 10; echo slow; exit 4; }
#fun & fun & fun & fun & fun &

parallelize fun4 fun3 "funx 5" fun2 "funx 3"

echo DONE.
