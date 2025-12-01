# ADR-003: Choosing API Gateway as the Public Entry Point (No ALB, No Route53)

## Status
Accepted

## Context
This architecture is a fully automated **scale-to-zero ECS Fargate deployment**:
- The service normally runs at **desiredCount = 0** (true zero-cost idle).
- A wake request is triggered via **API Gateway → Lambda → ECS UpdateService**.
- Once the task starts, the wake Lambda redirects the client directly to the
  **task's public IP**.
- An autosleep Lambda scales the service back to zero after inactivity.

Because the app is usually *not running*, we must choose the correct public
entry point to initiate wake events.

Two realistic options were:

1. **Application Load Balancer (ALB)**
2. **API Gateway (HTTP API)**

## Decision
Use **API Gateway** as the only public entry point.

## Rationale

### 1. ALB is cost-prohibitive for scale-to-zero
An ALB incurs ~$16–$20/month even with:
- 0 running tasks  
- no traffic  

This contradicts the project's design goal:  
**near-zero monthly AWS cost.**

API Gateway costs ~$0.01–$0.03/month for this workload.

### 2. ALB cannot “wake” a service when no tasks exist
ALB requires:
- a target group  
- at least one registered healthy target  

When desiredCount=0, ALB has nothing to route to.
It cannot trigger wake logic on its own.

### 3. API Gateway + Lambda works even when ECS is fully stopped
The service can be **completely powered off**, yet:
- API Gateway endpoint still works
- Lambda can run the wake logic
- ECS service can be scaled up from zero

This is the core of the architecture.

### 4. Zero infrastructure requirements
API Gateway:
- does not require Route 53 hosted zones  
- does not require ALB listeners, target groups, or health checks  
- does not need any EC2 instance or ENI pre-provisioning  

Perfect fit for minimal infrastructure.

### 5. Fits the project’s wake/sleep flow