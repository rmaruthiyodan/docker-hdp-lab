#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Used for displaying Cluster Nodes and their IPs
########

__print_cluster_info() {
	echo $USERNAME
	for cluster_name in $($DOCKER_PS_CMD| grep "\/$USERNAME\-" | awk -F "/" '{print $NF}' | cut -f 2 -d"-" | sort | uniq)
	do
		echo -e "\n\t" "$(tput setaf 1)[ $cluster_name ]$(tput sgr 0)"
		for node_name in $($DOCKER_PS_CMD | grep "$USERNAME-" | grep "\-$cluster_name-" | awk -F "/" '{print $NF}' | cut -f 3-8 -d"-")
		do
			INSTANCE_NAME=$USERNAME-$cluster_name-$node_name
			if [  $(docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME) = "false" ]; then 
			  IP="(OFFLINE)"
			  FQDN=$node_name
			else	
			  IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	        	  HOST_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $INSTANCE_NAME`
		          DOMAIN_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $INSTANCE_NAME`
			  FQDN=$HOST_NAME.$DOMAIN_NAME
			  #IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect INSTANCE_NAME | grep -i  "ipaddress" | grep 10 | xargs)
			fi
 			echo -e "\t \t $(tput setaf 2) $FQDN  --> \t $IP $(tput sgr 0)"
		done	  
	done
}


if [ $# -lt 1 ];then
 echo "Usage:: show_cluster.sh < all | username > [online]"
 echo "Displaying cluster for the current user " $USER
 USERNAME=$USER
else
 USERNAME=$1
fi

source /etc/docker-hdp-lab.conf

if [ "$2" == "online" ]
then
	DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps"
else
	DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
fi
	

if [ "$USERNAME" == "all" ]; then
	echo "Listing nodes from all clusters ..."
	#DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
 	all_users=$($DOCKER_PS_CMD | grep ambari | awk '{print $NF}' | cut -f 1 -d "-" | cut -f 2 -d "/"| sort | uniq)
	num_of_users=$(echo $all_users | wc -w)

	for i in $all_users; do
		USERNAME=$i
		__print_cluster_info
	done
	exit
fi

# If the show_cluster is run for a specific user:
__print_cluster_info

