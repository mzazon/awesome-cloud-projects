main:
  params: [args]
  steps:
  - init:
      assign:
      - intent: $${args.intent}
      - action: $${args.action}
      - parameters: $${args.parameters}
      - project_id: "$${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}"
      - region: "${region}"
      - queue_name: "${queue_name}"
      - task_processor_url: "${"https://" + region + "-" + project_id + ".cloudfunctions.net/${task_processor_function}"}"
      
  - validate_intent:
      switch:
      - condition: $${intent == "create_task"}
        next: create_task_process
      - condition: $${intent == "schedule_task"}
        next: schedule_task_process
      - condition: $${intent == "generate_report"}
        next: generate_report_process
      default:
        next: unknown_intent_error

  - create_task_process:
      steps:
      - log_task_creation:
          call: sys.log
          args:
            text: $${"Creating task with parameters: " + string(parameters)}
            severity: INFO
            
      - enqueue_task:
          call: http.post
          args:
            url: $${"https://cloudtasks.googleapis.com/v2/projects/" + project_id + "/locations/${region}/queues/${queue_name}/tasks"}
            auth:
              type: OAuth2
            headers:
              Content-Type: application/json
            body:
              task:
                httpRequest:
                  url: $${task_processor_url}
                  httpMethod: POST
                  headers:
                    Content-Type: application/json
                  body: $${base64.encode(json.encode({
                    "action": "create_task",
                    "parameters": parameters
                  }))}
                scheduleTime: $${time.format(time.now())}
          result: task_result
          
      - return_success:
          return:
            status: "success"
            message: "Task creation initiated"
            task_id: $${task_result.body.name}
            intent: $${intent}
            timestamp: $${time.format(time.now())}

  - schedule_task_process:
      steps:
      - log_scheduling:
          call: sys.log
          args:
            text: $${"Scheduling task with parameters: " + string(parameters)}
            severity: INFO
            
      - calculate_schedule_time:
          assign:
          - schedule_delay: 3600  # Default 1 hour delay
          - schedule_time: $${time.format(time.add(time.now(), schedule_delay))}
          
      - enqueue_scheduled_task:
          call: http.post
          args:
            url: $${"https://cloudtasks.googleapis.com/v2/projects/" + project_id + "/locations/${region}/queues/${queue_name}/tasks"}
            auth:
              type: OAuth2
            headers:
              Content-Type: application/json
            body:
              task:
                httpRequest:
                  url: $${task_processor_url}
                  httpMethod: POST
                  headers:
                    Content-Type: application/json
                  body: $${base64.encode(json.encode({
                    "action": "scheduled_task",
                    "parameters": parameters
                  }))}
                scheduleTime: $${schedule_time}
          result: scheduled_result
          
      - return_scheduled:
          return:
            status: "success"
            message: "Task scheduled successfully"
            scheduled_time: $${schedule_time}
            task_id: $${scheduled_result.body.name}
            intent: $${intent}
            timestamp: $${time.format(time.now())}

  - generate_report_process:
      steps:
      - log_report:
          call: sys.log
          args:
            text: "Generating report based on voice command"
            severity: INFO
            
      - create_report_task:
          call: http.post
          args:
            url: $${"https://cloudtasks.googleapis.com/v2/projects/" + project_id + "/locations/${region}/queues/${queue_name}/tasks"}
            auth:
              type: OAuth2
            headers:
              Content-Type: application/json
            body:
              task:
                httpRequest:
                  url: $${task_processor_url}
                  httpMethod: POST
                  headers:
                    Content-Type: application/json
                  body: $${base64.encode(json.encode({
                    "action": "generate_report",
                    "parameters": parameters
                  }))}
                scheduleTime: $${time.format(time.now())}
          result: report_result
          
      - return_report:
          return:
            status: "success"
            message: "Report generation initiated"
            task_id: $${report_result.body.name}
            intent: $${intent}
            timestamp: $${time.format(time.now())}

  - unknown_intent_error:
      raise:
        message: $${"Unknown intent received: " + intent + ". Supported intents: create_task, schedule_task, generate_report"}