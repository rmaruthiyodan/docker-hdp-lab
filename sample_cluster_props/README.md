## Ambari Metric Server Tools

#### 1) Count the metric types received by AMS (ams_metrics_type_count.sh)
- Purpose: While working on AMS performance issues, one of the required information to be collected is the count of types of metrics received from various components during every iteration.  
The script accepts AMS metrics metadata as input, in json format and produces an output that tells us the count of different types of metrics that are received from various HDP components. Ref: https://hortonworks.jira.com/browse/BUG-71434

- Input  : Capture AMS metadata, using the following AMS API and redirect to a file:  
    curl http://<AMS-Collector-Host>:6188/ws/v1/timeline/metrics/metadata > ams_meta.out

- Usage  :  # ams_metrics_type_count.sh ams_meta.out

Sample Output :  

    $ ./ams_metrics_type_count.sh ams_metrics_metadata.out 
    Input File: ams_metrics_metadata.out  
    hivemetastore : 682278  
    kafka_broker : 1588  
    hbase : 985  
    ams-hbase : 866 
    hiveserver2 : 728 
    datanode : 305 
    resourcemanager : 273 
    namenode : 263 
    nodemanager : 242 
    HOST : 157 
    journalnode : 102 
    applicationhistoryserver : 84 
    jobhistoryserver : 60 
    accumulo : 23 
    nimbus : 7 
    timeline_metric_store_watcher : 1  

- Note : This output tells us the number of different types of metrics that are received from various components. In this case, HiveMetastore was sending 682278 types of metrics at every interval and the AMS performance issue was resolved by removing hive table level metrics.
