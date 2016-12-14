#!/bin/bash
#Author: Ratish Maruthiyodan
#Purpose: Prepare the ambari.props file and call setup_kerberos
#############

__find_kerberos_clients() {
	for i in $(docker -H $SWARM_MANAGER:4000 ps | grep "\/$USERNAME_CLUSTERNAME-" | awk -F "/" '{print $NF}')
	do
		echo $i | grep -q -i ambari-server
		if [ $? -ne 0 ]
		then
			INSTANCE_NAME=$i
			HOST_NAME=$(docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $INSTANCE_NAME)
		        DOMAIN_NAME=$(docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $INSTANCE_NAME)
			if [ -z "$KERBEROS_CLIENTS" ]
			then
				KERBEROS_CLIENTS="$HOST_NAME.$DOMAIN_NAME"
			else
				KERBEROS_CLIENTS="$HOST_NAME.$DOMAIN_NAME,$KERBEROS_CLIENTS"
			fi
		fi
	done

}

__find_ambari_server_IP() {
    AMBARI_SERVER=$(docker -H $SWARM_MANAGER:4000 ps -a | grep -i "\/$USERNAME_CLUSTERNAME-ambari-server" | awk -F "/" '{print $NF}')
    AMBARI_SERVER_IP=$(docker -H $SWARM_MANAGER:4000 inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $AMBARI_SERVER)
    HOST_NAME=$(docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Hostname}}' $AMBARI_SERVER)
    DOMAIN_NAME=$(docker -H $SWARM_MANAGER:4000 inspect --format='{{.Config.Domainname}}' $AMBARI_SERVER)
    AMBARI_HOST=$HOST_NAME.$DOMAIN_NAME

}

__validate_clustername() {
        docker -H $SWARM_MANAGER:4000 ps -a | grep -q "\/$USERNAME_CLUSTERNAME-"
        if [ $? -ne 0 ]
        then
                echo -e "\n\t$(tput setaf 1)Cluster doesn't exist with the name: $USERNAME_CLUSTERNAME. Check the given <username-clustername> and try again $(tput sgr 0)\n"
                exit
        fi
}

__copy_config_and_run(){
	scp /tmp/$USERNAME_CLUSTERNAME-kerb.out root@$AMBARI_SERVER_IP:/root
	scp /opt/docker_cluster/manage_cluster/Kerberos_setup/setup_kerberos.sh root@$AMBARI_SERVER_IP:/root
	ssh root@$AMBARI_SERVER_IP mv /root/$USERNAME_CLUSTERNAME-kerb.out /root/ambari.props
	ssh root@$AMBARI_SERVER_IP chmod 777 /root/setup_kerberos.sh
	ssh root@$AMBARI_SERVER_IP nohup /root/setup_kerberos.sh > /tmp/enable_kerberos.out 2>&1 &
}



# public static void main  :)
LOC=`pwd`

if [ -z $2 ]
then
	echo "Usage:: $0 user-cluster REALM"
	exit 1
fi

source /etc/docker-hdp-lab.conf

USERNAME_CLUSTERNAME=$1
__validate_clustername


__find_ambari_server_IP

__find_kerberos_clients

REALM=$(echo $2 | awk '{print toupper($0)}')
CLUSTER_NAME=$(echo $USERNAME_CLUSTERNAME | awk -F "-" '{print $2}')
AMBARI_ADMIN_USER=admin
AMBARI_ADMIN_PASSWORD=admin

echo "Using Realm as /'$REALM/'"
echo "CLUSTER_NAME=$CLUSTER_NAME" > /tmp/$USERNAME_CLUSTERNAME-kerb.out
echo "AMBARI_ADMIN_USER=$AMBARI_ADMIN_USER" >>  /tmp/$USERNAME_CLUSTERNAME-kerb.out
echo "AMBARI_ADMIN_PASSWORD=$AMBARI_ADMIN_PASSWORD" >>  /tmp/$USERNAME_CLUSTERNAME-kerb.out
echo "AMBARI_HOST=$AMBARI_HOST" >>  /tmp/$USERNAME_CLUSTERNAME-kerb.out
echo "KDC_HOST=$AMBARI_HOST" >>  /tmp/$USERNAME_CLUSTERNAME-kerb.out
echo "REALM=$REALM" >>  /tmp/$USERNAME_CLUSTERNAME-kerb.out
echo "KERBEROS_CLIENTS=$KERBEROS_CLIENTS" >>  /tmp/$USERNAME_CLUSTERNAME-kerb.out

__copy_config_and_run

exit 0
# end
