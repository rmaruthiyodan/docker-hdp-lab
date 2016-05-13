FROM centos:6

RUN yum install openssh-server -y
RUN yum install openssh-clients -y
RUN mkdir /root/.ssh
RUN touch /root/.ssh/authorized_keys
RUN chmod 700 /root/.ssh
RUN chmod 400 /root/.ssh/authorized_keys
ADD id_rsa /root/.ssh/
ADD id_rsa.pub /root/.ssh/
RUN echo "hadoop" | passwd --stdin root
RUN chkconfig sshd on
ADD ambari.repo /etc/yum.repos.d/
RUN yum install ambari-agent -y
RUN yum install ambari-server -y
RUN ambari-server setup -s
ADD ./start /
CMD ["/start"]
