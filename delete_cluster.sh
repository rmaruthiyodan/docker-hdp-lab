#!/bin/bash
docker -H altair:4000 rm $(docker -H altair:4000 ps -a | grep $1 | awk -F "/" '{print $NF}')
