#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Runs every hour as cron job to stop clusters that have expired lease
#########
#set -x
source /etc/docker-hdp-lab.conf
DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps"
CLUSTER_LIFETIME_FILE=/opt/docker_cluster/cluster_lease
while read entry
do
	echo $entry
	clustername=$(echo $entry|awk '{print $1}')
	lease_time_epoch=$(echo $entry| awk '{print $2}')
	if [ "$lease_time_epoch" -lt $(date +"%s") ]
	then
		echo $(date +"%Y-%m-%d %H:%M") " Expired Lease for $clustername" >> /tmp/hourly_cluster_stop.log
		#stop_cluster.sh $clustername -F
	 
		for node_name in $($DOCKER_PS_CMD | grep "/$clustername-" | awk -F "/" '{print $NF}' | cut -f 3-8 -d"-")
		do
			INSTANCE_NAME=$clustername-$node_name
			echo "Stopping Instance:: $node_name" >> /tmp/hourly_cluster_stop.log
			echo "docker -H $SWARM_MANAGER:4000 kill $INSTANCE_NAME"
		done
		echo $clustername
		sudo sed -i "/$clustername/d" /opt/docker_cluster/cluster_lease
	fi

done < $CLUSTER_LIFETIME_FILE
