```mermaid
flowchart LR
  subgraph GH[GitHub]
    CI[CI • Build & Push to ECR<br/>ci.yml]
    CD[CD • Terraform Apply / Destroy<br/>cd.yml]
    OPS[OPS • Wake / Sleep helpers<br/>ops.yml]
  end

  CI --> ECR[(ECR repo)]
  CD --> TF[(Terraform)]
  OPS --> APIGW[API Gateway HTTP API]

  TF --> VPC[(VPC + public subnets)]
  TF --> ECS[ECS Cluster + Fargate Service]
  TF --> ECR
  TF --> CWL[CloudWatch Logs]
  TF --> LWA[Lambda • Wake]
  TF --> LAS[Lambda • Auto-sleep]
  TF --> APIGW
  TF --> EVB[EventBridge rule]

  APIGW --> LWA
  EVB --> LAS

  LWA -->|desiredCount = 1| ECS
  LAS -->|desiredCount = 0| ECS

  subgraph Runtime
    ECS -->|public IP| Client[Client / Browser]
  end
  ```