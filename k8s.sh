#!/usr/bin/env bash

. ./config.properties
. ./k8s-common.sh

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] This script must be run as root!" && exit 1

k8s(){
    chmod +x ./k8s-master.sh
    chmod +x ./k8s-worknode.sh

    if [[ $# > 0 ]]; then
        if [ "$1" == "worknode" ]; then
            echo "k8s-worknode.sh executing.."

            . ./k8s-worknode.sh
            return 0
        else
            echo "cnt: $#,"
            return 1
        fi
    fi

#    verify_inet
#    local ret=$?

#    if [ $ret -eq 2 ];then
#        echo ""
#        echo -e "[${red}Error${plain}] verify_inet failed,current IP doesn not match with config file."
#        return 1
#    fi


    echo "k8s-master.sh executing.."
    . ./k8s-master.sh


    return 0

    if [ $ret -eq 0 ]; then
        echo "k8s-master.sh executing.."
        . ./k8s-master.sh

        return 0
    fi

    if [ $ret  -eq 1 ]; then
        echo "k8s-worknode.sh executing.."
        . ./k8s-worknode.sh
    fi

}

if [[ $# > 0 ]]; then
    k8s $*
else
    k8s
fi