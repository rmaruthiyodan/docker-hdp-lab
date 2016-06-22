#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: If the Cluster will never be used again, better kill it. That will free up some disk space
########

source /etc/docker-hdp-lab.conf

if [ $# -ne 1 ] ;then
 echo "Incorrect Arguments"
 echo "Usage:: delete_cluster.sh <username-clustername>"
 exit
fi

if [ ! "$(docker -H $SWARM_MANAGER:4000 ps -a | grep $1 | awk -F "/" '{print $NF}')" ]
then
  echo -e "\nThere is no Instnace in Running or Stopped state that matches the given string..."
  exit
fi

stop_cluster.sh $1

if [  "$?" -ne 0 ]
then
	exit
fi

echo -e " \n----------------------------------------------------------------------------\n\t ****** WARNING !!! ****** \n "
echo -e "The following instances will be DELETED : \n"
for i in $(docker -H $SWARM_MANAGER:4000 ps -a | grep $1 | awk -F "/" '{print $NF}')
do
	echo -e "\t" $i
done
echo -e "\n\t"
read -p "Are you sure ? [Y/N] : " choice
if [ "$choice" == "Y" ] || [ "$choice" == "y" ]
then
	docker -H $SWARM_MANAGER:4000 rm $(docker -H $SWARM_MANAGER:4000 ps -a | grep $1 | awk -F "/" '{print $NF}')
fi
