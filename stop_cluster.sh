#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Although no one likes to stop their clusters ever, this script helps with managing the available resources well, by stopping unwanted clusters
########

source /etc/docker-hdp-lab.conf

if [ $# -ne 1 ] ;then
 echo "Incorrect Arguments"
 echo "Usage:: stop_cluster.sh <username-clustername>"
 exit 1
fi

if [ ! "$(docker -H $SWARM_MANAGER:4000 ps | grep $1 | awk -F "/" '{print $NF}')" ]
then
  echo -e "\nThere is no Running Instnace that matches the given string..."
  exit 0 
fi

# echo -e " \n\t ****** WARNING !!! ****** \n "
echo -e "\nThe following instances will be stopped :"
for i in $(docker -H $SWARM_MANAGER:4000 ps | grep $1 | awk -F "/" '{print $NF}')
do
	echo -e "\t" $i
done
echo -e "\n\t"

read -p "Are you sure to stop ? [Y/N] : " choice
echo "---------------------------------------------------"
if [ "$choice" == "Y" ] || [ "$choice" == "y" ]
then
	docker -H $SWARM_MANAGER:4000 kill $(docker -H $SWARM_MANAGER:4000 ps | grep $1 | awk -F "/" '{print $NF}')
else
	exit 1
fi

