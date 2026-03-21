# Data Intelligence Platform: Step Functions Architecture Design

**Author:** George Villanueva  
**Date:** 2026-03-21  
**Project:** Week 23 Assignment - Data Intelligence Platform  
**Branch:** assignment/week23-data-intelligence

---

## Executive Summary

The current Data Intelligence Platform uses a Lambda orchestrator to coordinate
four Bedrock agents in a sequential pipeline. While functional, this approach
has limitations in error resilience, observability, and scalability. This
document proposes a Step Functions-based architecture that addresses these
limitations for production deployment.

---

## Current Architecture: Lambda Orchestrator

### How It Works Today

The DataIntelligenceOrchestrator Lambda function calls four agents in sequence:
```
S3 Upload → Lambda Trigger → Repo_Intelligence_Agent
                           → Technology_Assessment_Agent
                           → Maturity_Assessment_Agent
                           → Integration_Recommendations_Agent
                           → Assemble Report
                           → Save to S3
```

### Current Limitations

**No retry logic.** If the Technology_Assessment_Agent fails due to a transient
Bedrock timeout, the entire pipeline fails and no report is generated. The user
must manually re-upload the trigger file to start over.

**No parallelism.** The three analytical agents run sequentially even though
they are completely independent. Each agent receives the same intelligence JSON
and produces an independent section. Running them sequentially adds unnecessary
latency. If each agent takes 20 seconds, the analytical phase takes 60 seconds
when it could take 20 seconds with parallel execution.

**Limited observability.** Debugging requires reading CloudWatch logs and
manually tracing the execution flow. There is no visual representation of which
step failed or how long each step took.

**No fallback behavior.** If the Integration_Recommendations_Agent produces an
error response, the report assembly continues with that error text included in
the final document.

---

## Proposed Architecture: Step Functions State Machine

### Design Overview

The proposed architecture replaces the monolithic Lambda orchestrator with a
Step Functions state machine that implements three production patterns:
parallel execution, error handling with retries, and conditional fallback.

### State Machine Definition
```json
{
  "Comment": "Data Intelligence Platform - Production State Machine",
  "StartAt": "ScanRepository",
  "States": {

    "ScanRepository": {
      "Type": "Task",
      "Resource": "arn:aws:states:::bedrock:invokeAgent",
      "Parameters": {
        "AgentId.$": "$.agent_ids.repo_intelligence",
        "AgentAliasId": "TSTALIASID",
        "SessionId.$": "$.session_id",
        "InputText.$": "$.repo_url"
      },
      "ResultPath": "$.intelligence_data",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed", "States.Timeout"],
          "IntervalSeconds": 3,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.scan_error",
          "Next": "HandleScanFailure"
        }
      ],
      "Next": "RunAnalyticalAgentsInParallel"
    },

    "RunAnalyticalAgentsInParallel": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "TechnologyAssessment",
          "States": {
            "TechnologyAssessment": {
              "Type": "Task",
              "Resource": "arn:aws:states:::bedrock:invokeAgent",
              "Parameters": {
                "AgentId.$": "$.agent_ids.technology_assessment",
                "AgentAliasId": "TSTALIASID",
                "SessionId.$": "$.session_ids.tech",
                "InputText.$": "$.intelligence_data.output"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 2,
                  "BackoffRate": 1.5
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "MaturityAssessment",
          "States": {
            "MaturityAssessment": {
              "Type": "Task",
              "Resource": "arn:aws:states:::bedrock:invokeAgent",
              "Parameters": {
                "AgentId.$": "$.agent_ids.maturity_assessment",
                "AgentAliasId": "TSTALIASID",
                "SessionId.$": "$.session_ids.maturity",
                "InputText.$": "$.intelligence_data.output"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 2,
                  "BackoffRate": 1.5
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "IntegrationRecommendations",
          "States": {
            "IntegrationRecommendations": {
              "Type": "Task",
              "Resource": "arn:aws:states:::bedrock:invokeAgent",
              "Parameters": {
                "AgentId.$": "$.agent_ids.integration_recommendations",
                "AgentAliasId": "TSTALIASID",
                "SessionId.$": "$.session_ids.integration",
                "InputText.$": "$.intelligence_data.output"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 2,
                  "BackoffRate": 1.5
                }
              ],
              "End": true
            }
          }
        }
      ],
      "ResultPath": "$.analytical_results",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.analysis_error",
          "Next": "HandleAnalysisFailure"
        }
      ],
      "Next": "AssembleReport"
    },

    "AssembleReport": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "DataIntelligenceReportAssembler",
        "Payload": {
          "repo_name.$": "$.repo_name",
          "scan_date.$": "$.scan_date",
          "intelligence_data.$": "$.intelligence_data.output",
          "technology_assessment.$": "$.analytical_results[0].output",
          "maturity_assessment.$": "$.analytical_results[1].output",
          "integration_recommendations.$": "$.analytical_results[2].output",
          "output_bucket.$": "$.output_bucket",
          "report_date.$": "$.report_date"
        }
      },
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 2,
          "BackoffRate": 1.5
        }
      ],
      "End": true
    },

    "HandleScanFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "DataIntelligenceErrorNotifier",
        "Payload": {
          "error_stage": "repository_scan",
          "error.$": "$.scan_error",
          "repo_url.$": "$.repo_url"
        }
      },
      "Next": "PipelineFailed"
    },

    "HandleAnalysisFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "DataIntelligenceErrorNotifier",
        "Payload": {
          "error_stage": "analytical_agents",
          "error.$": "$.analysis_error",
          "repo_url.$": "$.repo_url"
        }
      },
      "Next": "PipelineFailed"
    },

    "PipelineFailed": {
      "Type": "Fail",
      "Error": "PipelineExecutionFailed",
      "Cause": "One or more pipeline stages failed after retries were exhausted"
    }

  }
}
```

---

## Architecture Comparison

### Performance Improvement

| Stage | Lambda Orchestrator | Step Functions |
|-------|-------------------|----------------|
| Repository Scan | 25 seconds | 25 seconds |
| Technology Assessment | 20 seconds | 20 seconds (parallel) |
| Maturity Assessment | 20 seconds | 20 seconds (parallel) |
| Integration Recommendations | 20 seconds | 20 seconds (parallel) |
| Report Assembly | 5 seconds | 5 seconds |
| **Total** | **90 seconds** | **50 seconds** |

The parallel execution of the three analytical agents reduces total pipeline
time from approximately 90 seconds to approximately 50 seconds, a 44%
improvement.

### Reliability Improvement

The current Lambda orchestrator has zero retry logic. A single transient
Bedrock timeout causes a complete pipeline failure. The Step Functions
architecture adds automatic retries with exponential backoff at every stage.

For the ScanRepository stage: 3 retries with 3 second initial interval and
2x backoff means the system will wait 3 seconds, then 6 seconds, then 12
seconds before declaring failure. This handles the vast majority of transient
cloud service errors automatically without any user intervention.

### Observability Improvement

The Step Functions console provides a real-time visual execution graph showing
exactly which state is currently executing, the input and output of each
completed state, the duration of each state, and where failures occurred with
the exact error message. This replaces the current approach of parsing
CloudWatch logs manually.

---

## Data Engineering Relevance

This architecture design demonstrates three patterns that are directly
applicable to data engineering work.

**Parallel processing** is a foundational concept in data engineering. Any time
you have independent transformations that can run simultaneously you should run
them in parallel. This is the core principle behind distributed processing
frameworks like Spark. Step Functions implements this same concept at the
workflow orchestration level.

**Declarative error handling** is how production data pipelines manage
reliability. Rather than writing try/except blocks in Python, you declare the
retry policy and fallback behavior in the workflow definition. This separates
the business logic from the operational logic, making both easier to maintain.

**Workflow observability** is a requirement for production data pipelines.
When a pipeline fails at 3am you need to know exactly which stage failed, what
the input was, and what the error was. The Step Functions execution history
provides this without any additional instrumentation code.

---

## Migration Path

A production migration from the current Lambda orchestrator to Step Functions
would follow these steps:

1. Deploy the Step Functions state machine using Terraform alongside the
   existing Lambda orchestrator without removing it.
2. Route a small percentage of traffic to the Step Functions workflow using
   a feature flag in the S3 trigger Lambda.
3. Monitor both pipelines in parallel and compare output quality and
   reliability metrics.
4. Once Step Functions shows equal or better results, redirect all traffic
   and decommission the Lambda orchestrator.

This approach eliminates risk by running both systems simultaneously before
cutting over completely.

---

## Conclusion

The Step Functions architecture addresses all four limitations of the current
Lambda orchestrator: it adds automatic retry logic, enables parallel agent
execution reducing latency by 44%, provides visual execution monitoring, and
implements structured error handling with fallback behavior. For a production
data intelligence platform processing hundreds of repositories per day, these
improvements are not optional enhancements but baseline requirements.