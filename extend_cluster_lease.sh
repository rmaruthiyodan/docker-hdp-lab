#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Script to extend the lease time for Clusters

__validate_clustername() {
        $DOCKER_PS_CMD | grep -q "\/$clustername-"
        if [ $? -ne 0 ]
        then
                echo -e "\n\tNo Running cluster exists with the name: $clustername. Check the given <username-clustername> and try again \n"
		__usage
                exit
        fi
}

__extend_lease() {
	current_expiry=`grep $clustername $CLUSTER_LIFETIME_FILE| awk '{print $NF}'`
	new_expiry=$(($current_expiry + $hrs_to_extend * 3600))
	echo -e "\n\tNew Lease for the cluster \"$clustername\" is till: `date -d "@$new_expiry" +"%Y-%m-%d %H:%M"`"
}

__usage() {
	echo -e "Usage:: extend_cluster_lease.sh <username-clustername> [ Hours ]\n"
	exit 1
}

## Main
#set -x
if [ $# -lt 1 ]
then
	echo -e "\n\tInsufficient argument"
	__usage
fi

source /etc/docker-hdp-lab.conf
DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
CLUSTER_LIFETIME_FILE=/opt/docker_cluster/cluster_lease
clustername=$1

__validate_clustername $clustername

if [ ! -z $2 ]
then
	echo $2 | egrep -q -v "[0-9]"
	if [ "$?" -eq 0 ] || [ "$2" -gt 24 ]
	then
		echo -e "\n\tInvalid 2nd Argument. No. of Hours can only be integer number and max 24hrs"
		__usage
		exit 1
	fi
	hrs_to_extend=$2
else
	hrs_to_extend=2
fi

__extend_lease

	
