#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Maggie Cluster
########

if [ $# -lt 1 ]
then
        echo -e "\n\nUsage : maggie_cluster -<Verb> [<arg>]"
	echo -e "Options: \n\n\t -create_cluster <Cluster properties file>>\n\n\t -start_cluster <username-clustername> \n\n\t -add_clusternode <username-clustername> <nodename.domain> \n\n\t -show_cluster <all|username> [online] \n\n\t -stop_cluster <username-clustername>\n\n\t -delete_cluster <username-clustername>\n\n\t -build_ambari_image <Ambari Version> <Base URL> \n\n\t -download_hdp <url>\n"
        exit
fi

VERB=$1

case "$VERB" in

-create_cluster) create_cluster $2
		 ;;
-start_cluster) start_cluster $2
		;;
-add_clusternode) add_clusternode $2 $3
		;;
-show_cluster) show_cluster $2 $3
		;;
-stop_cluster) stop_cluster $2
		;;
-delete_cluster) delete_cluster $2
		;;
-build_image) build_ambari_image $2 $3
		;;
-download_hdp) download_hdp $2
		;;
*) echo "Invalid Verb"
	;;
esac
