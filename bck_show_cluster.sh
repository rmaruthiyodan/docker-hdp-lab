#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Used for displaying Cluster Nodes and their IPs
########

__print_cluster_info() {
	#echo $USERNAME
	printf "%-12s | %-25s | %-40s | %-15s | %-5s %-4s | %-6s |\n" $USERNAME $junk $junk $junk  $junk $junk
	for cluster_name in $(cat $TMP_DOCKER_PS_OUTFILE | grep "\/$USERNAME\-" | awk -F "/" '{print $NF}' | cut -f 2 -d"-" | sort | uniq)
	do
#		echo -e "\n\t" "$(tput setaf 1)[ $cluster_name ]$(tput sgr 0)"
		printf "%-12s |\e[31m %-25s \e[0m| %-40s | %-15s | %-5s %-4s | %-6s |\e[0m\n" "" $cluster_name - - - - -
		for node_name in $(cat $TMP_DOCKER_PS_OUTFILE | grep "\/$USERNAME-" | grep "\-$cluster_name-" | awk -F "/" '{print $NF}' | cut -f 3-8 -d"-")
		do
			INSTANCE_NAME=$USERNAME-$cluster_name-$node_name
			if [  "$(docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME)" == "false" ]; then 
			  IP="(OFFLINE)"
			  FQDN=$node_name
			  CPU=""
			  MEM=""
			  MEM_UNIT=""
			else	
			  IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	        	  HOST_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $INSTANCE_NAME`
		          DOMAIN_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $INSTANCE_NAME`
			  FQDN=$HOST_NAME.$DOMAIN_NAME
			  INSTANCE_ID=$(grep $INSTANCE_NAME $TMP_DOCKER_PS_OUTFILE | awk '{print $1}')

			  read CPU MEM MEM_UNIT <<< $(grep $INSTANCE_ID $TMP_DOCKER_STATS_OUTFILE| awk '{print $2 , $3 , $4}')
			 # docker -H $SWARM_MANAGER:4000 stats --no-stream $INSTANCE_NAME | tail -n1| awk '{print $2 $3 $4}' | read CPU MEM MEM_UNIT 
			  #IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect INSTANCE_NAME | grep -i  "ipaddress" | grep 10 | xargs)
			fi
 		#	echo -e "\t \t $(tput setaf 2) $FQDN  -->    $IP $(tput sgr 0)"
			if [ $MEM_UNIT == "GB" ] && (( $(echo "$MEM" \> 5 | bc -l) ))
			then
				printf "%-12s | %-25s |\e[32m %-40s \e[0m| %-15s |\e[31m %-5s %-4s\e[0m | %-6s |\e[0m\n" "" ""  $FQDN $IP  $MEM $MEM_UNIT $CPU
			else
				printf "%-12s | %-25s |\e[32m %-40s \e[0m| %-15s | \e[32m%-5s %-4s\e[0m | %-6s |\e[0m\n" "" ""  $FQDN $IP  $MEM $MEM_UNIT $CPU
			fi
		done	  
	#	printf "%-12s |--------------------------------------------------------------------------------------------------------- \n" ""
	done
	echo "----------------------------------------------------------------------------------------------------------------------------"
}


if [ $# -lt 1 ];then
 echo "Usage:: show_cluster.sh < all | username > [online]"
 echo "Displaying cluster for the current user " $USER
 USERNAME=$USER
else
 USERNAME=$1
fi

source /etc/docker-hdp-lab.conf
TMP_DOCKER_PS_OUTFILE=/tmp/tmp_showout.txt
TMP_DOCKER_STATS_OUTFILE=/tmp/tmp_docker_stats.txt

if [ "$2" == "online" ]
then
	DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps"
else
	DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
fi

$DOCKER_PS_CMD > $TMP_DOCKER_PS_OUTFILE
docker -H $SWARM_MANAGER:4000 stats --no-stream > $TMP_DOCKER_STATS_OUTFILE
	
echo "----------------------------------------------------------------------------------------------------------------------------"
printf "\e[1m%-12s | %-25s | %-40s | %-15s | %-9s | %-6s |\e[0m\n" UserName ClusterName NodeName IPAddress Mem CPU%
echo "----------------------------------------------------------------------------------------------------------------------------"

if [ "$USERNAME" == "all" ]; then
	echo "Listing nodes from all clusters ..."
	#DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
 	all_users=$($DOCKER_PS_CMD | grep ambari | awk '{print $NF}' | cut -f 1 -d "-" | cut -f 2 -d "/"| sort | uniq)
	num_of_users=$(echo $all_users | wc -w)
	
	for i in $all_users; do
		USERNAME=$i
		__print_cluster_info
	done
	rm -f $TMP_DOCKER_PS_OUTFILE
	exit
fi

# If the show_cluster is run for a specific user:
__print_cluster_info
rm -f $TMP_DOCKER_PS_OUTFILE

