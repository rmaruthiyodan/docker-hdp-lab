#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: Used for displaying Cluster Nodes and their IPs
########

__get_ambari_version() {
	INSTANCE_NAME=$1
	echo $(docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME ambari-agent --version)
}

__get_hdp_version() {
	INSTANCE_NAME=$1
	hadoopver=$(docker -H $SWARM_MANAGER:4000 exec $INSTANCE_NAME hadoop version 2> /dev/null | head -n1 | awk '{print $2}')
	echo ${hadoopver:6}
}

__print_cluster_info() {
	#echo $USERNAME
	printf "%-12s | %-25s | %-40s | %-15s | %-5s %-4s | %-7s |\n" $USERNAME $junk $junk $junk  $junk $junk
	for cluster_name in $(cat $TMP_DOCKER_PS_OUTFILE | grep "\/$USERNAME\-" | awk -F "/" '{print $NF}' | cut -f 2 -d"-" | sort | uniq)
	do
#		echo -e "\n\t" "$(tput setaf 1)[ $cluster_name ]$(tput sgr 0)"
		lease_time_epoch=$(cat /opt/docker_cluster/cluster_lease | grep "$USERNAME-$cluster_name" | awk '{print $2}')
		lease_time=$(date -d "@$lease_time_epoch" +"%Y-%m-%d %H:%M" 2> /dev/null)
		if [ ! -z "$lease_time" ]; then lease_time="Expires after: "$lease_time ; fi

		printf "%-12s |\e[31m %-25s \e[0m|\e[31m %-40s \e[0m| %-15s | %-5s %-4s | %-7s |\e[0m\n" "" $cluster_name "$lease_time" - - - -
		version_printed_fl=0
		for node_name in $(cat $TMP_DOCKER_PS_OUTFILE | grep "\/$USERNAME-" | grep "\-$cluster_name-" | awk -F "/" '{print $NF}' | cut -f 3-8 -d"-")
		do
			INSTANCE_NAME=$USERNAME-$cluster_name-$node_name
			if [  "$(docker -H $SWARM_MANAGER:4000 inspect -f {{.State.Running}} $INSTANCE_NAME)" == "false" ]; then 
			  IP="(OFFLINE)"
			  FQDN=$node_name
			  CPU="0"
			  MEM="0"
			  MEM_UNIT="-"
			else
			  echo $INSTANCE_NAME | grep -q -i "ambari-server"
			  if [ "$?" -ne 0 ] && [ "$version_printed_fl" -eq 0 ] && [ "$VERSION_OPTION" -ne 0 ]
			  then
				amb_version=`echo Ambari:$(__get_ambari_version $INSTANCE_NAME)`
				hdp_version=`echo HDP:$(__get_hdp_version $INSTANCE_NAME)`
				print_version=$amb_version
				version_printed_fl=2
			  elif [ "$version_printed_fl" -eq 2 ]
			  then
                                print_version=$hdp_version
				version_printed_fl=1
			  else
				print_version=" "
                          fi

			  IP=`docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $INSTANCE_NAME`
	        	  HOST_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $INSTANCE_NAME`
		          DOMAIN_NAME=`docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $INSTANCE_NAME`
			  FQDN=$HOST_NAME.$DOMAIN_NAME
			  INSTANCE_ID=$(grep $INSTANCE_NAME $TMP_DOCKER_PS_OUTFILE | awk '{print $1}')

			  read CPU MEM MEM_UNIT <<< $(grep $INSTANCE_ID $TMP_DOCKER_STATS_OUTFILE| tail -n1| awk '{print $2 , $3 , $4}')
			 # docker -H $SWARM_MANAGER:4000 stats --no-stream $INSTANCE_NAME | tail -n1| awk '{print $2 $3 $4}' | read CPU MEM MEM_UNIT 
			  #IPADDR=$(docker -H $SWARM_MANAGER:4000 inspect INSTANCE_NAME | grep -i  "ipaddress" | grep 10 | xargs)
			fi
 		#	echo -e "\t \t $(tput setaf 2) $FQDN  -->    $IP $(tput sgr 0)"
			if [ "$MEM_UNIT" == "GB" ] && (( $(echo "$MEM" \> 5 | bc -l) ))
			then
				if (( $(echo `echo "$CPU"| cut -d "%" -f1` \> 70 | bc -l) ))
				then
				   printf "%-12s | %-25s |\e[32m %-40s \e[0m| %-15s |\e[31;1m %-5s %-4s\e[0m |\e[31;1m %-7s \e[0m|\n" "" "$print_version"  $FQDN $IP  $MEM $MEM_UNIT $CPU
				else
				   printf "%-12s | %-25s |\e[32m %-40s \e[0m| %-15s |\e[31;1m %-5s %-4s\e[0m |\e[32m %-7s \e[0m|\n" "" "$print_version"  $FQDN $IP  $MEM $MEM_UNIT $CPU
				fi
			else
				if (( $(echo `echo "$CPU"| cut -d "%" -f1` \> 70 | bc -l) ))
				then
				   printf "%-12s | %-25s |\e[32m %-40s \e[0m| %-15s | \e[32m%-5s %-4s\e[0m |\e[31;1m %-7s \e[0m|\n" "" "$print_version"  $FQDN $IP  $MEM $MEM_UNIT $CPU
				else
				   printf "%-12s | %-25s |\e[32m %-40s \e[0m| %-15s |\e[32m %-5s %-4s\e[0m |\e[32m %-7s\e[0m |\n" "" "$print_version"  $FQDN $IP  $MEM $MEM_UNIT $CPU
				fi	
			fi
		done	  
	#	printf "%-12s |--------------------------------------------------------------------------------------------------------- \n" ""
	done
	echo "-----------------------------------------------------------------------------------------------------------------------------"
}


#set -x
if [ $# -lt 1 ];then
 echo "Usage:: show_cluster.sh < all | username > [online] [version]"
 echo "Displaying cluster for the current user " $USER
 USERNAME=$USER
else
 USERNAME=$1
fi

source /etc/docker-hdp-lab.conf
TMP_DOCKER_PS_OUTFILE=/tmp/$USER_showout_$(date +%d-%m-%y-%H-%M-%S).txt
TMP_DOCKER_STATS_OUTFILE=/tmp/$USER_docker_stats_$USERNAME.txt

if [ "$2" == "online" ]
then
	DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps"
else
	DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
fi

if [ "$2" == "version" ] || [ "$3" == "version" ]
then
	VERSION_OPTION=1
else
	VERSION_OPTION=0
fi

$DOCKER_PS_CMD > $TMP_DOCKER_PS_OUTFILE
echo -e "\nObtaining Stats..."
timeout 3s docker -H $SWARM_MANAGER:4000 stats > $TMP_DOCKER_STATS_OUTFILE
	
echo "-----------------------------------------------------------------------------------------------------------------------------"
printf "\e[1m%-12s | %-25s | %-40s | %-15s | %-5s %-4s | %-7s |\e[0m\n" UserName ClusterName NodeName IPAddress Mem "" CPU%
echo "-----------------------------------------------------------------------------------------------------------------------------"

if [ "$USERNAME" == "all" ]; then
	#DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps -a"
 	all_users=$($DOCKER_PS_CMD | grep ambari | awk '{print $NF}' |  cut -f 2 -d "/"| cut -f 1 -d "-"| sort | uniq)
	num_of_users=$(echo $all_users | wc -w)
	
	for i in $all_users; do
		USERNAME=$i
		__print_cluster_info
	done
	rm -f $TMP_DOCKER_PS_OUTFILE
	rm -f $TMP_DOCKER_STATS_OUTFILE
	exit
fi

# If the show_cluster is run for a specific user:
__print_cluster_info
rm -f $TMP_DOCKER_PS_OUTFILE
rm -f $TMP_DOCKER_STATS_OUTFILE
