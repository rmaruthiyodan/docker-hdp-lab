#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Docker HDP Lab Setup Clean script.
########


echo -e "\nContinuing the Cleanup will Remove *ALL* Instances & *ALL* Docker Images, along with Configs & Image repository directory\n"
read -p "Are you Sure about it ? [Y/N] : " choice
if [ "$choice" != "Y" ] && [ "$choice" != "y" ]
then
        exit 1
fi

echo -e "\n\tStopping all running containers...\n"
docker kill $(docker ps -q)
echo -e "\n\tDeleting all containers... \n"
docker rm $(docker ps -qa)

echo -e "\n\tDeleting all docker images from the node ( You still have 10s to press Ctrl+c & Cancel this operation )...\n"
sleep 10
docker rmi $(docker images -q)

echo -e "\n\tDeleting the config file, service startup script and image repository...\n"
rm -rf /opt/docker_cluster
rm -f /etc/docker-hdp-lab.conf
rm -f /etc/systemd/system/docker-hdp-lab.service
rm -f /etc/systemd/system/multi-user.target.wants/docker-hdp-lab.service

echo -e "\tClean up Done! \n"
