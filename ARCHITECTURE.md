# Architecture Diagram

## ECS Task Structure

### Without Sidecar (Original)

```
┌─────────────────────────────────────────────┐
│ ECS Task Definition                          │
│ arn:.../task-definition/dev-my-app:123      │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │ Container: my-app                      │ │
│  │ Image: my-app:1.0.0                    │ │
│  │ CPU: 512, Memory: 1024                 │ │
│  │ Port: 8080                             │ │
│  │                                        │ │
│  │ Environment:                           │ │
│  │   ENV_NAME=dev                         │ │
│  │   COMPONENT_NAME=my-app                │ │
│  │   ...shared vars...                    │ │
│  │                                        │ │
│  │ Secrets: app + platform secrets        │ │
│  │                                        │ │
│  │ Logs: dev-my-app-stdout/stderr         │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### With Sidecar (New)

```
┌─────────────────────────────────────────────────────────────────┐
│ ECS Task Definition                                              │
│ arn:.../task-definition/dev-my-app:124                          │
│                                                                  │
│  ┌────────────────────────────────────────┐                    │
│  │ Container: my-app                      │                    │
│  │ Image: my-app:1.0.0                    │                    │
│  │ CPU: 512, Memory: 1024                 │                    │
│  │ Port: 8080                             │                    │
│  │                                        │                    │
│  │ Environment:                           │                    │
│  │   ENV_NAME=dev                         │  ┌──Shared Config─┐│
│  │   COMPONENT_NAME=my-app                │  │ • Secrets      ││
│  │   ...shared vars...                    │──│ • Environment  ││
│  │                                        │  │ • Timeouts     ││
│  │ Secrets: app + platform secrets        │  │ • ulimits      ││
│  │                                        │  │ • extra_hosts  ││
│  │ Logs: dev-my-app-stdout/stderr         │  └────────────────┘│
│  └────────────────────────────────────────┘                    │
│                                                                  │
│  ┌────────────────────────────────────────┐                    │
│  │ Container: metrics-exporter            │                    │
│  │ Image: prom/statsd-exporter:v0.26.0    │                    │
│  │ CPU: 128, Memory: 256                  │                    │
│  │ Port: 9102                             │                    │
│  │                                        │                    │
│  │ Environment:                           │                    │
│  │   ENV_NAME=dev         (inherited)     │                    │
│  │   COMPONENT_NAME=my-app (inherited)    │                    │
│  │   ...shared vars...    (inherited)     │                    │
│  │   STATSD_LISTEN_UDP=.. (unique)        │                    │
│  │                                        │                    │
│  │ Secrets: app + platform secrets (inherited)                 │
│  │                                        │                    │
│  │ Logs: dev-my-app-metrics-exporter-stdout/stderr             │
│  └────────────────────────────────────────┘                    │
│                                                                  │
│  Network: Shared (can communicate via localhost)                │
│  Total Resources: CPU=640, Memory=1280                          │
└─────────────────────────────────────────────────────────────────┘
```

## Container Communication

### Bridge Network Mode (default)

```
┌─────────────────────────────────────────────┐
│ Docker Bridge Network                        │
│                                              │
│  ┌─────────────┐      ┌──────────────────┐ │
│  │   my-app    │◄────►│ metrics-exporter │ │
│  │ localhost   │      │    localhost     │ │
│  │  :8080      │      │     :9102        │ │
│  └─────────────┘      └──────────────────┘ │
│                                              │
│  Both containers share:                      │
│  - Network namespace                         │
│  - Can access each other via localhost       │
│  - Port conflicts will cause task failure    │
└─────────────────────────────────────────────┘
```

### AWSVPC Network Mode

```
┌─────────────────────────────────────────────┐
│ Task ENI (Elastic Network Interface)        │
│ IP: 10.0.1.50                                │
│                                              │
│  ┌─────────────┐      ┌──────────────────┐ │
│  │   my-app    │◄────►│ metrics-exporter │ │
│  │ localhost   │      │    localhost     │ │
│  │  :8080      │      │     :9102        │ │
│  └─────────────┘      └──────────────────┘ │
│                                              │
│  Task gets its own:                          │
│  - ENI with IP address                       │
│  - Security group(s)                         │
│  - Containers share the task's network       │
└─────────────────────────────────────────────┘
```

## Module Flow

```
┌──────────────────────────────────────────────────────────────┐
│ terraform-iona-ecs-service-2                                  │
│                                                               │
│  Input: sidecar_container = {                                │
│    name = "metrics-exporter"                                 │
│    image = "prom/statsd-exporter:v0.26.0"                    │
│    cpu = "128"                                               │
│    memory = "256"                                            │
│  }                                                            │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ module.service_container_definition                    │ │
│  │ (container-definition submodule)                       │ │
│  │ → Generates main container JSON                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                            ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ module.sidecar_container_definition[0]                 │ │
│  │ (container-definition submodule)                       │ │
│  │ → Generates sidecar container JSON                     │ │
│  │ → Inherits secrets, env, timeouts from main            │ │
│  └────────────────────────────────────────────────────────┘ │
│                            ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ local.complete_container_definition                    │ │
│  │ → concat(firelens, main, sidecar)                      │ │
│  │ → jsonencode() for task definition                     │ │
│  └────────────────────────────────────────────────────────┘ │
│                            ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ module.taskdef                                         │ │
│  │ (taskdef submodule)                                    │ │
│  │ → Creates aws_ecs_task_definition                      │ │
│  │ → Both containers in same task                         │ │
│  └────────────────────────────────────────────────────────┘ │
│                            ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ module.service                                         │ │
│  │ (service submodule)                                    │ │
│  │ → Creates aws_ecs_service                              │ │
│  │ → References task definition with both containers      │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  Additional Resources Created:                                │
│  • aws_cloudwatch_log_group.sidecar_stdout                   │
│  • aws_cloudwatch_log_group.sidecar_stderr                   │
│  • aws_cloudwatch_log_subscription_filter (if Datadog)       │
└──────────────────────────────────────────────────────────────┘
```

## Use Cases

### 1. Metrics Collection

```
┌──────────┐         ┌────────────────┐         ┌──────────┐
│          │ StatsD  │                │  HTTP   │          │
│ Main App │────────►│ StatsD Exporter│────────►│Prometheus│
│  :8080   │UDP:8125 │     :9102      │ :9102   │          │
└──────────┘         └────────────────┘         └──────────┘
```

### 2. Log Shipping

```
┌──────────┐         ┌──────────────┐         ┌───────────┐
│          │  logs   │              │  HTTPS  │           │
│ Main App │────────►│  Fluent Bit  │────────►│ CloudWatch│
│  :8080   │ stdout  │   (sidecar)  │         │  / S3     │
└──────────┘         └──────────────┘         └───────────┘
```

### 3. Reverse Proxy

```
┌──────────┐  :80    ┌──────────┐  :8080   ┌──────────┐
│          │◄────────│          │◄─────────│          │
│ Internet │         │  Nginx   │          │ Main App │
│          │────────►│ (sidecar)│─────────►│          │
└──────────┘  :443   └──────────┘  :8080   └──────────┘
             HTTPS        ↓ TLS         HTTP
                    terminates here
```

### 4. Service Mesh

```
┌──────────┐         ┌──────────┐         ┌──────────┐
│          │◄───────►│  Envoy   │◄───────►│          │
│ Main App │localhost│ (sidecar)│  mesh   │  Other   │
│  :8080   │         │   :15001 │ network │ Services │
└──────────┘         └──────────┘         └──────────┘
                          ↑
                     mTLS, retry,
                     circuit breaking
```

## Resource Allocation

```
ECS Task Capacity = Main Container + Sidecar Container

Example:
  Main:    CPU = 512,  Memory = 1024
  Sidecar: CPU = 128,  Memory = 256
  ─────────────────────────────────────
  Total:   CPU = 640,  Memory = 1280

ECS Host must have:
  - Available CPU ≥ 640
  - Available Memory ≥ 1280

If insufficient capacity → Task placement fails
```
