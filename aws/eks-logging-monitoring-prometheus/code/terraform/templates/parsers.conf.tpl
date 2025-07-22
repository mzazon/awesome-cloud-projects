[PARSER]
    Name                docker
    Format              json
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L
    Time_Keep           On

[PARSER]
    Name                cri
    Format              regex
    Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L%z

[PARSER]
    Name                syslog
    Format              regex
    Regex               ^\<(?<pri>[0-9]+)\>(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$
    Time_Key            time
    Time_Format         %b %d %H:%M:%S

[PARSER]
    Name                container_firstline
    Format              regex
    Regex               (?<log>(?<="log":")\S(?:[^"\\]|\\.)*).*(?<stream>(?<="stream":")(?:stdout|stderr)).*(?<time>\d{4}-\d{1,2}-\d{1,2}T\d{2}:\d{2}:\d{2}\.\w*).*(?=})
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L
    Time_Keep           On

[PARSER]
    Name                cwlogs
    Format              json
    Time_Key            timestamp
    Time_Format         %Y-%m-%dT%H:%M:%S.%L