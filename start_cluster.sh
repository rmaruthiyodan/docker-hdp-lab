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
	if [ ! -z "$DOMAIN_NAME" ]
        then
                echo $IP "  " $HOST_NAME.$DOMAIN_NAME $HOST_NAME >> $TEMP_HOST_FILE
        else
                S_HOSTNAME=`echo $HOST_NAME | awk -F "." '{print $1}'`
                echo $IP "  " $HOST_NAME $S_HOSTNAME >> $TEMP_HOST_FILE
        fi        
	echo $IP "  " $HOST_NAME.$DOMAIN_NAME $HOST_NAME >> $TEMP_HOST_FILE
	MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' $INSTANCE_NAME`
	echo "arp -s $IP $MACADDR" >> /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
#	echo $IP  $HOST_NAME.$DOMAIN_NAME $HOST_NAME
}

__update_arp_table() {
	for (( i=1; i<=$count ; i++ ))
	do
 		NODNAME=${HST[$i]}
 		INSTANCE_NAME=$NODNAME
 		while read entry
  		do
			docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME $entry 2> /dev/null
  		done < /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
  	done
}

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

if [ $# -ne 1 ];then
 echo "Usage:: start_cluster <USERNAME>-<CLUSTERNAME>"
 exit
fi

USERNAME_CLUSTERNAME=$1

source /etc/docker-hdp-lab.conf

TEMP_HOST_FILE=/tmp/$USERNAME_CLUSTERNAME-tmphostfile
CLUSTER_NAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $NF}')
echo -e "\tStarting Cluster: " $USERNAME_CLUSTERNAME
USERNAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $1}')
### Starting the stopped Instances in the cluster and preparing /etc/hosts file on all the nodes again
rm -f /tmp/$USERNAME-$CLUSTER_NAME-tmparptable

count=0
amb_server_restart_flag=0

echo "127.0.0.1		localhost localhost.localdomain" > $TEMP_HOST_FILE
for i in $(docker -H $SWARM_MANAGER:4000 ps -a | grep "\/$USERNAME_CLUSTERNAME" | awk -F "/" '{print $NF}')
do
	INSTANCE_NAME=$i
	count=$(($count+1))
	HST[$count]=`echo $INSTANCE_NAME | awk -F "." '{print $1}'`
	if (! `docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME` )  then
		echo -e "\nStarting: " $INSTANCE_NAME
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

set -e
# capture the MAC address of overlay gateway too
IPADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' overlay-gatewaynode`
MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' overlay-gatewaynode`
echo "arp -s $IPADDR $MACADDR" >> /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
set +e

__update_arp_table
## Sending the prepared /etc/hosts files to all the nodes in the cluster
for ip in $(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker -H $SWARM_MANAGER:4000 ps -a | grep $USERNAME_CLUSTERNAME | awk -F "/" '{print $NF}'))
do
	echo -e "\tPopulating /etc/hosts on $ip"
        while ! cat $TEMP_HOST_FILE | ssh -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "cat > /etc/hosts" >/dev/null 2>&1
        do
         echo "Initialization of [" `grep $ip $TEMP_HOST_FILE| awk '{print $2}'` "] is taking a bit long to complete.. waiting for another 5s"
         sleep 5
        done
	if [ "$amb_server_restart_flag" -eq 1 ]
	then
	  echo -e "\n\tRestarting Ambari-agent on : $ip"
	  ssh -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "service ambari-agent restart" >/dev/null 2>&1
	fi
done
echo -e "\n\tAmbari server IP is :" $AMBARI_SERVER_IP "\n"

#__start_services


rm -f $TEMP_HOST_FILE
