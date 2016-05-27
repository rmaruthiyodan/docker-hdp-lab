#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Run this script to build a new Docker images for Ambari-agent and ambari-server, and to distribute them on other Docker hosts
########

__check_n_create_dir() {
	if [ ! -d /opt/docker_cluster/ambari-server-$AMBARI_VERSION ];then
		mkdir -p /opt/docker_cluster/ambari-server-$AMBARI_VERSION
	fi
	cp /opt/docker_cluster/ambari-server-template/* /opt/docker_cluster/ambari-server-$AMBARI_VERSION

	if [ ! -d /opt/docker_cluster/ambari-agent-$AMBARI_VERSION ];then
                mkdir -p /opt/docker_cluster/ambari-agent-$AMBARI_VERSION
        fi
	cp /opt/docker_cluster/ambari-agent-template/* /opt/docker_cluster/ambari-agent-$AMBARI_VERSION

}

__prepare_dirs() {
	AMBARI_YUM_BASE_URL=$(echo $AMBARI_YUM_BASE_URL|sed 's/\//\\\//g')
	sed -i "s/.*baseurl=.*/baseurl=$AMBARI_YUM_BASE_URL/" /opt/docker_cluster/ambari-server-$AMBARI_VERSION/ambari.repo
 	cp -f /opt/docker_cluster/ambari-server-$AMBARI_VERSION/ambari.repo /opt/docker_cluster/ambari-agent-$AMBARI_VERSION/ambari.repo
}

__build_n_save_image(){

	cd /opt/docker_cluster/ambari-server-$AMBARI_VERSION
	docker images | grep -q "hdp/ambari-server-$AMBARI_VERSION"
	if [ ! $? -eq 0 ]; then
		echo "Building docker image for ambari-server-$AMBARI_VERSION..."
		docker build -t hdp/ambari-server-$AMBARI_VERSION .
		sleep 5
	fi
	echo "Saving image ambari-server-$AMBARI_VERSION.tar ..."
	docker save -o ambari-server-$AMBARI_VERSION.tar hdp/ambari-server-$AMBARI_VERSION

	echo "------------------------------------------------"

	cd /opt/docker_cluster/ambari-agent-$AMBARI_VERSION
	docker images | grep -q "hdp/ambari-agent-$AMBARI_VERSION"
	if [ ! $? -eq 0 ]; then
		echo -e "\nBuilding docker image for ambari-agent-$AMBARI_VERSION...\n"
       		 docker build -t hdp/ambari-agent-$AMBARI_VERSION .
		sleep 5
	fi
	echo "Saving image ambari-agent-$AMBARI_VERSION.tar ..."
	docker save -o ambari-agent-$AMBARI_VERSION.tar hdp/ambari-agent-$AMBARI_VERSION
	echo -e "Done Saving the Ambari-agent image ambari-agent-$AMBARI_VERSION.tar !\n"
}

__distribute_n_build(){

	for (( i=1 ; i <= $NUM_OF_DOCKER_HOSTS; i++))
	do
	    eval "DH=\${DOCKER_HOST${i}}"
	    if [ "$DH" != "$HOSTNAME" ]
	    then
		echo -e "\nCopying & Building New Ambari Images on : [ " $DH " ]"
		ssh -o ConnectTimeout=4 -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q root@$DH mkdir -p /opt/docker_cluster/ambari-server-$AMBARI_VERSION
		scp -o ConnectTimeout=4 -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /opt/docker_cluster/ambari-server-$AMBARI_VERSION/ambari-server-$AMBARI_VERSION.tar root@$DH:/opt/docker_cluster/ambari-server-$AMBARI_VERSION/

		ssh -q root@$DH mkdir -p /opt/docker_cluster/ambari-agent-$AMBARI_VERSION
		scp /opt/docker_cluster/ambari-agent-$AMBARI_VERSION/ambari-agent-$AMBARI_VERSION.tar root@$DH:/opt/docker_cluster/ambari-agent-$AMBARI_VERSION/

	 	echo -e "\nBuilding local images"
		ssh -q root@$DH "cat /opt/docker_cluster/ambari-server-$AMBARI_VERSION/ambari-server-$AMBARI_VERSION.tar | docker load"
		ssh -q root@$DH "cat /opt/docker_cluster/ambari-agent-$AMBARI_VERSION/ambari-agent-$AMBARI_VERSION.tar | docker load"
		echo "Done"
	     fi
	done

}


source /etc/docker-hdp-lab.conf

if [ $# -ne 2 ];then
 echo -e "\nInvalid Number of Argument(s)"
 echo "Usage::  build_image.sh <AmbariVersion> <RepoURL>"
 echo -e "Example::  ./build_image.sh  2.2.2.0  http://$LOCAL_REPO_NODE/AMBARI-2.2.2.0/centos6/2.2.2.0-460/\n"
 exit 1
fi


AMBARI_VERSION=$1
AMBARI_YUM_BASE_URL=$2

__check_n_create_dir
__prepare_dirs
__build_n_save_image
__distribute_n_build

