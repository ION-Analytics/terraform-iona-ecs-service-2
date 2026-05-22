# Scheduled Task Support — Implementation Plan

## Overview

Add the ability to run containers as ECS scheduled tasks (via EventBridge) to the `terraform-iona-ecs-service` module by introducing `"scheduled_task"` as a new `service_type` value.

When selected, the module creates an EventBridge rule + target instead of an ECS service. The task definition and container definition submodules are reused unchanged.

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Coexistence | One or the other per module call | A module invocation creates either a service OR a scheduled task |
| Container definition | Identical (same image/command) | Lowest delta to existing code |
| Launch type | EC2 only | Matches current service behavior using existing cluster capacity providers |
| Schedules per call | Single | One schedule expression per module invocation |
| Network mode | Bridge (default) | Matches current services; no subnet/security group config needed |

---

## What Stays Identical (No Changes)

| Component | Reason |
|---|---|
| `container-definition/` submodule | Container def is the same for services and scheduled tasks |
| `taskdef/` submodule | Task definition, task role, execution role are all needed for scheduled tasks |
| CloudWatch log groups (stdout/stderr) | Still useful for scheduled task output |
| Log subscription filters | Datadog feed still useful |

## What Gets Conditionally Skipped

When `service_type == "scheduled_task"`, the following resources are not created:

| Component | How |
|---|---|
| `module "service"` | `count = var.service_type != "scheduled_task" ? 1 : 0` |
| `module "ecs_update_monitor"` | `count = var.service_type != "scheduled_task" ? 1 : 0` |
| `aws_appautoscaling_target.ecs` | `count = var.service_type != "scheduled_task" ? 1 : 0` |
| `aws_appautoscaling_scheduled_action.scale_down` | Add `&& var.service_type != "scheduled_task"` to existing condition |
| `aws_appautoscaling_scheduled_action.scale_back_up` | Same as above |
| `aws_appautoscaling_policy.task_scaling_policy` | Gate with `var.service_type != "scheduled_task"` |

---

## New Resources

All created only when `service_type == "scheduled_task"`, added to root `main.tf`:

### 1. `data "aws_ecs_cluster" "cluster"`

Looks up the cluster ARN from the `var.ecs_cluster` name. Required because the EventBridge target needs the cluster ARN, not just the name.

### 2. `aws_iam_role.scheduled_task_events`

IAM role for EventBridge to assume, with an `events.amazonaws.com` trust policy.

### 3. `aws_iam_role_policy.scheduled_task_events`

Policy granting:
- `ecs:RunTask` on the task definition family (wildcard revision via `replace(module.taskdef.arn, "/:\\d+$/", ":*")`)
- `iam:PassRole` on both the task role and execution role ARNs

### 4. `aws_cloudwatch_event_rule.scheduled_task`

EventBridge rule with the user-provided `schedule_expression`.

### 5. `aws_cloudwatch_event_target.scheduled_task`

EventBridge target pointing to the ECS cluster, referencing the task definition and capacity provider strategy.

---

## New Variables

Added to root `variables.tf`:

| Variable | Type | Default | Description |
|---|---|---|---|
| `schedule_expression` | `string` | `""` | Cron or rate expression, e.g. `"rate(1 hour)"` or `"cron(0 12 * * ? *)"`. Required when `service_type = "scheduled_task"`. |
| `schedule_task_count` | `number` | `1` | Number of task instances to launch per schedule trigger. |
| `schedule_enabled` | `bool` | `true` | Enable/disable the schedule without destroying it. |

## Variable Default Changes (Backward-Compatible)

| Variable | Change | Reason |
|---|---|---|
| `port` | Add `default = "0"` | Scheduled tasks don't listen on ports; avoids forcing callers to provide a meaningless value. Existing callers already pass `port`, so no breakage. |

---

## New Outputs

Added to root `outputs.tf`:

| Output | Value | Notes |
|---|---|---|
| `schedule_rule_arn` | EventBridge rule ARN | Empty string when not a scheduled task |
| `schedule_rule_name` | EventBridge rule name | Empty string when not a scheduled task |

Existing outputs (`task_role_arn`, `task_role_name`, `taskdef_arn`, `stdout_name`, `stderr_name`, `full_service_name`, `use_graviton`, `capacity_providers`) remain unchanged since `module "taskdef"` is always created.

---

## Files Changed Summary

| File | Change Type |
|---|---|
| `main.tf` (root) | Add conditionals to service/monitor/scaling; add scheduled task resources |
| `variables.tf` (root) | Add 3 new variables; add default to `port` |
| `outputs.tf` (root) | Add 2 new scheduled-task outputs |
| `README.md` | Document new `service_type = "scheduled_task"` option |

**No changes** to `service/`, `taskdef/`, or `container-definition/` submodules.

---

## Example Caller Usage

```hcl
module "ecs_scheduled_task" {
  source = "ION-Analytics/ecs-service/iona"

  providers = { aws = aws.cluster_provider }

  service_type        = "scheduled_task"
  schedule_expression = "cron(0 2 * * ? *)"   # daily at 2am UTC
  schedule_task_count = 1

  env             = terraform.workspace
  ecs_cluster     = local.ecs_cluster
  release         = var.release
  image_id        = var.docker["image"]
  platform_config = module.platform_config.config
  cpu             = var.cpu
  memory          = var.memory
  # port not required (defaults to "0")
  # target_group_arn not required (defaults to "")
  # desired_count irrelevant for scheduled tasks
}
```

---

## Risks and Caveats

- **Module count reference change**: Adding `count` to `module "service"` changes its reference from `module.service.name` to `module.service[0].name`. Only `module "ecs_update_monitor"` references it, and that module is also gated with the same condition, so this is safe.
- **Autoscaling gating is clean**: `aws_appautoscaling_target.ecs` references `local.full_service_name` directly (not the service module), so gating it independently works without dependency issues.
- **Provider version**: EventBridge capacity provider strategy support requires `aws` provider >= 4.x. Verify the provider version in use before implementing.
