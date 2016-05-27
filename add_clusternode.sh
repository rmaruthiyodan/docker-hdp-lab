#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: The script adds a new node to an existing cluster
########

__create_instance() {

docker -H $SWARM_MANAGER:4000 run -d --hostname $NODENAME --name $INSTANCE_NAME  --net $DEFAULT_DOMAIN_NAME  --net-alias=$NODENAME --env AMBARI_SERVER=$CLUSTERNAME-ambari-server.$DOMAIN_NAME --privileged $IMAGE

}


__validate_hostname() {

IP=$(getent hosts $NODENAME)
if [  $? -eq 0 ]; then
  echo -e "\t $(tput setaf 1) An instance already exists in this cluster, with the name: '" $NODENAME "' Please use unique hostnames...$(tput sgr 0)\n"
  exit
else
  echo $NODENAME | egrep -q '[^.0-9a-z-]'
  if [ $? -eq 0 ]; then
     echo -e "\t $(tput setaf 1)Invalid Hostname: " $NODENAME "$(tput sgr 0)"
     echo "Valid Hostnames charaters are limited to [a-z], [0-9], dot(.) and hyphen (-) symbols \n"
     exit
  fi
fi
}


__validate_clustername() {

clusters=`docker -H $SWARM_MANAGER:4000 ps | grep "\/$USERNAME-" | awk -F "/" '{print $NF}' | cut -f 2 -d"-" | sort | uniq`
if [ ! $(echo $clusters | grep "$CLUSTERNAME") ]
then
  echo -e "\nNon existing Cluster $CLUSTERNAME. Please check the Username-Clustername parameteri\n"
  exit
fi

}

__find_ambari_image_ver() {

AMBARIVERSION=$(docker -H $SWARM_MANAGER:4000 ps | grep $USERNAME-$CLUSTERNAME-ambari-server | awk '{print $2}' | cut -d"-" -f1,2 --complement)

}

__add_host_and_install_components() {

    curl  --user admin:admin -H "X-Requested-By: ambari" -i -X POST http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTERNAME/hosts/$NODENAME
    for COMPONENT in $LIST_OF_COMPONENTS
    do
	curl  --user admin:admin -H "X-Requested-By: ambari" -i -X POST http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTERNAME/hosts/$NODENAME/host_components/$COMPONENT
	curl  --user admin:admin -H "X-Requested-By: ambari" -i -X PUT -d '{"HostRoles": {"state": "INSTALLED"}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTERNAME/hosts/$NODENAME/host_components/$COMPONENT
    done

    for COMPONENT in $LIST_OF_COMPONENTS
    do
	curl  --user admin:admin -H "X-Requested-By: ambari" -i -X PUT -d '{"HostRoles": {"state": "STARTED"}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTERNAME/hosts/$NODENAME/host_components/$COMPONENT
    done
}

#set -x
if [ $# -ne 2 ];then
 echo -e "\n\tInsuffient or Incorrect Arguments"
 echo "Usage:: add_clusternode.sh <username-clustername> <nodename>"
 echo -e "Example:: add_clusternode.sh ratish-hdp234 n5.hwxblr.com\n"
 exit
fi

source $CLUSTER_PROPERTIES > /dev/null 2>&1

# Validate the hostnames and find duplicates
source /etc/docker-hdp-lab.conf

USERNAME_CLUSTER=$1
USERNAME=`echo $USERNAME_CLUSTER|cut -f1 -d"-"`
CLUSTERNAME=`echo $USERNAME_CLUSTER|cut -f2 -d"-"`

NODENAME=$2
DOMAIN_NAME=`echo $NODENAME | cut -f1 -d"." --complement`


__validate_hostname
__validate_clustername
__find_ambari_image_ver



IMAGE=hdp/ambari-agent-$AMBARIVERSION

SHORT_NODENAME=`echo $NODENAME| cut -d"." -f1`
INSTANCE_NAME=$USERNAME-$CLUSTERNAME-$SHORT_NODENAME
echo $NODENAME

__create_instance
start_cluster.sh $USERNAME_CLUSTER
LIST_OF_COMPONENTS="HDFS_CLIENT MAPREDUCE2_CLIENT YARN_CLIENT ZOOKEEPER_CLIENT"
AMBARI_SERVER_IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $USERNAME-$CLUSTERNAME-ambari-server`
__add_host_and_install_components

exit
