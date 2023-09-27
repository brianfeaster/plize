#!/bin/bash

function parallelize () {
    set +e
    local NORM=$'\e[0m'
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

    declare -A tasks=()
    declare -A taskStates=()
    graph0=("*")
    readTasksAndGraph

    local cpuMax=2
    scheduler

    prettyPrintEverything
    #for n in ${!graph*}; do eval def $n; done
}

########################################

function readTasksAndGraph () {
    local key value sexpr tokens
    while read -r key value
    do case $key in
        ("") ;;
        (=) sexpr=$value ;;
        (*) 
            tasks[$key]=$value
            taskStates[$key]=ready ;;
    esac done
    sexpr2tokens
    tokens2graph 0 <<<$tokens
}

function sexpr2tokens () {
    local IFS=
    while read -r -n 1 c
    do
        case $c in
            ("("|")") tokens+=$'\n'$c$'\n' ;;
            (" "|$'\t') tokens+=$'\n';;
            (*) tokens+=$c ;;
        esac
    done <<<$sexpr
}

function tokens2graph () {
    declare -n p=graph$1
    while read -r c
    do
      case $c in
        ('(')
            (( p[${#p[*]}] = $1 + 1 ))
            tokens2graph $(($1+1));;
        (')') return ;;
        ("") ;;
        (*) p[${#p[*]}]=$c ;;
      esac
    done
}

########################################

function scheduler () {
    declare -A pid2task=()

    while ((${#pid2task[*]} < cpuMax))
    do
        spawnNextFree 0
    done

    while waitForATask
    do
        spawnNextFree 0
    done

}

function spawnNextFree () {
    local taskCmd
    if [ "${1//[0-9]}" == "" ]
    then
        declare -n p=graph$1
        local taskId

        case $p in
            ("*")
                for taskId in ${p[@]:1}
                do
                  spawnNextFree "$taskId" && return $?
                done
                ;;
            ("+")
                for taskId in ${p[@]:1}
                do
                    spawnNextFree "$taskId"
                    case $? in
                        (0|1|3) return $? ;;
                        (2) ;;
                    esac
                done
                ;;
            (*) printf "[${IRED}FATAL EXCEPTION:  Unknown graph dependency '$p']"; exit 254 ;;
        esac

    else
        case ${taskStates[$1]} in
            (ready)
                taskStates[$1]=running
                taskCmd="${tasks[$1]}"
                spawnTask
                return 0
                ;;
            (running) return 1 ;;
            (finished) return 2 ;;
            (failed|*) return 3 ;;
        esac
    fi
}

function spawnTask () {
    ( eval  "echo $BASHPID; echo $BASHPID 1>&2; $taskCmd" )\
      2> >(read -r pid; while read -r l; do echo "$RED[$pid]$NORM $l"; done) \
      1> >(read -r pid; while read -r l; do echo "$GREEN[$pid]$NORM $l"; done) \
      &
    pid2task[$!]=$taskId
    echo "$IMAGENTA[Spawned $!:$taskId]$NORM $taskCmd"
    return 0
}

function waitForATask () {
    (( !${#pid2task[@]} )) && return 255

    echo -n "$IMAGENTA[Waiting on ${#pid2task[@]} tasks]$NORM ${!pid2task[@]} "
    prettyPrintGraph 0; echo

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
        reportTaskCompleted
    fi
}

########################################

function prettyPrintEverything () {
    echo -e "\n${WHITE}--TASKS--------$NORM"
    for k in $(sort <(tr \  \\n <<<${!tasks[@]}))
    do
        echo " $GREEN$k $YELLOW${taskStates[$k]} $NORM${tasks[$k]}"
    done
    echo -e "${WHITE}GRAPH$NORM"
    printf " "
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
            (*)       printf "$1" ;;
        esac
    fi
}

function reportTaskFail () {
    echo "$IRED[Exception pid $pid:$taskId returned $ret]$NORM $taskCmd"
}

function reportTaskCompleted () {
    echo "$IGREEN[Completed pid $pid:$taskId]$NORM $taskCmd"
}