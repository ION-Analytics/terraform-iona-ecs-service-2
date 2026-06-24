# Multi-Container Support Implementation

This document summarizes the changes made to add multi-container task support to the terraform-iona-ecs-service-2 module.

## Overview

Added the ability to deploy multiple containers within a single ECS task definition, with per-container load balancer configurations. This is controlled via a new `multiple_images` boolean flag.

## Key Features

1. **Backward Compatible**: When `multiple_images = false` (default), the module behaves exactly as before
2. **Multi-Container Tasks**: When `multiple_images = true`, define multiple containers via the `tasks` variable
3. **Per-Container Load Balancing**: Each container can specify its own list of target group ARNs
4. **Automatic Container Naming**: Container names are extracted from image URIs
5. **Works with All Service Types**: Compatible with service, service_multiple_load_balancers, service_no_load_balancer, service_for_awsvpc_no_loadbalancer, and scheduled_task
6. **Forced desired_count = 1**: When using multi-container mode, the service desired count is automatically set to 1

## Files Modified

### Root Module

#### variables.tf
- Added `multiple_images` (bool, default: false)
- Added `tasks` (list of container configuration objects)

#### main.tf
- Added `extract_container_name` local to parse container names from image URIs
- Modified `service_container_definition` module to use count (0 when multiple_images = true)
- Added `multi_container_definitions` module using for_each over tasks
- Modified `application_containers` local to build list from either single or multiple containers
- Added `multi_container_load_balancers` local to build per-container load balancer configurations
- Modified `service` module call to:
  - Force desired_count = 1 when multiple_images = true
  - Pass multi_container_load_balancers
  - Pass multiple_images flag
- Added validation resource with preconditions for configuration validation

#### README.md
- Added "Multi-container service" usage example
- Added "Multi-Container Tasks" section explaining the feature
- Updated variable documentation to indicate which variables are ignored when multiple_images = true
- Added notes about shared vs per-container configuration

### Service Submodule

#### service/variables.tf
- Added `multiple_images` (bool, default: false)
- Added `multi_container_load_balancers` (list of load balancer configuration objects)

#### service/main.tf
- Modified `aws_ecs_service.service` resource:
  - Changed static `load_balancer` block to dynamic block with conditional logic
  - When multiple_images = false: uses original single-container configuration
  - When multiple_images = true: uses multi_container_load_balancers list
- Modified `aws_ecs_service.service_multiple_loadbalancers` resource:
  - Changed dynamic `load_balancer` block to support both modes
  - When multiple_images = false: uses multiple_target_group_arns with single container
  - When multiple_images = true: uses multi_container_load_balancers list

### Documentation

#### docs/multi-container-example.md
- Comprehensive example showing multi-container deployment
- Demonstrates per-container target group configuration
- Shows advanced usage with multiple port mappings
- Documents shared vs per-container configuration

#### docs/MULTI_CONTAINER_CHANGES.md
- This file documenting the implementation

## Validation Rules

The module enforces the following validation rules:

1. When `multiple_images = true`:
   - The `tasks` list must contain at least one container
   
2. When `multiple_images = false`:
   - The `tasks` list must be empty
   - Either `image_id` or `release["image_id"]` must be provided

These validations are implemented using `null_resource` with lifecycle preconditions.

## Container Naming Convention

Container names are automatically generated as: `{component}-{extracted_image_name}`

The image name is extracted using regex from the image URI:
- `123.dkr.ecr.us-west-2.amazonaws.com/my-app:v1.0` → `my-app`
- `my-app@sha256:abc123...` → `my-app`
- `registry.example.com/team/my-service:latest` → `my-service`

## Load Balancer Configuration

### Single Container Mode (multiple_images = false)
- **service**: Uses `target_group_arn` with single container
- **service_multiple_load_balancers**: Uses `multiple_target_group_arns` with single container

### Multi-Container Mode (multiple_images = true)
Both service types use the `multi_container_load_balancers` list, where each entry specifies:
- `target_group_arn`: The ALB target group ARN
- `container_name`: Which container to connect (auto-generated)
- `container_port`: Which port on the container

Example multi_container_load_balancers entry:
```hcl
{
  target_group_arn = "arn:aws:elasticloadbalancing:..."
  container_name   = "my-service-app-a"
  container_port   = 8080
}
```

## Shared Configuration

When `multiple_images = true`, the following are shared across ALL containers:

- **Environment Variables**: `common_application_environment`, `application_environment`, `secrets`
- **Secrets**: `application_secrets`, `platform_secrets`, `custom_secrets`
- **Logging**: `log_configuration`, `firelens_configuration`
- **Base Docker Labels**: From `release` map (component, env, team, version)
- **Volume Mounts**: `taskdef_volume`, `container_mountpoint`
- **CloudWatch Log Groups**: All containers log to the same stdout/stderr log groups

## Per-Container Configuration

When `multiple_images = true`, each task in the `tasks` list can specify:

- `image`: Container image URI (required)
- `cpu`: CPU units (required)
- `memory`: Memory in MB (required)
- `port`: Single port (optional, default "0")
- `container_port_mappings`: Multiple ports as JSON (optional, overrides port)
- `target_group_arns`: List of target groups for this container (optional)
- `privileged`: Privileged mode (optional, default false)
- `nofile_soft_ulimit`: File descriptor limit (optional, default "4096")
- `stop_timeout`: Graceful shutdown timeout (optional, default "120")
- `extra_hosts`: Custom /etc/hosts entries (optional)
- `container_labels`: Additional Docker labels (optional, merged with base labels)

## Ignored Variables in Multi-Container Mode

When `multiple_images = true`, these root-level variables are ignored:

- `image_id`
- `cpu`
- `memory`
- `port`
- `desired_count` (forced to 1)
- `privileged`
- `nofile_soft_ulimit`
- `stop_timeout`
- `container_labels`
- `container_port_mappings`
- `extra_hosts`

## Testing

The implementation was validated using:
- `terraform init` - Successfully initialized
- `terraform validate` - Configuration is valid (only pre-existing deprecation warnings)
- `terraform fmt` - All files formatted

## Migration Path

### Existing Single-Container Services
No changes required. Setting `multiple_images = false` (the default) preserves all existing behavior.

### New Multi-Container Services
1. Set `multiple_images = true`
2. Remove or comment out single-container variables (image_id, cpu, memory, port, etc.)
3. Define containers in the `tasks` list
4. Configure per-container target_group_arns as needed

### Example Migration

**Before (single container):**
```hcl
module "ecs_service" {
  source = "ION-Analytics/ecs-service/iona"
  
  image_id    = "123.dkr.ecr.../app:v1"
  cpu         = "512"
  memory      = "1024"
  port        = "8080"
  target_group_arn = aws_alb_target_group.app.arn
  
  # ... other config
}
```

**After (multi-container):**
```hcl
module "ecs_service" {
  source = "ION-Analytics/ecs-service/iona"
  
  multiple_images = true
  tasks = [
    {
      image             = "123.dkr.ecr.../app:v1"
      cpu               = "512"
      memory            = "1024"
      port              = "8080"
      target_group_arns = [aws_alb_target_group.app.arn]
    },
    {
      image             = "123.dkr.ecr.../sidecar:v1"
      cpu               = "256"
      memory            = "512"
      port              = "9090"
      target_group_arns = [aws_alb_target_group.sidecar.arn]
    }
  ]
  
  # ... other config
}
```

## Known Limitations

1. **Desired Count**: When `multiple_images = true`, desired_count is always forced to 1. To scale, deploy multiple independent task definitions with the same containers.

2. **Container Names**: Container names are auto-generated from image names. If two tasks use images with the same repository name (e.g., both use `my-app` but from different registries), name conflicts will occur.

3. **Shared Secrets**: All containers share the same secrets. Per-container secrets would require additional implementation.

4. **Port Mapping Extraction**: When using container_port_mappings with multiple ports, only the first port is used for load balancer container_port. Additional ports won't be automatically connected to load balancers.

## Future Enhancements

Potential future improvements:

1. Support per-container secrets configuration
2. Support per-container environment variables
3. Auto-detect and handle container name collisions
4. Support multiple port mappings per container in load balancer configuration
5. Dynamic desired_count calculation based on container resource requirements
6. Per-container health check grace periods
