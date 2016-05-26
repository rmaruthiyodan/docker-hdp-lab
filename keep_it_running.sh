#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: The script is part of daily instance cleanup. This script puts the given cluster into an exception list
########


__validate_clustername() {
	$DOCKER_PS_CMD | grep -q "\/$USERNAME-$CLUSTERNAME-"
	if [ $? -ne 0 ]
	then
		echo -e "\n\tCluster doesn't exist with the name: $USERNAME_CLUSTER. Check the given <username-clustername> and try again \n"
		exit
	fi
}

if [ $# -ne 1 ]
then
	echo "Usage:: keep_it_running <username-clustername>"
	exit
fi

#set -x

USERNAME_CLUSTER=$1
USERNAME=`echo $USERNAME_CLUSTER|cut -f1 -d"-"`
CLUSTERNAME=`echo $USERNAME_CLUSTER|cut -f2 -d"-"`

source /etc/docker-hdp-lab.conf

DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"


__validate_clustername
echo $USERNAME-$CLUSTERNAME >> $CLEAN_UP_EXCEPTION_FILE
