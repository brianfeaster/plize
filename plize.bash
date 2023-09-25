#!/bin/bash

function parallelize () {
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
}

function spawnTasks () {
    local cmd
    for cmd in "${commands[@]}"
    do
        spawnCmd
    done
    return 0
}


function spawnCmd () {
    ( eval  "echo $BASHPID; echo $BASHPID 1>&2; $cmd" )\
        2> >(read -r pid; while read -r l; do echo "$RED[$pid]$NORM $l"; done) \
        1> >(read -r pid; while read -r l; do echo "$GREEN[$pid]$NORM $l"; done) \
        &
    pid=$!
    pid2cmd[$pid]=$cmd
    echo "$IMAGENTA[Spawned pid $!]$NORM $cmd"
    return 0
}

function waitForAllTasks () {
    local count=$((1+${#commands[@]})) pid ret cmd
    while ((--count))
    do
        echo "$IMAGENTA[Waiting on $count tasks]$NORM"
        wait -p pid -n ${!pid2cmd[@]} 2>/dev/null
        ret=$?
        cmd=${pid2cmd[$pid]}
        if ((ret))
        then
            reportTaskFail

            ## Respawn if failed
            #echo "$IMAGENTA[Re-spawning $pid]$NORM $cmd"
            #unset pid2cmd[pid]
            #spawnCmd
            #((++count))

            return $ret
        else
            reportTaskCompleted
        fi
    done
    return 0
}

function reportTaskFail () {
    echo "$IRED[Exception pid $pid returned $ret]$NORM $cmd"
}

function reportTaskCompleted () {
    echo "$IGREEN[Completed pid $pid]$NORM $cmd"
}