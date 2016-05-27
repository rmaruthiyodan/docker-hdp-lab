## Docker HDP Lab Cluster

#### Objective

##### To achieve the target of building and starting a complete HDP cluster in less than 5 minutes, using Docker based instances.


#### Introduction

To automate building HDP clusters at such a fast pace, we Run HDP Clusters using Docker based instances, where each docker instance represents a cluster node.
And we prepare ambari-agent and ambari-server images for various releases in addition to maintaining a local HDP repository for all possible versions.
Further, we make use of Ambari blueprints to install and start HDP services in the clusters.


#### Building a Docker HDP Lab

Multiple Docker Host Machines can be used in a Docker Swarm cluster to provide the required hardware resources to the instances.

#####Use the following instructions to setup multiple (or single) Docker Host machines in a Swarm cluster, using an RHEL 7/Centos 7/OEL 7 server


Repeat these steps for all the Docker Host Machines-

*1. Install the required Docker packages
(refer: https://docs.docker.com/engine/installation/linux/centos/ )

*2. Download the docker-hdp-lab setup files:

	git clone https://github.com/rmaruthiyodan/docker-hdp-lab/

*3. Place the config file - "docker-hdp-lab.conf" in /etc/
	cd docker-hdp-lab
	cp docker-hdp-lab.conf /etc/

*4. Edit the configs at "/etc/docker-hdp-lab.conf" and set the following properties as appropriate for your environment:

---

> SWARM_MANAGER  -  Defines the Docker Host that will run the Docker Swarm manager instance.
> LOCAL_REPO_NODE  -  Defines the Docker Host where the local repos will be saved and which will run a httpd instance to serve local repos.
> DEFAULT_DOMAIN_NAME  -  This will be the name set for the overlay network.
> OVERLAY_NETWORK  -  Defines the subnet and the netmask for the overlay network(example: 10.0.1.0/24).
> LOCAL_IP  -  Define the IP address of the Docker host.

>  The SWARM_MANAGER Docker Host will run the following instances as well:
>  i_ consul instance
>  ii_ overlay-gatewaynode

---

*5. Check (and config if needed) that all the Docker host machines can resolve each other's hostnames (FQDN) , including its own hostname.

*6. Run the "install" command:

	# cd docker-hdp-lab
	# ./install.sh
  (this  will install and configure docker-engine, and sets up & starts the Docker Swarm Cluster)


##### At this Stage the setup is completed and let's start using it...


*7. To start with, download the latest Ambari tarball locally:

	# cd /var/www/html/repo ; nohup wget http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.2.2.0/ambari-2.2.2.0-centos6.tar.gz &

	Extract the file once the Download is finished (monitor nohup.out file for the progress)
	# tar -xf ambari-2.2.2.0-centos6.tar.gz


*8. And then run the build_image command
(this step may take more than an hour, but it should be that slow only for the first image build process, since docker images re-uses the layers for the subsequent builds)
Execute:

	# source /etc/docker-hdp-lab.conf

	# nohup ./build_image.sh 2.2.2.0 http://$LOCAL_REPO_NODE/AMBARI-2.2.2.0/centos6/2.2.2.0-460/ &

Monitor "nohup.out" for completion. It will take more than an hour for the first image. And the subsequent image builds will be faster since it would use the existing layers.


*9. Edit cluster.props file and create your first cluster:

	# create_cluster.sh cluster.props
To make the deployment even more faster, use local HDP repositories and specify their location inside "cluster.props" file


*10. To see the list of Nodes & their IPs in your cluster run either of the below commands:

	# show_cluster.sh all

	Or

	# show_cluster.sh <username>  
	
*11. Add route on your laptop/desktop to reach the Instance IPs directly, so that UIs such as Ambari or RM/NN UI can be opened in the local browser

	Example: # route add -net 10.0.5.0/24 $SWARM_MANAGER_IP  
	Or 
	Use ssh tunnels:   ssh -L 8080:10.0.5.5:8080 $SWARM_MANAGER_IP  
	& use the broswer to open Ambari UI at http://127.0.0.1:8080

*12. Start using the scripts such as "start_cluster", "stop_cluster", "delete_cluster" and others to manage HDP clusters.

#####	Happy HDP'ing \o/


Tip:  Create an ssh alias as follows, in order to avoid repeatedly updating HostKeys in known_hosts file and the warnings:

	alias ssh='ssh -o CheckHostIP=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
