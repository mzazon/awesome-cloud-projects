# Container declaration for Endpoints Service Proxy (ESP)
# This configuration runs ESP as a container on Container-Optimized OS

spec:
  containers:
    - name: esp-proxy
      image: gcr.io/endpoints-release/endpoints-runtime:2
      ports:
        - containerPort: 8080
          hostPort: 8080
          protocol: TCP
      env:
        - name: ESPv2_ARGS
          value: >-
            --service=${endpoints_service_name}
            --rollout_strategy=managed
            --backend=http://${backend_service_ip}:${backend_port}
            --cors_preset=basic
            --cors_allow_origin=*
            --cors_allow_methods=GET,POST,PUT,DELETE,OPTIONS
            --cors_allow_headers=Content-Type,Authorization,X-Requested-With
            --enable_debug=false
            --log_level=1
            --healthz=/healthz
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: /etc/service_account/service-account-key.json
      resources:
        requests:
          memory: "256Mi"
          cpu: "100m"
        limits:
          memory: "512Mi"
          cpu: "500m"
      livenessProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
      readinessProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 5
        timeoutSeconds: 3
        failureThreshold: 3
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: var-log
          mountPath: /var/log
  volumes:
    - name: tmp
      emptyDir: {}
    - name: var-log
      emptyDir: {}
  restartPolicy: Always