#!/bin/bash
docker -H altair:4000 kill $(docker -H altair:4000 ps | grep $1 | awk -F "/" '{print $NF}')
