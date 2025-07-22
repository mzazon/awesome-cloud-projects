# Cloud Workflows Definition for Serverless GPU ML Pipeline
# This template defines the orchestration logic for the ML pipeline

main:
  params: [input]
  steps:
    - init:
        assign:
          - project_id: "${project_id}"
          - input_bucket: "${input_bucket}"
          - output_bucket: "${output_bucket}"
          - input_file: $${input.input_file}
          - preprocess_url: "${preprocess_url}"
          - inference_url: "${inference_url}"
          - postprocess_url: "${postprocess_url}"
    
    - log_start:
        call: sys.log
        args:
          text: $${"Starting ML pipeline for file: " + input_file}
          severity: INFO
    
    - preprocess_step:
        call: http.post
        args:
          url: $${preprocess_url + "/preprocess"}
          headers:
            Content-Type: "application/json"
          body:
            input_bucket: $${input_bucket}
            input_file: $${input_file}
          timeout: 60
        result: preprocess_result
    
    - check_preprocess:
        switch:
          - condition: $${preprocess_result.body.status == "success"}
            next: inference_step
        next: preprocess_error
    
    - inference_step:
        call: http.post
        args:
          url: $${inference_url + "/predict"}
          headers:
            Content-Type: "application/json"
          body:
            text: $${preprocess_result.body.processed_data.text}
          timeout: 300
        result: inference_result
    
    - check_inference:
        switch:
          - condition: $${inference_result.status == 200}
            next: postprocess_step
        next: inference_error
    
    - postprocess_step:
        call: http.post
        args:
          url: $${postprocess_url + "/postprocess"}
          headers:
            Content-Type: "application/json"
          body:
            prediction_result: $${inference_result.body}
            input_metadata:
              input_file: $${input_file}
              input_bucket: $${input_bucket}
            output_bucket: $${output_bucket}
          timeout: 60
        result: postprocess_result
    
    - log_success:
        call: sys.log
        args:
          text: $${"Pipeline completed successfully. Output: " + postprocess_result.body.output_file}
          severity: INFO
    
    - return_result:
        return:
          status: "success"
          input_file: $${input_file}
          output_file: $${postprocess_result.body.output_file}
          output_bucket: $${output_bucket}
          summary: $${postprocess_result.body.summary}
          execution_time: $${time.format(sys.now())}
    
    - preprocess_error:
        call: sys.log
        args:
          text: $${"Preprocessing failed: " + string(preprocess_result.body)}
          severity: ERROR
        next: error_return
    
    - inference_error:
        call: sys.log
        args:
          text: $${"Inference failed: " + string(inference_result)}
          severity: ERROR
        next: error_return
    
    - error_return:
        return:
          status: "error"
          input_file: $${input_file}
          error: "Pipeline execution failed"
          execution_time: $${time.format(sys.now())}