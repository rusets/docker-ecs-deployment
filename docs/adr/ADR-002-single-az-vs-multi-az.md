# ADR-002: Single-AZ vs Multi-AZ Deployment

## Status
Accepted

## Context
The project uses a VPC with 2 public subnets. Fargate tasks are ephemeral and inexpensive.  
The purpose of the project is a **portfolio demo**, optimized for **low cost** and **fast reproducibility**.

AWS offers:

- **Multi-AZ**: High availability, 2–3x cost  
- **Single-AZ**: Lower cost, simpler, faster destroy/apply cycles

## Decision
Use **Single-AZ** (two public subnets from the same AZ).

## Rationale
- Cuts VPC, route tables, ENIs, NATs, CloudWatch logs cost  
- Fargate tasks are stateless — AZ redundancy provides little benefit  
- Faster provisioning → better for demo / interview usage  
- Wake/sleep pattern assumes disposable workloads, not HA requirements

## Consequences
- Loss of HA if the chosen AZ goes down  
- Acceptable risk for portfolio / sandbox  
- If project becomes production → easy to extend to Multi-AZ later