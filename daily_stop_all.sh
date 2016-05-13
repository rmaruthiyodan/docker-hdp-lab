#!/bin/bash
########
#Author: Ratish Maruthiyodan
#Project: Docker HDP Lab
########

__daily_stop_cluster() {

  for cluster_name in $($DOCKER_PS_CMD| grep "\/$USERNAME-" | awk -F "/" '{print $NF}' | cut -f 2 -d"-" | sort | uniq)
  do
    grep -q $USERNAME-$cluster_name $CLEAN_UP_EXCEPTION_FILE
    if [ $? -gt 0 ]
    then
      echo -e "\nCluster:: $USERNAME-$cluster_name" >> /tmp/daily_delete_$(date +%d-%b-%y)
      
      for node_name in $($DOCKER_PS_CMD | grep "$USERNAME-" | grep "\-$cluster_name-" | awk -F "/" '{print $NF}' | cut -f 3-8 -d"-")
      do
        INSTANCE_NAME=$USERNAME-$cluster_name-$node_name
        echo "Deleting Instance:: $USERNAME-$cluster_name-$node_name" >> /tmp/daily_delete_$(date +%d-%b-%y)
        echo "docker -H $SWARM_MANAGER:4000 kill $INSTANCE_NAME"

      done
    else
      echo -e "\nExempted:: $USERNAME-$cluster_name" >> /tmp/daily_delete_$(date +%d-%b-%y)
    fi
   done
}


SWARM_MANAGER="altair"
CLEAN_UP_EXCEPTION_FILE="/opt/maggie/daily_exception_list_for_stop"
echo > /tmp/daily_delete_$(date +%d-%b-%y)
DOCKER_PS_CMD="docker -H $SWARM_MANAGER:4000 ps"

 	all_users=$($DOCKER_PS_CMD | grep ambari | awk '{print $NF}' | cut -f 1 -d "-" | cut -f 2 -d "/"| sort | uniq)
	num_of_users=$(echo $all_users | wc -w)

	for i in $all_users; do
		USERNAME=$i
		__daily_stop_cluster
	done
	exit
fi
