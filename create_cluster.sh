#!/bin/bash

__create_instance() {

docker -H $SWARM_MANAGER:4000 run -d --hostname $NODENAME --name $INSTANCE_NAME  --net hwxblr.com --net-alias=$NODENAME --env AMBARI_SERVER=$CLUSTERNAME-ambari-server.$DOMAIN_NAME --privileged $IMAGE

}

__validate_hostnames() {
# Function Checks for duplicate hostnames and check if they are valid
for (( i=1; i<=$NUM_OF_NODES; i++ ))
do
        eval "NODENAME=\${HOST${i}}"
        NODENAME=$NODENAME.$DOMAIN_NAME
	IP=$(getent hosts $NODENAME)
	if [  $? -eq 0 ]; then
		echo -e "\t $(tput setaf 1) An instance already exists in this cluster, with the name: '" $NODENAME "' Please use unique hostnames...$(tput sgr 0)"
		exit
	else
		echo $NODENAME | egrep -q '[^.0-9a-z-]'
		if [ $? -eq 0 ]; then
		   echo -e "\t $(tput setaf 1)Invalid Hostname: " $NODENAME "$(tput sgr 0)"
		   echo "Valid Hostnames charaters are limited to [a-z], [0-9], dot(.) and hyphen (-) symbols"
		   exit
		fi
	fi
done 

}


if [ $# -ne 1 ] || [ ! -f $1 ];then
 echo "Insuffient or Incorrect Arguments"
 echo "Usage:: create_cluster.sh <cluster.properties filename>"
 exit
fi

CLUSTER_PROPERTIES=$1
source $CLUSTER_PROPERTIES

if [ ! $USERNAME ] || [ ! $CLUSTERNAME ] || [ ! $CLUSTER_VERSION ] || [ ! $AMBARIVERSION ] || [ ! $NUM_OF_NODES ] || [ ! $DOMAIN_NAME ]; then
 echo "Incorrect Cluster properties file"
 exit
fi

# Validate the hostnames and find duplicates
__validate_hostnames

SWARM_MANAGER=altair
INSTANCE_NAME=$USERNAME-$CLUSTERNAME-ambari-server
NODENAME=$CLUSTERNAME-ambari-server.$DOMAIN_NAME
IMAGE=hdp/ambari-server-$AMBARIVERSION


# Create Ambari-server instance
__create_instance
sleep 2
IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect $INSTANCE_NAME  |  grep -i "ipaddress" | grep 10 |xargs |awk -F ' |,' '{print $2}')
echo $IPADDR   $NODENAME > $USERNAME-$CLUSTERNAME-tmphostfile

# To create remaining Nodes:

IMAGE=hdp/ambari-agent-$AMBARIVERSION

for (( i=1; i<=$NUM_OF_NODES; i++ ))
do
	eval "NODENAME=\${HOST${i}}"
        INSTANCE_NAME=$USERNAME-$CLUSTERNAME-$NODENAME
	NODENAME=$NODENAME.$DOMAIN_NAME
	echo $NODENAME
        __create_instance
	IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect $INSTANCE_NAME  |  grep -i "ipaddress" | grep 10 |xargs |awk -F ' |,' '{print $2}')
	echo $IPADDR   $NODENAME >> $USERNAME-$CLUSTERNAME-tmphostfile
done
sleep 5
for ip in $(awk '{print $1}' $USERNAME-$CLUSTERNAME-tmphostfile)
do
	while ! cat $USERNAME-$CLUSTERNAME-tmphostfile | ssh root@$ip "cat >> /etc/hosts"
	do
	 echo "Initialization of " `grep $ip $USERNAME-$CLUSTERNAME-tmphostfile| awk '{print $2}'`  " is taking too long to complete.. waiting for another 5s"
	 sleep 5
	done

done
rm -f $USERNAME-$CLUSTERNAME-tmphostfile
AMBARI_SERVER_IP=$(docker -H $SWARM_MANAGER:4000 inspect $USERNAME-$CLUSTERNAME-ambari-server  |  grep -i "ipaddress" | grep 10 |xargs |awk -F ' |,' '{print $2}')
echo "Ambari Server IP" $AMBARI_SERVER_IP
echo "Sleeping for 15 seconds while waiting for initialization..."
sleep 15
generate_json.sh $CLUSTER_PROPERTIES $AMBARI_SERVER_IP
