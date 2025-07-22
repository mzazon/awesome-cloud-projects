[SERVICE]
    Flush                     5
    Grace                     30
    Log_Level                 ${log_level}
    Daemon                    off
    Parsers_File              parsers.conf
    HTTP_Server               On
    HTTP_Listen               0.0.0.0
    HTTP_Port                 2020
    storage.path              /var/fluent-bit/state/flb-storage/
    storage.sync              normal
    storage.checksum          off
    storage.backlog.mem_limit 5M

[INPUT]
    Name                tail
    Tag                 application.*
    Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
    Path                /var/log/containers/*.log
    multiline.parser    docker, cri
    DB                  /var/fluent-bit/state/flb_container.db
    Mem_Buf_Limit       ${mem_buf_limit}
    Skip_Long_Lines     On
    Refresh_Interval    10
    Rotate_Wait         30
    storage.type        filesystem
    Read_from_Head      ${read_from_head ? "On" : "Off"}

[INPUT]
    Name                tail
    Tag                 dataplane.systemd.*
    Path                /var/log/journal
    multiline.parser    docker, cri
    DB                  /var/fluent-bit/state/flb_journal.db
    Mem_Buf_Limit       25MB
    Skip_Long_Lines     On
    Refresh_Interval    10
    Read_from_Head      ${read_from_head ? "On" : "Off"}

[FILTER]
    Name                kubernetes
    Match               application.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_Tag_Prefix     application.var.log.containers.
    Merge_Log           On
    Merge_Log_Key       log_processed
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off
    Labels              Off
    Annotations         Off
    Use_Kubelet         On
    Kubelet_Port        10250
    Buffer_Size         0

[OUTPUT]
    Name                cloudwatch_logs
    Match               application.*
    region              ${aws_region}
    log_group_name      /aws/containerinsights/${cluster_name}/application
    log_stream_prefix   $${kubernetes_namespace_name}-
    auto_create_group   On
    extra_user_agent    container-insights

[OUTPUT]
    Name                cloudwatch_logs
    Match               dataplane.systemd.*
    region              ${aws_region}
    log_group_name      /aws/containerinsights/${cluster_name}/dataplane
    log_stream_prefix   $${hostname}-
    auto_create_group   On
    extra_user_agent    container-insights