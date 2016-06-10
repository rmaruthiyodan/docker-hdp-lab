#!/bin/bash
########
# Author: Ratish Maruthiyodan
# Project: Docker HDP Lab
# Description: The script localizes HDP repositories in /var/www/html/repos on the $LOCAL_REPO server
########

__download_tarball()
{
        cd /var/www/html/repos
        nohup wget $2 > /tmp/localize_$HDPVER_download.out &
        sleep 10
        tail /tmp/localize_$HDPVER_download.out | grep -e "saved"
        while [ $? -ne 0 ]
        do
                sleep 60
                tail /tmp/localize_$HDPVER_download.out | grep -e "saved"
        done

}

__extract_and_update_repofile()
{
        hdptar=$(tail /tmp/localize_$HDPVER_download.out | grep saved | cut -d "‘" -f 2 | cut -d "’" -f 1)
        nohup tar -xvf $hdptar > /tmp/localize_$HDPVER_tar-extract.out
        REPODATA_DIR=$(find `head -n1 /tmp/localize_$HDPVER_tar-extract.out` -name repodata)
        BASE_URL=$LOCAL_REPO_NODE/$REPODATA_DIR
        echo "HDP_$HDPVER_BASE_URL=\"http://$BASE_URL\"" >> /opt/docker_cluster/localrepo_baseurl
        echo -e "\n\tAdded:: HDP_$HDPVER_BASE_URL=\"http://$BASE_URL\" in /opt/docker_cluster/localrepo_baseurl"
        echo -e "HDP Localization for $HDPVER is now Complete"
}


source /etc/docker-hdp-lab.conf

if [ "$LOCAL_REPO_NODE" != $HOSTNAME ] && [ "$LOCAL_REPO_NODE" != `hostname -s` ] &&  [ "$LOCAL_REPO_NODE" != `hostname -f` ]
then
	echo -e "\nThis is not the Local repo Node. \nPlease run this command on the node defined as LOCAL_REPO_NODE in /etc/docker-hdp-lab.conf\n"
	exit 1
fi

if [ $# -ne 2 ];then
 echo -e "\nInvalid Number of Argument(s)"
 echo "Usage::  localize_hdp.sh <HDP Version> http://<HDP Repository Tarball URL>"
 echo -e "\nExamples:: $(tput setaf 1)"
 echo -e "\tlocalize_hdp.sh 2.4.2.0 http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.4.2.0/HDP-2.4.2.0-centos6-rpm.tar.gz"
 echo -e "\tlocalize_hdp.sh 2.4.0.0 http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.4.0.0/HDP-2.4.0.0-centos6-rpm.tar.gz"
 echo -e "\tlocalize_hdp.sh 2.3.4.7 http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.3.4.7/HDP-2.3.4.7-centos6-rpm.tar.gz"
 echo -e "\tlocalize_hdp.sh 2.3.4.0 http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.3.4.0/HDP-2.3.4.0-centos6-rpm.tar.gz"
 echo -e "\tlocalize_hdp.sh 2.3.2.0 http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.3.2.0/HDP-2.3.2.0-centos6-rpm.tar.gz"
 echo -e "\tlocalize_hdp.sh 2.2.8.0 http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.2.8.0/HDP-2.2.8.0-centos6-rpm.tar.gz"
 echo -e "$(tput sgr 0)\n\n"

 exit 1
fi

if [ $( echo $1 | egrep '[^.0-9]')  ]
then
  echo -e "\nThe first argument should be HDP version. For example: 2.4.2.0"
  echo -e "Usage::  localize_hdp.sh <HDP Version> http://<HDP Repository Tarball URL>\n"
  read "Is the HDP URL correct & Do you want to continue ? [Y/N]" choice
  if [ "$choice" != "Y" ] && [ "$choice" != "y" ]
  then
        exit 1
  fi
fi

HDPVER=$1
__download_tarball
__extract_and_update_repofile

