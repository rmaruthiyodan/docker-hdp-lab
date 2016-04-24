#!/bin/bash
set +x

start_instance(){
	docker -H $SWARM_MANAGER:4000 start $INSTANCE_NAME
}

populate_hostsfile(){
	IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	HOST_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $INSTANCE_NAME`
	DOMAIN_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $INSTANCE_NAME`
	echo $IP "  " $HOST_NAME.$DOMAIN_NAME $HOST_NAME >> $TEMP_HOST_FILE
	echo $IP  $HOST_NAME.$DOMAIN_NAME $HOST_NAME
}

if [ $# -ne 1 ];then
 echo "Usage start_cluster.sh <USERNAME>-<CLUSTERNAME>"
 exit
fi

USERNAME_CLUSTERNAME=$1

SWARM_MANAGER=altair
TEMP_HOST_FILE=/tmp/$USERNAME_CLUSTERNAME-tmphostfile

echo $USERNAME_CLUSTERNAME

### Starting the stopped Instances in the cluster and preparing /etc/hosts file on all the nodes again

echo "127.0.0.1		localhost" > $TEMP_HOST_FILE
for i in $(docker -H $SWARM_MANAGER:4000 ps -a | grep $USERNAME_CLUSTERNAME | awk -F "/" '{print $NF}')
do
	INSTANCE_NAME=$i
	if (! `docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME` )  then
		echo "Starting: " $INSTANCE_NAME
		start_instance
	fi
	populate_hostsfile
done


sleep 5

## Sending the prepared /etc/hosts files to all the nodes in the cluster

for ip in $(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker -H $SWARM_MANAGER:4000 ps -a | grep $USERNAME_CLUSTERNAME | awk -F "/" '{print $NF}'))
do
        while ! cat $TEMP_HOST_FILE | ssh root@$ip "cat > /etc/hosts"
        do
         echo "Initialization of [" `grep $ip $TEMP_HOST_FILE| awk '{print $2}'` "] is taking a bit long to complete.. waiting for another 5s"
         sleep 5
        done
done
rm -f $TEMP_HOST_FILE
