#!/bin/bash
########
# Author: Shubhangi Pardeshi
# Project: Docker HDP Lab
# Description: Delete cluster node 
########

source /etc/docker-hdp-lab.conf
NodeInfo=""

if [ $# -ne 1 ] ;then
 echo "Incorrect Arguments"
 echo "Usage:: delete_clusterNode.sh <username-clustername-nodename>"
 echo "Example:: delete_clusterNode.sh shubhangi-sample11-n17"
 exit
else
 NodeInfo=$1
 out=`echo $NodeInfo | awk -F'-' '{print NF}'`
 if [ $out -lt 3 ]
 then
 	echo "Incorrect Arguments"
 	echo "Usage:: delete_clusternode.sh <username-clustername-nodename>"
 	echo "Example:: delete_clusterNode.sh shubhangi-sample11-n17"
 	exit
 fi
fi

if [ ! "$(docker -H $SWARM_MANAGER:4000 ps -a | grep $NodeInfo | awk -F "/" '{print $NF}')" ]
then
  echo -e "\nThere is no Instnace in Running or Stopped state that matches the given string..."
  exit
fi

#ClusterName=$(echo $NodeInfo | awk -F"-" '{print $1"-"$2}')
#echo $ClusterName
stop_clusterNode $NodeInfo


if [  "$?" -ne 0 ]
then	
	echo "Exiting with error: Could not stop cluster Node" 
	exit
fi

echo -e " \n----------------------------------------------------------------------------\n\t ****** WARNING !!! ****** \n "
echo -e "The following instance will be DELETED : \n"
echo -e "\t" $NodeInfo
echo -e "\n\t"
read -p "Are you sure ? [Y/N] : " choice
if [ "$choice" == "Y" ] || [ "$choice" == "y" ]
then
	docker -H $SWARM_MANAGER:4000 rm $(docker -H $SWARM_MANAGER:4000 ps -a | grep $NodeInfo | awk -F "/" '{print $NF}')
fi
