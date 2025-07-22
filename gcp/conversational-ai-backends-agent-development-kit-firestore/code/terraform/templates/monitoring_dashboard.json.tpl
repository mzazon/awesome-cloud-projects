{
  "displayName": "Conversational AI Backend Dashboard",
  "category": "CUSTOM",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "xPos": 0,
        "yPos": 0,
        "widget": {
          "title": "Cloud Function Invocations",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND resource.labels.project_id=\"${project_id}\" AND resource.labels.region=\"${region}\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["resource.labels.function_name"]
                    }
                  },
                  "unitOverride": "1/s"
                },
                "plotType": "LINE",
                "targetAxis": "Y1"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Invocations per second",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "yPos": 0,
        "widget": {
          "title": "Function Execution Duration",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND resource.labels.project_id=\"${project_id}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.labels.function_name"]
                    }
                  },
                  "unitOverride": "ms"
                },
                "plotType": "LINE",
                "targetAxis": "Y1"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Duration (ms)",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 0,
        "yPos": 4,
        "widget": {
          "title": "Function Error Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND resource.labels.project_id=\"${project_id}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.labels.status!=\"ok\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["resource.labels.function_name"]
                    }
                  },
                  "unitOverride": "1/s"
                },
                "plotType": "LINE",
                "targetAxis": "Y1"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Errors per second",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "yPos": 4,
        "widget": {
          "title": "Firestore Operations",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"firestore_database\" AND resource.labels.project_id=\"${project_id}\" AND metric.type=\"firestore.googleapis.com/api/request_count\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["metric.labels.op_type"]
                    }
                  },
                  "unitOverride": "1/s"
                },
                "plotType": "LINE",
                "targetAxis": "Y1"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Operations per second",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 0,
        "yPos": 8,
        "widget": {
          "title": "Cloud Storage Requests",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gcs_bucket\" AND resource.labels.project_id=\"${project_id}\" AND metric.type=\"storage.googleapis.com/api/request_count\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["metric.labels.method"]
                    }
                  },
                  "unitOverride": "1/s"
                },
                "plotType": "LINE",
                "targetAxis": "Y1"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Requests per second",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "yPos": 8,
        "widget": {
          "title": "Function Memory Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND resource.labels.project_id=\"${project_id}\" AND metric.type=\"cloudfunctions.googleapis.com/function/user_memory_bytes\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.labels.function_name"]
                    }
                  },
                  "unitOverride": "By"
                },
                "plotType": "LINE",
                "targetAxis": "Y1"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Memory Usage (Bytes)",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 12,
        "height": 3,
        "xPos": 0,
        "yPos": 12,
        "widget": {
          "title": "System Logs",
          "logsPanel": {
            "filter": "resource.type=\"cloud_function\" AND resource.labels.project_id=\"${project_id}\" AND (severity>=ERROR OR jsonPayload.message=~\"conversation\")",
            "resourceNames": []
          }
        }
      }
    ]
  },
  "labels": {
    "application": "conversational-ai",
    "component": "monitoring",
    "managed-by": "terraform"
  }
}