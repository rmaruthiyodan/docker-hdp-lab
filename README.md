# docker-hdp-lab

Objective

To achieve the target of building and starting a complete HDP cluster in less than 5 minutes, using Docker based instances.


Introduction

To automate building HDP clusters at such a fast pace, we Run HDP Clusters using Docker based instances, where each docker instance represents a cluster node.
And we prepare ambari-agent and ambari-server images for various releases in addition to maintaining a local HDP repository for all possible versions.
Further, we make use of Ambari blueprints to install and start HDP services in the clusters.


Building a Docker HDP Lab

Multiple Docker Host Machines can be used in a Docker Swarm cluster to provide the required hardware resources to the instances.
Use the following instructions to setup multiple Docker Host machines in a Swarm cluster, using an RHEL 7/Centos 7/OEL 7 server:

(Repeat these steps for all the Docker Host Machines)
1. Install the required Docker packages (refer: https://docs.docker.com/engine/installation/linux/centos/ )

2. Download the docker-hdp-lab setup files:
# git clone https://github.com/rmaruthiyodan/docker-hdp-lab/

3. Place the docker-hdp-lab config file, "docker-hdp-lab.conf" in /etc/

4. Edit the file "/etc/docker-hdp-lab.conf" and set the following properties as appropriate for your environment:
SWARM_MANAGER  -  Defines the Docker Host that will run the Docker Swarm manager instance
LOCAL_REPO_NODE  -  Defines the Docker Host where the local repos will be saved and which will run a httpd instance to serve local repos.
DEFAULT_DOMAIN_NAME  -  This will be the name set for the overlay network
OVERLAY_NETWORK  -  Defines the subnet and the netmask for the overlay network(example: 10.0.1.0/24)
LOCAL_IP  -  Define the IP address of the Docker host 

The SWARM_MANAGER Docker Host will run the following instances as well:
i_ consul instance
ii_ overlay-gatewaynode

4. Check (and config if needed) that all the Docker host machines can resolve each other's hostnames (FQDN) , including its own hostname.

5. Run the "docker-hdp-lab_setup.sh" on all the Docker Host Machines
(this  will install and configure docker-engine, and sets up & starts the Docker Swarm Cluster)

6. Start using the scripts such as "build_image", "create_cluster" , "start_cluster", "stop_cluster", "delete_cluster" and others to manage HDP clusters.
