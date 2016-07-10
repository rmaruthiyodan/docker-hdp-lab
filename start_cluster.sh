#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Starts an existing cluster, that was previously shutdown.
########

__start_instance(){
	docker -H $SWARM_MANAGER:4000 start $INSTANCE_NAME
}

__set_lifetime() {
	sudo sed -i "/$USERNAME_CLUSTERNAME/d" /opt/docker_cluster/cluster_lease
	echo $USERNAME_CLUSTERNAME $(date -d '+6 hour' "+%s") | $tee_cmd -a $CLUSTER_LIFETIME_FILE
	echo -e "\tCluster Lease is till: $(date -d '+6 hour') \n"
}

__resource_check() {

for dh in $(docker -H $SWARM_MANAGER:4000 ps -a | grep "\/$USERNAME_CLUSTERNAME" | awk '{print $NF}' | awk -F "/" '{print $1}' | sort -u)
do
	ssh_options="-o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=5"
	read free cache <<< $($ssh_cmd $ssh_options $dh "cat /proc/meminfo" 2> /dev/null | egrep "MemFree|Cached" | head -n2 | awk '{print $2}')
	free_memory=$(( ($free + $cache)/1024/1024 ))
	if [ $free_memory -lt 5 ]
	then
	    echo -e "\n$(tput setaf 1)Atleast one Instance in this cluster is present on [$dh]. And the Docker Host is running with less than 5GiB of Free memory"
	    echo -e "\tCannot Start the Cluster since Docker Host is running with very less free memory at this time$(tput sgr 0)\n"
	    exit 1
	fi
	#echo "Free Mem on $dh: " $free_memory
done

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
	MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' $INSTANCE_NAME`
	echo "arp -s $IP $MACADDR" >> /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
#	echo $IP  $HOST_NAME.$DOMAIN_NAME $HOST_NAME
}

__update_arp_table() {
	for (( i=1; i<=$node_count ; i++ ))
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


if [ "$USER" != "root" ]
then
	export ssh_cmd="sudo /bin/ssh"
	export tee_cmd="sudo tee"
else
	export ssh_cmd="/bin/ssh"
	export tee_cmd="tee"
fi

__resource_check
node_count=0
amb_server_restart_flag=0

echo "127.0.0.1		localhost localhost.localdomain" > $TEMP_HOST_FILE
for i in $(docker -H $SWARM_MANAGER:4000 ps -a | grep "\/$USERNAME_CLUSTERNAME" | awk -F "/" '{print $NF}')
do
	INSTANCE_NAME=$i
	node_count=$(($node_count+1))
	HOST_AMBAGENT_RESTART[$node_count]=1
	HST[$node_count]=`echo $INSTANCE_NAME | awk -F "." '{print $1}'`
	if (! `docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME` )  then
		HOST_AMBAGENT_RESTART[$node_count]=0
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

counter=1
echo  ""
## Sending the prepared /etc/hosts files to all the nodes in the cluster
for ip in $(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker -H $SWARM_MANAGER:4000 ps -a | grep $USERNAME_CLUSTERNAME | awk -F "/" '{print $NF}'))
do
	echo -e "\tPopulating /etc/hosts on $ip"
        while ! cat $TEMP_HOST_FILE | $ssh_cmd  -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "cat > /etc/hosts" >/dev/null 2>&1
        do
         echo "Initialization of [" `grep $ip $TEMP_HOST_FILE| awk '{print $2}'` "] is taking a bit long to complete.. waiting for another 5s"
         sleep 5
        done
	if [ "$amb_server_restart_flag" -eq 1 ] && [ "${HOST_AMBAGENT_RESTART[$counter]}" -ne 0 ]
	then
	  echo -e "\tRestarting Ambari-agent on : $ip \n"
	  $ssh_cmd -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "service ambari-agent restart" >/dev/null 2>&1
	fi
	counter=$(($counter+1))
done
echo -e "\n\tAmbari server IP is :" $AMBARI_SERVER_IP "\n"

CLUSTER_LIFETIME_FILE=/opt/docker_cluster/cluster_lease
__set_lifetime
#__start_services


#rm -f $TEMP_HOST_FILE
