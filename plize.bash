#!/bin/bash

function parallelize () {
    local -
    set +e +m

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
    graph0=("*")
    readTasksAndGraph

    ((debug)) && prettyPrintEverything
    #printGraph

    if ((!dryrun))
    then
        scheduler
        ((debug)) && prettyPrintEverything
    fi
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
    -vv Verbose plus dependency graph details

Task and Dependency Specification

  One or more lines: taskId bashCommand
  Last line: = dependencySexper

  The bash command must be on a single line.

  Example:

task1 echo task1; sleep;
task2 cargo run | cat -n
= (* task1 (+ task2 task3))

Dependency Graph Syntax

  A prefix expression (Scheme/Lisp expressions) where:
    * runs tasks in parallel
    + runs tasks consecutively

  TaskIDs can be used more than once in the graph but will only run one.

Example

(* A (+ B (* C D) A E) F)

  The following will run A and F in parallel along with the middle group
  (+ B (* C D) E A).  The middle group runs sequentally B followed by (* C D),
  where C and D run in parallel, and finally E with A already having run.
BLOCK
}

function readTasksAndGraph () {
    local key value sexpr tokens
    while read -r key value
    do case $key in
        ("") ;;
        (=) sexpr=$value ;;
        (*) tasks[$key]=$value
            taskStates[$key]=ready
            ;;
        esac done
    sexpr2tokens <<<$sexpr
    tokens2graph 0 <<<$tokens
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
    local c token=$1
    declare -n p=graph$token
    ((token)) && p=()
    while read -r c
    do
      case $c in
        ('(') tokens2graph $(( p[${#p[*]}] = ++token )) ;;
        (')') return ;;
        ("") ;;
        (*) p[${#p[*]}]=$c ;;
      esac
    done
}

########################################

function scheduler () {
    declare -A pid2task=()

    while ((${#pid2task[*]} < cpus)) && spawnNextFree 0; do :; done

    while waitForATask
    do
        spawnNextFree 0
    done

}

function spawnNextFree () {
    local taskId=$1
    if [ "${taskId//[0-9]}" == "" ]
    then
        declare -n p=graph$taskId
        local allFinished=1
        case $p in
        ("*")
            for taskId in ${p[@]:1}
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
            for taskId in ${p[@]:1}
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
            printf "$IRED[EXCEPTION unknown graph dependency '$p'] $NORM"
            prettyPrintGraph 0
            exit 3 ;;
        esac

    else
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
    ((${#pid2task[@]})) || return 255

    ((debug)) && echo -n "$IMAGENTA[Waiting on ${#pid2task[@]} tasks]$NORM ${!pid2task[@]} "
    ((2 <= debug)) && prettyPrintGraph 0
    ((debug)) && echo

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
    echo -e "\n${WHITE}--TASKS--------$NORM"
    for k in $(sort <(tr \  \\n <<<${!tasks[@]}))
    do
        echo " $GREEN$k $YELLOW${taskStates[$k]} $NORM${tasks[$k]}"
    done
    echo -ne "${WHITE}GRAPH$NORM\n "
    prettyPrintGraph 0
    echo
}

function prettyPrintGraph () {
    if [ "${1//[0-9]}" == "" ]
    then
        declare -n p=graph$1
        local a
        printf "("
        prettyPrintGraph "$p"
        for a in ${p[@]:1}
        do
            printf " "
            prettyPrintGraph "$a"
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
    for n in ${!graph*}
    do
        declare -p $n
    done
}

function reportTaskFail () {
    echo "$IRED[Exception pid $pid:$taskId returned $ret]$NORM $taskCmd"
}

function reportTaskCompleted () {
    echo -n "$IGREEN[Completed pid $pid:$taskId]$NORM $taskCmd "
    ((2 <= debug)) && prettyPrintGraph 0
    echo
}