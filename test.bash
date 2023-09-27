#!/bin/bash
. plize.bash
set -e

fun2 () { sleep 2; printf "fun2\ndone\n";      sleep 0; return 0; }
fun3 () { sleep 3; printf "fun3\ndone\n" 1>&2; sleep 0; return 0; }
fun4 () { sleep 4; printf "fun4\ndone\n";      sleep 0; return $((RANDOM%4)); }
funx () { sleep $1; printf "funx$1\ndone\n";   sleep 1; return 0; }
export -f fun2 fun3 fun4


## create non-related processes
#fun () { sleep 10; echo slow; exit 4; }
#fun & fun & fun & fun & fun &

#parallelize fun4 3 fun3 1m "funx 5" 3 1m fun2 "funx 3" 'timeout 4 bash -c fun3'

<<REM
parallelize <<<'a echo hi
= a'
REM

parallelize <<<'
a sleep 1; echo a
aa sleep 2; echo aa 1>&2
b sleep 3; echo b
c2 sleep 4; echo c2; exit 0
d sleep 5; echo d
e_ sleep 6; echo _e
= a (+ (* aa(+ b c2)d) e_) a
'
echo DONE.
