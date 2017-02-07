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
	echo $USERNAME_CLUSTERNAME $(date -d '+6 hour' "+%s") | $tee_cmd -a $CLUSTER_LIFETIME_FILE > /dev/null
	echo -e "\tCluster Lease is till: $(date -d '+6 hour') \n"
}

__resource_check() {

for dh in $(docker -H $SWARM_MANAGER:4000 ps -a | grep "\/$USERNAME_CLUSTERNAME-" | awk '{print $NF}' | awk -F "/" '{print $1}' | sort -u)
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

	## Also Populating a file for ARP Table
	MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' $INSTANCE_NAME`
	echo "arp -s $IP $MACADDR" >> /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
#	echo $IP  $HOST_NAME.$DOMAIN_NAME $HOST_NAME
}

__add_common_entries_hostfile() {
	i=0
        for entry in $(grep "HOST_ENTRY_" /etc/docker-hdp-lab.conf | awk '{print $1}')
        do
                i=$(($i+1))
                eval "ENTRY=\${HOST_ENTRY_${i}}"
                echo $ENTRY >> $TEMP_HOST_FILE
        done
}

__populate_clusterversion_file() {
## Function to update HDP and Ambari version info into the file
	clusterversion_file="/opt/docker_cluster/clusterversions"
	AMBARI_VER=$(docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME ambari-agent --version)
	hadoopver=$(docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME hadoop version 2> /dev/null | head -n1 | awk '{print $2}')
	HDP_VER=${hadoopver:6}
	grep -q "\-$USERNAME_CLUSTERNAME-" $clusterversion_file
	if [ $? -eq 0 ]
	then
		sed -i "/-$USERNAME_CLUSTERNAME-/c\-$USERNAME_CLUSTERNAME- $AMBARI_VER $HDP_VER" $clusterversion_file
	else
		echo "-$USERNAME_CLUSTERNAME- $AMBARI_VER $HDP_VER" >> $clusterversion_file
	fi
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

## Performing a ping from each node to Overlay Network GW to address a node reachability issue that is intermittently seen
		docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME ping -qc 1 $OVERLAY_GATEWAY_IP > /dev/null 2>&1
  	done

	# Also updating ARP entry on gateway node
        while read entry
        do
                docker -H $SWARM_MANAGER:4000 exec overlay-gatewaynode $entry 2> /dev/null
        done < /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
}

__validate_clustername() {
        docker -H $SWARM_MANAGER:4000 ps -a | grep -q "\/$USERNAME_CLUSTERNAME-"
        if [ $? -ne 0 ]
        then
                echo -e "\n\t$(tput setaf 1)Cluster doesn't exist with the name: $USERNAME_CLUSTERNAME. Check the given <username-clustername> and try again $(tput sgr 0)\n"
                exit
        fi
}

__check_ambari_server_portstatus()
{
        loop=0
        nc $AMBARI_SERVER_IP 8080 < /dev/null
        while [ $? -eq 1 ]
        do
                echo "Ambari-Server is still initializing. Sleeping for 10s..."
                sleep 10
                loop=$(( $loop + 1 ))
		if [ $loop -eq 60 ]
		then
			ssh root@$AMBARI_SERVER_IP service ambari-server restart
                elif [ $loop -eq 10 ]
                then
                        echo -e "\nThere may be some error with the Ambari-Server connection or service startup... Not attempting to start services!"
			echo -e "Run the following command Or Use Ambari WebUI to start the services: \n #curl -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Start All Services\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services"
                        exit 1
                fi

                nc $AMBARI_SERVER_IP 8080 < /dev/null
        done
}


__start_services()
{
        echo "Let's give 5s for Ambari-Server to Start"
        sleep 5
        __check_ambari_server_portstatus
        HB_lost_nodecount=1
        loop_count=0
        while [ $HB_lost_nodecount -gt 0 ]
        do
                HB_lost_nodecount=`curl -u admin:admin -i -H 'X-Requested-By: ambari' -X GET http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME 2> /dev/null | grep "Host/host_state/HEARTBEAT_LOST" | awk '{print $3}' | cut -d',' -f1 `
                if [ -z $HB_lost_nodecount ]
                then
                        HB_lost_nodecount=1
                fi
                loop_count=$(($loop_count+1))

                if [ $loop_count -eq 5 ]
                then
			echo -e "\n\tWaited for 10s and some ambari-agents are still down... :("
			for node in `curl -u admin:admin -i -H 'X-Requested-By: ambari' -X GET http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/hosts 2> /dev/null | grep host_name | awk -F "\"" '{print $(NF-1)}'`
			do
				echo "Restarting ambari-agent on $node"
				nodeip=$(grep $node $TEMP_HOST_FILE | awk '{print $1}')
				ssh $nodeip service ambari-agent restart
			done
			sleep 5
		elif [ $loop_count -eq 15 ]
		then
                        echo "One Or more of Nodes have problems with ambari-agent service. Please check the Ambari-Server UI and restart ambari-agent before manually starting services in the cluster"
                        exit 1
                fi
                sleep 2
         done
	echo "Nodes have started... Will wait for 10s more to services to update"
	sleep 10

## Starting All services and since this is not consitently starting all services, explicitly starting Zookeeper, HDFS and Yarn services "
        curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start All Services"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services > /tmp/dhc-curl.out
        #curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start ZOOKEEPER via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services/ZOOKEEPER >> /tmp/dhc-curl.out
        #curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start HDFS via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services/HDFS >> /tmp/dhc-curl.out
        #curl -s -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start YARN via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services/YARN >> /tmp/dhc-curl.out

        echo -e "\n\tIssued command to start Services... \nIf the services are not starting by itself, run the following command Or Use Ambari WebUI: \n #curl -u admin:admin -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Start All Services\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://$AMBARI_SERVER_IP:8080/api/v1/clusters/$CLUSTER_NAME/services"
}



## Main starts here...
#set -x

if [ $# -ne 1 ];then
 echo "Usage:: start_cluster <USERNAME>-<CLUSTERNAME>"
 exit
fi

USERNAME_CLUSTERNAME=$1

source /etc/docker-hdp-lab.conf

TEMP_HOST_FILE=/tmp/$USERNAME_CLUSTERNAME-tmphostfile
CLUSTER_NAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $NF}')
USERNAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $1}')
### Starting the stopped Instances in the cluster and preparing /etc/hosts file on all the nodes again

__validate_clustername

echo -e "\tStarting Cluster: " $USERNAME_CLUSTERNAME

rm -f /tmp/$USERNAME-$CLUSTER_NAME-tmparptable


if [ "$USER" != "root" ]
then
	export ssh_cmd="sudo /bin/ssh"
	export tee_cmd="sudo tee"
else
	export ssh_cmd="/bin/ssh"
	export tee_cmd="tee"
fi

#__resource_check
node_count=0
amb_server_restart_flag=0

echo "127.0.0.1		localhost localhost.localdomain" > $TEMP_HOST_FILE
for i in $(docker -H $SWARM_MANAGER:4000 ps -a | grep "\/$USERNAME_CLUSTERNAME-" | awk -F "/" '{print $NF}')
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
		else
		  if [ $node_count -eq 1 ]
		  then
			__populate_clusterversion_file
		  fi
		fi
	fi
	if ( $(echo "$INSTANCE_NAME" | grep -q "ambari-server") ) then
		AMBARI_SERVER_IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	fi
	__populate_hostsfile
done

__add_common_entries_hostfile

sleep 5

set -e
# capture the MAC address of overlay gateway too
IPADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' overlay-gatewaynode`
OVERLAY_GATEWAY_IP=$IPADDR
MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' overlay-gatewaynode`
echo "arp -s $IPADDR $MACADDR" >> /tmp/$USERNAME-$CLUSTER_NAME-tmparptable
set +e

__update_arp_table

counter=1
echo  ""
## Sending the prepared /etc/hosts files to all the nodes in the cluster
for ip in $(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker -H $SWARM_MANAGER:4000 ps -a | grep "$USERNAME_CLUSTERNAME-" | awk -F "/" '{print $NF}'))
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
## deleting 90-nproc limits file, if exists
	$ssh_cmd -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "rm -f /etc/security/limits.d/90-nproc.conf" > /dev/null 2>&1
	fi
	counter=$(($counter+1))
done
echo -e "\n\tAmbari server IP is :" $AMBARI_SERVER_IP "\n"

CLUSTER_LIFETIME_FILE=/opt/docker_cluster/cluster_lease
__set_lifetime

echo -e "Attempting to start services in the background. Monitor /tmp/$USERNAME_CLUSTERNAME-startup.out for progress\n"
__start_services > /tmp/$USERNAME_CLUSTERNAME-startup.out 2>&1 &

#rm -f $TEMP_HOST_FILE
