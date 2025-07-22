# Cloud Workflow for Analytics Processing
# This workflow performs automated analytics on traffic data and routing decisions

main:
  params: [args]
  steps:
    - initialize:
        assign:
          - project_id: "${project_id}"
          - dataset_name: "${dataset_name}"
          - current_time: $${time.format(sys.now())}
        
    - log_start:
        call: sys.log
        args:
          text: $${"Starting analytics processing at " + current_time}
          severity: INFO

    - analyze_traffic_patterns:
        call: http.post
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/jobs"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            configuration:
              query:
                query: |
                  SELECT 
                    target_service,
                    COUNT(*) as total_requests,
                    AVG(response_time) as avg_response_time,
                    STDDEV(response_time) as response_time_stddev,
                    MIN(response_time) as min_response_time,
                    MAX(response_time) as max_response_time,
                    AVG(CASE WHEN status_code BETWEEN 200 AND 299 THEN 1 ELSE 0 END) as success_rate,
                    COUNTIF(status_code >= 400) as error_count
                  FROM `${project_id}.${dataset_name}.lb_metrics`
                  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)
                  GROUP BY target_service
                  ORDER BY total_requests DESC
                useLegacySql: false
                useQueryCache: true
        result: traffic_analysis_job

    - wait_for_traffic_analysis:
        call: http.get
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/jobs/" + traffic_analysis_job.body.jobReference.jobId}
          auth:
            type: OAuth2
        result: traffic_job_status
        
    - check_traffic_job_complete:
        switch:
          - condition: $${traffic_job_status.body.status.state == "DONE"}
            next: get_traffic_results
          - condition: $${traffic_job_status.body.status.state == "RUNNING"}
            next: wait_traffic_job
        next: traffic_job_error

    - wait_traffic_job:
        call: sys.sleep
        args:
          seconds: 2
        next: wait_for_traffic_analysis

    - get_traffic_results:
        call: http.get
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/jobs/" + traffic_analysis_job.body.jobReference.jobId + "/results"}
          auth:
            type: OAuth2
        result: traffic_results

    - analyze_routing_decisions:
        call: http.post
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/jobs"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            configuration:
              query:
                query: |
                  SELECT 
                    target_service,
                    COUNT(*) as decision_count,
                    AVG(confidence_score) as avg_confidence,
                    MIN(confidence_score) as min_confidence,
                    MAX(confidence_score) as max_confidence,
                    STDDEV(confidence_score) as confidence_stddev,
                    COUNT(DISTINCT LEFT(source_criteria, 20)) as unique_sources
                  FROM `${project_id}.${dataset_name}.routing_decisions`
                  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)
                  GROUP BY target_service
                  ORDER BY decision_count DESC
                useLegacySql: false
                useQueryCache: true
        result: routing_analysis_job

    - wait_for_routing_analysis:
        call: http.get
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/jobs/" + routing_analysis_job.body.jobReference.jobId}
          auth:
            type: OAuth2
        result: routing_job_status
        
    - check_routing_job_complete:
        switch:
          - condition: $${routing_job_status.body.status.state == "DONE"}
            next: get_routing_results
          - condition: $${routing_job_status.body.status.state == "RUNNING"}
            next: wait_routing_job
        next: routing_job_error

    - wait_routing_job:
        call: sys.sleep
        args:
          seconds: 2
        next: wait_for_routing_analysis

    - get_routing_results:
        call: http.get
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/jobs/" + routing_analysis_job.body.jobReference.jobId + "/results"}
          auth:
            type: OAuth2
        result: routing_results

    - generate_insights:
        assign:
          - insights: {}
          - traffic_data: $${traffic_results.body.rows}
          - routing_data: $${routing_results.body.rows}
          
    - process_traffic_insights:
        for:
          value: row
          in: $${traffic_data}
          steps:
            - extract_traffic_metrics:
                assign:
                  - service_name: $${row.f[0].v}
                  - total_requests: $${int(row.f[1].v)}
                  - avg_response_time: $${double(row.f[2].v)}
                  - success_rate: $${double(row.f[7].v)}
                  
            - categorize_performance:
                switch:
                  - condition: $${avg_response_time < 0.5 and success_rate > 0.95}
                    assign:
                      - performance_category: "excellent"
                  - condition: $${avg_response_time < 1.0 and success_rate > 0.9}
                    assign:
                      - performance_category: "good"
                  - condition: $${avg_response_time < 2.0 and success_rate > 0.8}
                    assign:
                      - performance_category: "acceptable"
                  - condition: true
                    assign:
                      - performance_category: "needs_attention"
                      
            - log_service_performance:
                call: sys.log
                args:
                  text: $${"Service " + service_name + " performance: " + performance_category + " (avg_time: " + string(avg_response_time) + "s, success: " + string(success_rate) + ")"}
                  severity: INFO

    - process_routing_insights:
        for:
          value: row
          in: $${routing_data}
          steps:
            - extract_routing_metrics:
                assign:
                  - service_name: $${row.f[0].v}
                  - decision_count: $${int(row.f[1].v)}
                  - avg_confidence: $${double(row.f[2].v)}
                  
            - evaluate_routing_quality:
                switch:
                  - condition: $${avg_confidence > 0.8}
                    assign:
                      - routing_quality: "high_confidence"
                  - condition: $${avg_confidence > 0.6}
                    assign:
                      - routing_quality: "medium_confidence"
                  - condition: true
                    assign:
                      - routing_quality: "low_confidence"
                      
            - log_routing_quality:
                call: sys.log
                args:
                  text: $${"Service " + service_name + " routing quality: " + routing_quality + " (decisions: " + string(decision_count) + ", confidence: " + string(avg_confidence) + ")"}
                  severity: INFO

    - create_recommendations:
        assign:
          - recommendations: []
          
    - add_performance_recommendations:
        for:
          value: row
          in: $${traffic_data}
          steps:
            - check_performance_issues:
                assign:
                  - service_name: $${row.f[0].v}
                  - avg_response_time: $${double(row.f[2].v)}
                  - success_rate: $${double(row.f[7].v)}
                  
            - generate_recommendation:
                switch:
                  - condition: $${avg_response_time > 2.0}
                    assign:
                      - recommendations: $${list.concat(recommendations, ["Consider optimizing " + service_name + " for better response times (current: " + string(avg_response_time) + "s)"])}
                  - condition: $${success_rate < 0.9}
                    assign:
                      - recommendations: $${list.concat(recommendations, ["Investigate error rates for " + service_name + " (success rate: " + string(success_rate) + ")"])}

    - log_final_insights:
        call: sys.log
        args:
          text: $${"Analytics complete. Generated " + string(len(recommendations)) + " recommendations"}
          severity: INFO

    - log_recommendations:
        for:
          value: recommendation
          in: $${recommendations}
          steps:
            - log_recommendation:
                call: sys.log
                args:
                  text: $${"Recommendation: " + recommendation}
                  severity: INFO

    - return_results:
        return:
          status: "success"
          timestamp: $${current_time}
          traffic_analysis:
            total_services_analyzed: $${len(traffic_data)}
            routing_decisions_analyzed: $${len(routing_data)}
          recommendations: $${recommendations}
          insights:
            message: "Traffic analytics processing completed successfully"
            data_sources: ["lb_metrics", "routing_decisions"]
            analysis_window: "15 minutes"

    # Error handling steps
    - traffic_job_error:
        call: sys.log
        args:
          text: $${"Traffic analysis job failed: " + string(traffic_job_status.body)}
          severity: ERROR
        next: return_error

    - routing_job_error:
        call: sys.log
        args:
          text: $${"Routing analysis job failed: " + string(routing_job_status.body)}
          severity: ERROR
        next: return_error

    - return_error:
        return:
          status: "error"
          timestamp: $${current_time}
          error_message: "Analytics processing failed"
          recommendations: ["Check BigQuery dataset and table permissions", "Verify data availability in recent time window"]