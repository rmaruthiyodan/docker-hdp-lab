#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Starts an existing cluster, that was previously shutdown.
########

__start_instance(){
	docker -H $SWARM_MANAGER:4000 start $INSTANCE_NAME
}

__populate_hostsfile(){
	IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	HOST_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $INSTANCE_NAME`
	DOMAIN_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $INSTANCE_NAME`
	echo $IP "  " $HOST_NAME.$DOMAIN_NAME $HOST_NAME >> $TEMP_HOST_FILE
#	echo $IP  $HOST_NAME.$DOMAIN_NAME $HOST_NAME
}

if [ $# -ne 1 ];then
 echo "Usage:: start_cluster <USERNAME>-<CLUSTERNAME>"
 exit
fi


__start_services(){
	echo "Sleeping for 20 seconds, while waiting for Ambari Server to discover the nodes liveliness"
	sleep 20
## Starting All services and since this is not consitently starting all services, explicitly starting Zookeeper, HDFS and Yarn services "
        curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start All Services"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services > /tmp/dhc-curl.out
	curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start ZOOKEEPER via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services/ZOOKEEPER >> /tmp/dhc-curl.out
	curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start HDFS via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services/HDFS >> /tmp/dhc-curl.out
	curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start YARN via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services/YARN >> /tmp/dhc-curl.out

	echo -e "\n\tLogin to Ambari Server at :  http://$AMBARI_SERVER_IP:8080"
	echo -e "If the services are not starting by itself, run the following command again: \n curl -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start All Services"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services"
}


#set -x
USERNAME_CLUSTERNAME=$1

source /etc/docker-hdp-lab.conf

TEMP_HOST_FILE=/tmp/$USERNAME_CLUSTERNAME-tmphostfile
CLUSTER_NAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $NF}')
echo $USERNAME_CLUSTERNAME

### Starting the stopped Instances in the cluster and preparing /etc/hosts file on all the nodes again

echo "127.0.0.1		localhost localhost.localdomain" > $TEMP_HOST_FILE
for i in $(docker -H $SWARM_MANAGER:4000 ps -a | grep "\/$USERNAME_CLUSTERNAME" | awk -F "/" '{print $NF}')
do
	INSTANCE_NAME=$i
	if (! `docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME` )  then
		echo "Starting: " $INSTANCE_NAME
		__start_instance
		echo "$INSTANCE_NAME" | grep -q "ambari-server"
		if [ "$?" -eq 0  ] 
		then
		  amb_server_restart_flag=1
		fi
	fi
	if ( $(echo "$INSTANCE_NAME" | grep -q "ambari-server") ) then
		AMBARI_SERVER_IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	fi
	__populate_hostsfile
done


sleep 5

## Sending the prepared /etc/hosts files to all the nodes in the cluster
amb_server_restart_flag=0
for ip in $(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker -H $SWARM_MANAGER:4000 ps -a | grep $USERNAME_CLUSTERNAME | awk -F "/" '{print $NF}'))
do
        while ! cat $TEMP_HOST_FILE | ssh root@$ip "cat > /etc/hosts"
        do
         echo "Initialization of [" `grep $ip $TEMP_HOST_FILE| awk '{print $2}'` "] is taking a bit long to complete.. waiting for another 5s"
         sleep 5
        done
	if [ "$amb_server_restart_flag" -eq 1 ] 
	then
	  ssh root@$ip "service ambari-agent restart"
	fi
done

echo "ambari server ip is :" $AMBARI_SERVER_IP

__start_services


rm -f $TEMP_HOST_FILE

