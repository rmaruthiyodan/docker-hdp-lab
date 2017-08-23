#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Script to populate /etc/hosts files on multiple clusters to have each others hostnames resolvable
########

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
	echo "arp -s $IP $MACADDR" >> $TEMP_ARP_FILE
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


__update_arp_table() {
	for (( i=1; i<=$node_count ; i++ ))
	do
 		NODNAME=${HST[$i]}
 		INSTANCE_NAME=$NODNAME
 		while read entry
  		do
			docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME $entry 2> /dev/null
  		done < $TEMP_ARP_FILE

## Performing a ping from each node to Overlay Network GW to address a node reachability issue that is intermittently seen
		docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME ping -qc 1 $OVERLAY_GATEWAY_IP > /dev/null 2>&1
  	done

	# Also updating ARP entry on gateway node
        while read entry
        do
                docker -H $SWARM_MANAGER:4000 exec overlay-gatewaynode $entry 2> /dev/null
        done < $TEMP_ARP_FILE
}


## Main starts here...
#set -x

if [ $# -lt 2 ];then
 echo "Usage:: update_cluster_hostfile.sh <USER1>-<CLUSTER1> <USER2>-<CLUSTER2> ..<USERn><CLUSTERn>"
 exit
fi

source /etc/docker-hdp-lab.conf
TEMP_HOST_FILE=/tmp/$1-tmphostfile
TEMP_ARP_FILE=/tmp/$1-tmparptable

echo "127.0.0.1		localhost localhost.localdomain" > $TEMP_HOST_FILE

node_count=0

for clustername in $*
do

  USERNAME_CLUSTERNAME=$clustername
  CLUSTER_NAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $NF}')
  USERNAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $1}')


  amb_server_restart_flag=0

  for i in $(docker -H $SWARM_MANAGER:4000 ps | grep "\/$USERNAME_CLUSTERNAME" | awk -F "/" '{print $NF}')
  do
	INSTANCE_NAME=$i
	node_count=$(($node_count+1))
	HST[$node_count]=`echo $INSTANCE_NAME | awk -F "." '{print $1}'`
	__populate_hostsfile
  done
done

__add_common_entries_hostfile

set -e
# capture the MAC address of overlay gateway too
IPADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' overlay-gatewaynode`
OVERLAY_GATEWAY_IP=$IPADDR
MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' overlay-gatewaynode`
echo "arp -s $IPADDR $MACADDR" >> $TEMP_ARP_FILE
set +e

__update_arp_table


for clustername in $*
do

  echo -e "\nUpdating the cluster : " $USERNAME_CLUSTERNAME
  USERNAME_CLUSTERNAME=$clustername
  CLUSTER_NAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $NF}')
  USERNAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $1}')
  ## Sending the prepared /etc/hosts files to all the nodes in the cluster
  for ip in $(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker -H $SWARM_MANAGER:4000 ps | grep "$USERNAME_CLUSTERNAME" | awk -F "/" '{print $NF}'))
  do
	echo -e "\tPopulating /etc/hosts on $ip"
        while ! cat $TEMP_HOST_FILE | ssh  -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "cat > /etc/hosts" >/dev/null 2>&1
        do
         echo "Unable to ssh into [" `grep $ip $TEMP_HOST_FILE| awk '{print $2}'` "] .. will try again after 5s"
         sleep 5
        done
  done
done
