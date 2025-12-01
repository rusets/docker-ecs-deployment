# ADR-005: Autosleep Implementation — Lambda + EventBridge Instead of ECS Scheduled Tasks

## Status
Accepted

## Context
The application must automatically scale down to zero when idle.
Two implementation options were considered:

1. **ECS Scheduled Tasks**
2. **Lambda triggered by EventBridge (every 1 minute)**

Requirements:
- Zero cost when idle
- Easy logic updates
- Ability to inspect ECS service/tasks before scaling down
- Central place to extend the autosleep logic later

## Decision
Use **EventBridge (1-minute rule) → autosleep Lambda**.

## Rationale
### 1. Lambda is cheaper & simpler
- Lambda cost is essentially zero at this invocation frequency.
- No Fargate tasks running periodically (which cost money even if short).

### 2. More flexible logic
Autosleep Lambda can perform:
- `ecs:ListTasks`
- `ecs:DescribeTasks`
- inspect container health
- custom heuristics (CPU/memory thresholds)
- per-service logic

ECS Scheduled Tasks only run a container — requiring extra code and image maintenance.

### 3. No container image required
Lambda:
- is deployed automatically by Terraform  
- requires no Dockerfile  
- makes iteration faster  
- integrates cleanly with CloudWatch Logs

### 4. Consistent wake/sleep model
Wake = Lambda  
Sleep = Lambda  
→ symmetrical serverless design.

### 5. Works even when ECS has **zero running tasks**
ECS Scheduled Tasks rely on Fargate capacity.  
Lambda works regardless of ECS state.

## Consequences
- Autosleep logic lives as Python code inside Lambda → simple to maintain.
- No additional Fargate executions → cost stays near zero.
- Event-driven design keeps the architecture clean and minimal.