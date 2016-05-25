#!/bin/bash
########
#Author: Ratish Maruthiyodan
#Project: Docker HDP Lab
########

#set -x

source /etc/docker-hdp-lab.conf

SWARM_MANAGER_IP=$(getent ahosts $SWARM_MANAGER | head -n 1 | awk '{print $1}')
CONSUL_MANAGER=$SWARM_MANAGER_IP

if [ ! -e /root/.ssh/id_rsa ] || [  ! -e /root/.ssh/id_rsa.pub ]
then
	ssh-keygen
fi

yum update -y
echo "1" > /proc/sys/net/ipv4/ip_forward

### Setup Docker repo
tee /tmp/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

yum install -y docker-engine

chkconfig docker on
if [ -z $LOCAL_IP ]
then
	LOCAL_IP=$(getent ahosts $HOSTNAME | head -n 1 | awk '{print $1}')
fi

sed -i "/ExecStart=/c\ExecStart=\/usr\/bin\/docker daemon -H tcp\:\/\/$LOCAL_IP:2375  -H unix:\/\/\/var\/run\/docker.sock --cluster-store=consul\:\/\/$CONSUL_MANAGER:8500 --cluster-advertise=$LOCAL_IP\:2375" /etc/systemd/system/multi-user.target.wants/docker.service
sed -i "/ExecStart=/c\ExecStart=\/usr\/bin\/docker daemon -H tcp\:\/\/$LOCAL_IP:2375  -H unix:\/\/\/var\/run\/docker.sock --cluster-store=consul\:\/\/$CONSUL_MANAGER:8500 --cluster-advertise=$LOCAL_IP\:2375" /usr/lib/systemd/system/docker.service
systemctl daemon-reload
service docker start

if [ $SWARM_MANAGER == $HOSTNAME ]
then
	echo -e "\n\tStarting Consul instance (takes a few seconds to start)"
	docker run -d -p 8500:8500 --name=consul progrium/consul -server -bootstrap
	echo "docker start consul" >> /etc/rc.local
	sleep 10
	echo -e "\n\tStarting swarm manager and then 20s sleep"
	docker run -d -p 4000:4000 --name=swarm_manager swarm manage -H :4000 --replication --advertise $LOCAL_IP:4000 consul://$CONSUL_MANAGER:8500
	#echo "sleep 10" >> /etc/rc.local
	#echo "docker start swarm_manager" >> /etc/rc.local

	sleep 20

	echo -e "\n\tStarting Swarm join and 10s sleep"
	docker run --name=swarm_join  -d swarm join --advertise=$LOCAL_IP:2375 consul://$CONSUL_MANAGER:8500
	#echo "sleep 10" >> /etc/rc.local
	#echo "docker start swarm_join" >> /etc/rc.local
	sleep 10
	echo -e "\n \t Creating Overlay network..."
	docker -H $SWARM_MANAGER_IP:4000 network create --driver overlay --subnet=$OVERLAY_NETWORK $DEFAULT_DOMAIN_NAME
	mkdir /tmp/gateway-instance

	cat > /tmp/gateway-instance/start << EOF
service sshd restart
service dnsmasq restart
/usr/sbin/sshd -d -p 2222
EOF
	chmod +x  /tmp/gateway-instance/start
	cat > /tmp/gateway-instance/Dockerfile << EOF
FROM centos:6
RUN yum install openssh-server -y
RUN yum install openssh-clients -y
RUN yum install dnsmasq -y
RUN echo "hadoop" | passwd --stdin root
RUN chkconfig sshd on
RUN mkdir /root/.ssh
RUN touch /root/.ssh/authorized_keys
RUN chmod 700 /root/.ssh
RUN chmod 400 /root/.ssh/authorized_keys
ADD ./start /
CMD ["/start"]
EOF
	echo -e "\n\t Building images for Overlay network gateway...\n"
	docker build -t gatewaynode /tmp/gateway-instance/
	sleep 5
	docker run -d --hostname overlay-gatewaynode --name overlay-gatewaynode  --net $DEFAULT_DOMAIN_NAME --net-alias=overlay-gatewaynode  --privileged gatewaynode
	OVERLAY_GATEWAY_IP=$(docker exec overlay-gatewaynode hostname -i | awk '{print $2}')
	route add -net $OVERLAY_NETWORK gw $OVERLAY_GATEWAY_IP


else
        docker run -d swarm join --advertise=$LOCAL_IP:2375 consul://$CONSUL_MANAGER:8500
	route add -net $OVERLAY_NETWORK gw $SWARM_MANAGER_IP
fi

if [ $LOCAL_REPO_NODE == $HOSTNAME  ]
then
	docker run -d --hostname localrepo --name localrepo --privileged -v /var/www/html/repo:/var/www/html httpd:2.4
fi
