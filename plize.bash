#!/bin/bash

function parallelize () (
    set +e
    local NORM=$'\e[0m'
    local RED=$'\e[0;31m'
    local GREEN=$'\e[0;32m'
    local IRED=$'\e[1;31m'
    local IGREEN=$'\e[1;32m'
    local IMAGENTA=$'\e[1;35m'

    local commands=("$@")
    declare -A pid2cmd=()

    spawnTasks
    waitForAllTasks
)

function spawnTasks () {
    local cmd
    for cmd in "${commands[@]}"
    do
        $cmd \
            2> >(while read -r l; do echo "$RED[$BASHPID]$NORM $l"; done) \
            1> >(while read -r l; do echo "$GREEN[$BASHPID]$NORM $l"; done) \
            &
        pid2cmd[$!]=$cmd
        echo "$IMAGENTA[Spawned pid $!]$NORM $cmd"
    done
    return 0
}

function waitForAllTasks () {
    local count=$((1+${#commands[@]})) pid ret cmd
    while ((--count))
    do
        echo "$IMAGENTA[Waiting on $count tasks]$NORM"
        waitForNextPid
        ret=$?
        cmd=${pid2cmd[$pid]}
        if ((ret))
        then
            reportTaskFail
            return $ret
        else
            reportTaskCompleted
        fi
    done
    return 0
}

function waitForNextPid () {
    wait -p pid -n ${!pid2cmd[@]} 2>/dev/null
}

function reportTaskFail () {
    echo "$IRED[Exception pid $pid returned $ret]$NORM $cmd"
}

function reportTaskCompleted () {
    echo "$IGREEN[Completed pid $pid]$NORM $cmd"
}