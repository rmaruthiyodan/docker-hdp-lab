#!/bin/bash
########
# Author: Shubhangi Pardeshi
# Project: Docker HDP Lab
# Description: This script helps to stop single node from cluster
########

source /etc/docker-hdp-lab.conf

NodeInfo=""
if [ $# -ne 1 ] ;then
 echo "Incorrect Arguments"
 echo "Usage:: stop_clusterNode.sh <username-clustername-nodename>"
 echo "Example:: stop_clusterNode.sh shubhangi-sample11-n10"
 exit 1
else
 NodeInfo=$1
 out=`echo $NodeInfo | awk -F'-' '{print NF}'`
 if [ $out -lt 3 ]
 then
        echo "Incorrect Arguments"
        echo "Usage:: stop_clusterNode.sh <username-clustername-nodename>"
        echo "Example:: stop_clusterNode.sh shubhangi-sample11-n10"
        exit
 fi
fi


if [ ! "$(docker -H $SWARM_MANAGER:4000 ps | grep $NodeInfo | awk -F "/" '{print $NF}')" ]
then
  echo -e "\nThere is no Running Instnace that matches the given string..."
  exit 0 
fi

echo -e "\nThe following instance will be stopped :"
echo -e "\t" $NodeInfo
echo -e "\n\t"

read -p "Are you sure to stop ? [Y/N] : " choice
echo "---------------------------------------------------"
if [ "$choice" == "Y" ] || [ "$choice" == "y" ]
then
	docker -H $SWARM_MANAGER:4000 kill $(docker -H $SWARM_MANAGER:4000 ps | grep $NodeInfo | awk -F "/" '{print $NF}')
else
	exit 1
fi

