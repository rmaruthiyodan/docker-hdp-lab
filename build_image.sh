#!/bin/bash
########
#Author: Ratish Maruthiyodan
#Project: Docker HDP Lab
########

__check_n_build_dir() {
	if [ ! -d /opt/docker_cluster/ambari-server-$AMBARI_VERSION ];then
		mkdir /opt/docker_cluster/ambari-server-$AMBARI_VERSION
	fi
	cp /opt/docker_cluster/ambari-server-template/* /opt/docker_cluster/ambari-server-$AMBARI_VERSION

	if [ ! -d /opt/docker_cluster/ambari-agent-$AMBARI_VERSION ];then
                mkdir /opt/docker_cluster/ambari-agent-$AMBARI_VERSION
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

	cd /opt/docker_cluster/ambari-agent-$AMBARI_VERSION
	docker images | grep -q "hdp/ambari-agent-$AMBARI_VERSION"
	if [ ! $? -eq 0 ]; then
		echo "Building docker image for ambari-agent-$AMBARI_VERSION..."
       		 docker build -t hdp/ambari-agent-$AMBARI_VERSION .
		sleep 5
	fi
	echo "Saving image ambari-agent-$AMBARI_VERSION.tar ..."
	docker save -o ambari-agent-$AMBARI_VERSION.tar hdp/ambari-agent-$AMBARI_VERSION
}

__distribute_n_build(){
	
	for (( i=1 ; i <=$NUM_OF_DOCKER_HOSTS; i++))
	do
		eval "DH=\${DOCKER_HOST${i}}"
		echo -e "\nCopying & Building New Ambari Images on : [ " $DH " ]"
		ssh -q root@$DH mkdir -p /opt/docker_cluster/ambari-server-$AMBARI_VERSION
		scp /opt/docker_cluster/ambari-server-$AMBARI_VERSION/ambari-server-$AMBARI_VERSION.tar root@$DH:/opt/docker_cluster/ambari-server-$AMBARI_VERSION/

		ssh -q root@$DH mkdir -p /opt/docker_cluster/ambari-agent-$AMBARI_VERSION
		scp /opt/docker_cluster/ambari-agent-$AMBARI_VERSION/ambari-agent-$AMBARI_VERSION.tar root@$DH:/opt/docker_cluster/ambari-agent-$AMBARI_VERSION/

	 	echo -e "\nBuilding local images"
		ssh -q root@$DH "cat /opt/docker_cluster/ambari-server-$AMBARI_VERSION/ambari-server-$AMBARI_VERSION.tar | docker load"
		ssh -q root@$DH "cat /opt/docker_cluster/ambari-agent-$AMBARI_VERSION/ambari-agent-$AMBARI_VERSION.tar | docker load"
		echo "Done"
	done

}

AMBARI_VERSION=$1
AMBARI_YUM_BASE_URL=$2
NUM_OF_DOCKER_HOSTS=2
DOCKER_HOST1="altair"
DOCKER_HOST2="baham"

__check_n_build_dir
__prepare_dirs
__build_n_save_image
__distribute_n_build

