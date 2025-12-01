```mermaid
flowchart LR
  Client[Client / Browser]

  APIGW[API Gateway HTTP API]

  LWA[Lambda • Wake]

  ECS[ECS Service]

  TASK[Fargate Task App]

  EVB[EventBridge rule]

  LAS[Lambda • Auto-sleep]

  %% Wake flow
  Client -->|GET / wake| APIGW
  APIGW --> LWA
  LWA -->|desiredCount = 1| ECS
  ECS -->|start task| TASK
  TASK -->|serve app| Client

  %% Sleep flow
  EVB --> LAS
  LAS -->|desiredCount = 0| ECS
  ```