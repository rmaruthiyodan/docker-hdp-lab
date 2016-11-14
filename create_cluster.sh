#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: The first script in this proejct. Creates a new cluster using the given properties
########


__create_instance() {

docker -H $SWARM_MANAGER:4000 run -d --hostname $NODENAME --name $INSTANCE_NAME  --net $DEFAULT_DOMAIN_NAME --net-alias=$NODENAME --env AMBARI_SERVER=$CLUSTERNAME-ambari-server.$DOMAIN_NAME --privileged $IMAGE

}

__set_lifetime() {
        sudo sed -i "/$USERNAME-$CLUSTERNAME/d" $CLUSTER_LIFETIME_FILE
        echo $USERNAME-$CLUSTERNAME $(date -d '+6 hour' "+%s") | $tee_cmd -a $CLUSTER_LIFETIME_FILE > /dev/null
        echo -e "\tCluster Lease is till: $(date -d '+6 hour') \n"
}

__resource_check() {
for (( i=1;i<=$NUM_OF_DOCKER_HOSTS;i++ ))
do
	eval "dh=\${DOCKER_HOST${i}}"
	ssh_options="-o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=5"
        read free cache <<< $($ssh_cmd $sh_options $dh "cat /proc/meminfo" 2> /dev/null | egrep "MemFree|Cached" | head -n2 | awk '{print $2}')
	if [ $? -ne 0 ]
	then
		break
	fi
        free_memory=$(( ($free + $cache)/1024/1024 ))
        if [ $free_memory -lt 5 ]
        then
            echo -e "\n$(tput setaf 1)The Docker Host [ $dh ] is running with less than 5GiB of Free memory"
            echo -e "Failed to create the Cluster since one Docker Host is running with very less free memory at this time$(tput sgr 0)\n"
            exit 1
        fi
        #echo "Free Mem on $dh: " $free_memory
done

}

__validate_ambariserver_hostname()
{
	IP=$(getent hosts $CLUSTERNAME-ambari-server.$DOMAIN_NAME)
        if [  $? -eq 0 ]; then
                echo -e "\t $(tput setaf 1) An instance already exists in this cluster, with the name: '" $CLUSTERNAME-ambari-server.$DOMAIN_NAME "' Please use unique hostnames...$(tput sgr 0)"
                exit
        fi

}


__validate_hostnames() {
# Function Checks for duplicate hostnames and check if they are valid
for (( i=1; i<=$NUM_OF_NODES; i++ ))
do
        eval "NODENAME=\${HOST${i}}"
	existing_node=$(docker -H $SWARM_MANAGER:4000 ps -a | grep $NODENAME | awk -F "/" '{print $NF}')
	if [ ! -z "$existing_node" ]
	then
		existing_node_fqdn=$(echo $existing_node | cut -d "-" -f 3-).$(docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $existing_node)
		if [ "$existing_node_fqdn" == "$NODENAME.$DOMAIN_NAME" ]
		then
			echo -e "\t $(tput setaf 1) An instance already exists in this environment, with the name: [" $NODENAME.$DOMAIN_NAME "] Please use unique hostnames...$(tput sgr 0)\n"
			exit 1
		fi	
	fi

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

__validate_clustername() {
	echo $CLUSTERNAME | egrep -q '[^0-9a-zA-Z]'
	if [ $? -eq 0 ]; then
	  echo -e "\t$(tput setaf 1)Invalid Clustername: " $CLUSTERNAME "$(tput sgr 0)"
	  echo -e "\tCannot have cluster names with charaters other than [a-z], [A-Z] and [0-9]\n"
	  exit
	fi
}

__update_arp_table() {
	# first on ambari server & on overlay-gateway node
	INSTANCE_NAME=$USERNAME-$CLUSTERNAME-ambari-server
	while read entry
	do
    	docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME $entry 2> /dev/null
	docker -H $SWARM_MANAGER:4000 exec overlay-gatewaynode $entry 2> /dev/null
	done < $USERNAME-$CLUSTERNAME-tmparptable

	# For all other nodes
	for (( i=1; i<=$NUM_OF_NODES; i++ ))
	do
 		eval "NODENAME=\${HOST${i}}"
 		INSTANCE_NAME=$USERNAME-$CLUSTERNAME-$NODENAME

 		while read entry
  		do
			docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME $entry 2> /dev/null
  		done < $USERNAME-$CLUSTERNAME-tmparptable
  	done
}

__populate_clusterversion_file() {
## Function to update HDP and Ambari version info into the file
        clusterversion_file="/opt/docker_cluster/clusterversions"
        AMBARI_VER=$AMBARIVERSION
        HDP_VER=$CLUSTER_VERSION
        grep -q "\-$USERNAME-$CLUSTERNAME-" $clusterversion_file
        if [ $? -eq 0 ]
        then
                sed -i "/-$USERNAME-$CLUSTERNAME-/c\-$USERNAME-$CLUSTERNAME- $AMBARI_VER $HDP_VER" $clusterversion_file
        else
                echo "-$USERNAME-$CLUSTERNAME- $AMBARI_VER $HDP_VER" >> $clusterversion_file
        fi
}


__populate_hosts_file() {
for ip in $(awk '{print $1}' $USERNAME-$CLUSTERNAME-tmphostfile)
do
	while ! cat $USERNAME-$CLUSTERNAME-tmphostfile | $ssh_cmd -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ip "cat >> /etc/hosts" 2> /dev/null
	do
	 echo "Initialization of " `grep $ip $USERNAME-$CLUSTERNAME-tmphostfile| awk '{print $2}'`  " is taking some time to complete. Waiting for another 5s..."
	 sleep 5
	done

done
# rm -f $USERNAME-$CLUSTERNAME-tmphostfile
}

__check_ambari_server_portstatus() {
	loop=0
	nc $AMBARI_SERVER_IP 8080 < /dev/null
	while [ $? -eq 1 ]
	do
		echo "Sleeping for 10 seconds while waiting for initialization..."
		sleep 10
		loop=$(( $loop + 1 ))
		if [ $loop -eq 10 ]
		then
			echo -e "\nThere may be some error with the Ambari-Server connection or service startup..."
			read -p "Would you like to continue waiting for Ambari-Server to initialize ? [Y/N] : " choice
			if [ "$choice" != "Y" ] && [ "$choice" != "y" ]
			then
				echo -e "\n\tStopping the newly created cluster..."
				delete_cluster.sh $USERNAME-$CLUSTERNAME -F
        		exit 1
			fi	
		fi

		nc $AMBARI_SERVER_IP 8080 < /dev/null
	done
}

__check_ambari_agent_status() {

	for ip in $(awk '{print $1}' $USERNAME-$CLUSTERNAME-tmphostfile)
	do
		# Do not run the check on ambari-server node
		grep $ip $USERNAME-$CLUSTERNAME-tmphostfile | grep -q "ambari-server"
		if [ "$?" -eq 0 ]
		then
			break
		fi

		loop = 0
		nc $ip 8670 < /dev/null
		while [ $? -eq 1 ]
		do
			echo "Ambari-agent service on $i is taking some time to initialize. Sleeping for 10s..."
			sleep 10
			loop=$(( $loop + 1 ))
			if [ $loop -eq 10 ]
			then
				echo -e "\nThis Node at IP [$i] appears to be too slow to startup..."
				read -p "Would you like to continue waiting for Ambari-Agent service to initialize ? [Y/N] : " choice
				if [ "$choice" != "Y" ] && [ "$choice" != "y" ]
				then
					echo -e "\n\tStopping the newly created cluster..."
					delete_cluster.sh $USERNAME-$CLUSTERNAME -F
        				exit 1
				fi	
			fi
			nc $i 8670 < /dev/null
		done
	done
}


## Main
#set -x
if [ $# -ne 1 ] || [ ! -f $1 ];then
 echo "Insuffient or Incorrect Arguments"
 echo "Usage:: create_cluster.sh <cluster.properties filename>"
 exit
fi

CLUSTER_PROPERTIES=$1
source $CLUSTER_PROPERTIES > /dev/null 2>&1

if [ ! $USERNAME ] || [ ! $CLUSTERNAME ] || [ ! $CLUSTER_VERSION ] || [ ! $AMBARIVERSION ] || [ ! $NUM_OF_NODES ] || [ ! $DOMAIN_NAME ]; then
 echo -e "\tIncorrect Cluster properties file"
 exit
fi

if [ "$NUM_OF_NODES" -ne `grep "HOST[0-9]*=" $CLUSTER_PROPERTIES| wc -l` ]
then
  echo -e "\n\tNUM_OF_NODES in the cluster properties file does not match the defined hosts. Exiting.\n"
  exit 1
elif [ "$NUM_OF_NODES" -ne `grep "HOST[0-9]*_SERVICE" $CLUSTER_PROPERTIES | wc -l` ]
then
  echo -e "\n\tNUM_NODES in the cluster properties file does not match the HOST_x_SERVICES defined. Exiting.\n"
  exit 1
fi

source /etc/docker-hdp-lab.conf

if [ "$USER" != "root" ]
then
        export ssh_cmd="sudo /bin/ssh"
        export tee_cmd="sudo tee"
else
        export ssh_cmd="/bin/ssh"
        export tee_cmd="tee"
fi


__resource_check
# Validate the hostnames and find duplicates
__validate_hostnames
__validate_clustername
__validate_ambariserver_hostname

INSTANCE_NAME=$USERNAME-$CLUSTERNAME-ambari-server
NODENAME=$CLUSTERNAME-ambari-server.$DOMAIN_NAME

matching_versions=$(docker images | grep  "hdp/ambari-server-$AMBARIVERSION" | awk -F '/| ' '{print $2}' | awk -F '-' '{print $NF}' )
echo $matchig_versions
if [ `echo $matching_versions | wc -w` -gt 1 ]
then
	echo  -e "Please choose the exact Ambari version. There are multiple matching versions:\n$matching_versions"
	exit 1
else
	AMBARIVERSION=$matching_versions
fi	

if [ -z "$matching_versions" ]
then	
#AMBARIVERSION=$AMBARIVERSION'.0'
#	echo -e "\nGiven Ambari version image doesn't exist... Trying Ambari version as: $AMBARIVERSION"
#	docker images | grep -q "hdp/ambari-server-$AMBARIVERSION"
#	if [ $? -ne '0' ]
#	then
		echo -e "\nPlease check the Ambari version specified & if thats correct then it is likely that we need to build a local image for this version\n\t Run \"build_image.sh\" command for the required version"
		echo -e "\nFollowing are the currently available Ambari images..."
		docker images | grep ambari-server | awk -F '/| ' '{print $2}'
		echo -e "\n"
		exit 1
fi
echo "Ambari version =" $AMBARIVERSION
IMAGE=hdp/ambari-server-$AMBARIVERSION


# Create Ambari-server instance
echo "Starting: " $NODENAME
__create_instance
sleep 2
IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect $INSTANCE_NAME  |  grep -i "ipaddress" | grep 10 |xargs |awk -F ' |,' '{print $2}')
echo $IPADDR   $NODENAME > $USERNAME-$CLUSTERNAME-tmphostfile
MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' $INSTANCE_NAME`
echo "arp -s $IPADDR $MACADDR" > $USERNAME-$CLUSTERNAME-tmparptable

# To create remaining Nodes:
IMAGE=hdp/ambari-agent-$AMBARIVERSION

for (( i=1; i<=$NUM_OF_NODES; i++ ))
do
	eval "NODENAME=\${HOST${i}}"
    	INSTANCE_NAME=$USERNAME-$CLUSTERNAME-$NODENAME
	S_NODENAME=$NODENAME
	NODENAME=$NODENAME.$DOMAIN_NAME
	echo "Starting: " $NODENAME
    __create_instance

	IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect $INSTANCE_NAME  |  grep -i "ipaddress" | grep 10 |xargs |awk -F ' |,' '{print $2}')
	echo $IPADDR   $NODENAME  $S_NODENAME >> $USERNAME-$CLUSTERNAME-tmphostfile

	MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' $INSTANCE_NAME`
	echo "arp -s $IPADDR $MACADDR" >> $USERNAME-$CLUSTERNAME-tmparptable

done
#sleep 5

set -e
# capture the MAC address of overlay gateway too
IPADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' overlay-gatewaynode`
MACADDR=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' overlay-gatewaynode`
echo "arp -s $IPADDR $MACADDR" >> $USERNAME-$CLUSTERNAME-tmparptable
set +e

### Update ARP table on all the nodes

__update_arp_table

__populate_hosts_file

AMBARI_SERVER_IP=$(docker -H $SWARM_MANAGER:4000 inspect $USERNAME-$CLUSTERNAME-ambari-server  |  grep -i "ipaddress" | grep 10 |xargs |awk -F ' |,' '{print $2}')
echo -e "\nAmbari Server IP is: $AMBARI_SERVER_IP"

echo -e "\n\tChecking if $AMBARI_SERVER_IP:8080 is reachable\n"
__check_ambari_server_portstatus
echo -e "\b  ...[OK]"
echo -e "\n\tChecking if Ambari-Agents have started\n"
__check_ambari_agent_status
echo -e "\b  ...[OK]"

rm -f $USERNAME-$CLUSTERNAME-tmphostfile

CLUSTER_LIFETIME_FILE=/opt/docker_cluster/cluster_lease
__set_lifetime

__populate_clusterversion_file
sleep 20
generate_json.sh $CLUSTER_PROPERTIES $AMBARI_SERVER_IP
