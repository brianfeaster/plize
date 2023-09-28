#!/bin/bash

function parallelize () {
    local -
    set +e +m -f

    local NORM=$'\e[m'
    local RED=$'\e[0;31m'
    local GREEN=$'\e[0;32m'
    local YELLOW=$'\e[0;33m'
    local CYAN=$'\e[0;36m'
    local IRED=$'\e[1;31m'
    local IGREEN=$'\e[1;32m'
    local IBLUE=$'\e[1;34m'
    local ICYAN=$'\e[1;36m'
    local IMAGENTA=$'\e[1;35m'
    local WHITE=$'\e[1;37m'

    local help=0
    local dryrun=0
    local quiet=0
    local debug=0
    local cpus=3
    parseCommandArgs "$*"

    ((help)) && { help; return; }

    declare -A tasks=()
    declare -A taskStates=()
    local dependencytree=("* ")
    readTasksAndGraph || throwDependencyGraph

    ((debug)) && prettyPrintEverything
    #printGraph

    if ((!dryrun))
    then
        scheduler
        ((debug)) && prettyPrintEverything
    fi
    return 0
}

########################################

function parseCommandArgs () {
    [[ $* =~ -h ]] && help=1
    [[ $* =~ -d ]] && dryrun=1
    [[ $* =~ -q ]] && quiet=1
    [[ $* =~ -v ]] && debug=1
    [[ $* =~ -vv ]] && debug=2
    [[ $* =~ -c\ *([0-9]+) ]] && cpus=BASH_REMATCH[1]
}

function help () {
    cat <<BLOCK

NAME
  Parallelize

USAGE
  parallelize [-h] [-c CPUs] [-d] [-q] [-v | -vv]

  Reads Tasks and Dependency Specification (see below) via STDIN

OPTIONS
  -h  Help/manual
  -c  CPU/threads/process limit
  -d  Dry run
  -q  Quiet prefixed task info for all job output
  -v  Verbose runtime details
  -vv Verbose plus dependency tree details

TASKS AND DEPENDENCYIES FILE:

  The specifcation file contains multiple lines of task definitions and
  dependency definitions.  See below for details.

  Examples:

task1 echo hello world
task2 git clone stuff; sleep && date
task3 cargo build | cat -n
= (* task1 (+ task2 task3))

aa echo hello
bb echo world
= (+ aa bb)
cc echo done
= (* aa cc)


TASK DEFINITION SYNTAX:

    taskId bash-expression

  A task definition consists of a unique task ID followed by a bash expression.
  The bash-expression must be one line with no line breaks.  It may be
  a compound expression IE with semicolons, pipes, etc.

  The task IDs are used in the dependency tree definitions.


DEPENDENCY DEFINITION SYNTAX:

    = sexpr

  A parenthesized prefix-style LISP expression (prefixed by a "=") containing
  task Ids (specified via task definitions) and the following "operators":

    *  parallel scheduled operator
    +  sequenced scheduled operator

  Example (Assume 6 existing tasks labeled A through F):

    = (* A (+ B (* C D) A E) F)

  The following will run A and F in parallel along with the middle group
  (+ B (* C D) E A).  The middle group runs sequentally B followed by (* C D),
  where C and D run in parallel, and finally E with A already having run.

  TaskIDs can be used more than once in the tree but will only run one.

  Mutliple dependency definitions are considered parallel tasks. IE

    = (+ a b)
    = c

  is equivalent to

    = (* (+ a b) c)


COMMAND LINE EXAMPLES

echo -e "a echo hello\nb echo world\n= (* a b)" | parallelize

parallelize <<<'
a echo hello
b echo world
= a
= b
'

cat >spec <<HEREDOC
= (+ c (* a b))
a echo hello
b echo world
c echo ok
HEREDOC
parallelize -c 8 -vv <spec

BLOCK
}

function readTasksAndGraph () {
    declare -A graphTasks
    local key value sexpr="" tokens
    while read -r key value
    do case $key in
        ("") ;;
        (=) sexpr+=" $value" ;;
        (*) tasks[$key]=$value
            taskStates[$key]=ready
            ;;
        esac done
    sexpr2tokens <<<$sexpr
    tokens2graph 0 <<<$tokens
    (( ${#graphTasks[*]}-2 == ${#tasks[*]}))
}

function sexpr2tokens () {
    local c IFS=
    while read -r -n 1 c
    do case $c in
        ("("|")") tokens+=$'\n'$c$'\n' ;;
        (" "|$'\t') tokens+=$'\n';;
        (*) tokens+=$c ;;
    esac done
}

function tokens2graph () {
    local task depth=$1
    while read -r task
    do
      case $task in
        ('(')
            dependencytree[depth]+="$((1+depth)) "
            tokens2graph $((depth+1))
            ;;
        (')') return ;;
        ("") ;;
        (*) graphTasks[$task]=1
            dependencytree[depth]+="$task "
            ;;
      esac
    done
}

########################################

function scheduler () {
    local pid2task=()
    while ((${#pid2task[*]} < cpus)) && spawnNextFree 0; do :; done
    while waitForATask
    do
        spawnNextFree 0
    done
}

function spawnNextFree () {
    if [ "${1//[0-9]}" == "" ]
    then
        local depth=$1 taskId allFinished=1
        case ${dependencytree[depth]%% *} in
        ("*")
            for taskId in ${dependencytree[depth]#* }
            do
              spawnNextFree $taskId
                case $? in
                    (0) return 0 ;;
                    (2) ;;
                    (*) allFinished=0 ;;
                esac
            done
            return $((allFinished ? 2 : 1))
            ;;
        ("+")
            for taskId in ${dependencytree[depth]#* }
            do
                spawnNextFree $taskId
                case $? in
                    (2) ;;
                    (*) return $? ;;
                esac
            done
            return 2
            ;;
        (*)
            printf "$IRED[EXCEPTION unknown dependency op '$p'] $NORM"
            prettyPrintGraph
            exit 3 ;;
        esac

    else
        local taskId=$1
        case ${taskStates[$taskId]} in
            (ready) spawnTask; return 0 ;;
            (running) return 1 ;;
            (finished) return 2 ;;
            (failed|*) return 3 ;;
        esac
    fi
}

function spawnTask () {
    local taskCmd="${tasks[$taskId]}"
    if ((quiet))
    then
        eval "$taskCmd" &
    else
        ( eval "echo $BASHPID; echo $BASHPID 1>&2; $taskCmd" )\
          2> >(read -r pid; while read -r l; do echo "$RED[$pid:$taskId]$NORM $l"; done) \
          1> >(read -r pid; while read -r l; do echo "$GREEN[$pid:$taskId]$NORM $l"; done) \
        &
    fi
    pid2task[$!]=$taskId
    taskStates[$taskId]=running
    ((debug)) && echo "$IMAGENTA[Spawned $!:$taskId]$NORM $taskCmd"
    return 0
}

function waitForATask () {
    local pid ret taskId taskCmd
    ((${#pid2task[@]})) || return 255

    ((debug)) && echo $(
        echo -n "$IMAGENTA[Waiting on ${#pid2task[@]} tasks]$NORM ${!pid2task[@]} "
        ((2 <= debug)) && prettyPrintGraph
    )

    wait -p pid -n ${!pid2task[@]}

    ret=$?
    taskId=${pid2task[$pid]}
    taskCmd=${tasks[$taskId]}

    unset pid2task[$pid]
    if ((ret))
    then
        taskStates[$taskId]=failed
        reportTaskFail
        return $ret
    else
        taskStates[$taskId]=finished
        ((debug)) && reportTaskCompleted
        return 0
    fi
}

########################################

function prettyPrintEverything () {
    echo -e "${WHITE}--TASKS--------$NORM"
    for k in $(sort <(tr \  \\n <<<${!tasks[@]}))
    do
        echo " $GREEN$k $YELLOW${taskStates[$k]} $NORM${tasks[$k]}"
    done
    echo -ne "${WHITE}GRAPH$NORM\n "
    prettyPrintGraph
}

function prettyPrintGraph () {
    local buff=$(_prettyPrintGraph 0)
    echo $buff
}

function _prettyPrintGraph () {
    if [ "${1//[0-9]}" == "" ]
    then
        local a w="("
        for a in ${dependencytree[$1]}
        do
            printf "$w"
            _prettyPrintGraph $a
            w=" "
        done
        printf ")"
    else
        case ${taskStates[$1]} in
            (ready) printf "$1" ;;
            (running) printf "$IGREEN$1$NORM" ;;
            (finished) printf "$IBLUE$1$NORM" ;;
            (failed) printf "$IRED$1$NORM" ;;
            (*) printf "$1" ;;
        esac
    fi
}

function printGraph () {
    for i in "${!dependencytree[@]}"
    do
        echo dependencytree[$i]=\"${dependencytree[i]}\"
    done
}

function reportTaskFail () {
    echo "$IRED[Exception pid $pid:$taskId returned $ret]$NORM $taskCmd"
}

function reportTaskCompleted () {
    echo $(
      echo -n "$IGREEN[Completed $pid:$taskId]$NORM $taskCmd "
      ((2 <= debug)) && prettyPrintGraph
    )
}

function throwDependencyGraph () {
    printf "$IRED[EXCEPTION dependency tree missing one or more tasks]$NORM"
    prettyPrintEverything
    exit 2
}