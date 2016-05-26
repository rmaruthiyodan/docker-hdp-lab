#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Ad-hoc script - The script starts all the cluster nodes that are offline
########

__start_cluster() {
	echo $USERNAME
	for cluster_name in $($DOCKER_PS_CMD| grep "\/$USERNAME-" | awk -F "/" '{print $NF}' | cut -f 2 -d"-" | sort | uniq)
	do
		mod_start_cluster $USERNAME-$cluster_name
		docker -H $SWARM_MANAGER:4000 kill $(docker -H $SWARM_MANAGER:4000 ps | grep $USERNAME-$cluster_name | awk -F "/" '{print $NF}')
	done
}


if [ $# -lt 1 ];then
 echo "Usage:: all_node_start  all | username"
 echo "Displaying cluster for the current user " $USER
 USERNAME=$USER
else
 USERNAME=$1
fi

source /etc/docker-hdp-lab.conf

DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
	

if [ "$USERNAME" == "all" ]; then
	#DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
 	all_users=$($DOCKER_PS_CMD | grep ambari | awk '{print $NF}' | cut -f 1 -d "-" | cut -f 2 -d "/"| sort | uniq)
	num_of_users=$(echo $all_users | wc -w)

	for i in $all_users; do
		USERNAME=$i
		__start_cluster
	done
	exit
fi


