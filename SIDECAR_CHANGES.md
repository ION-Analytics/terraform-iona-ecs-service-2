# Sidecar Container Support

This fork of `terraform-iona-ecs-service` adds support for running a second container (sidecar) alongside the main application container in the same ECS task.

## Changes Made

### 1. New Variable: `sidecar_container`

Added optional `sidecar_container` variable to `variables.tf` that accepts:

- **Required fields:**
  - `name` - Container name
  - `image` - Docker image

- **Optional fields:**
  - `cpu` - CPU units (defaults to main container's CPU if not specified)
  - `memory` - Memory in MB (defaults to main container's memory if not specified)
  - `port` - Container port (defaults to "0" for no port mapping)
  - `privileged` - Run with elevated privileges (defaults to false)
  - `map_environment` - Additional environment variables (merged with shared environment)
  - `port_mappings` - Custom port mappings (overrides simple `port` setting)
  - `mount_points` - Custom volume mounts (defaults to main container's mountpoint)
  - `container_labels` - Additional docker labels (merged with standard labels)
  - `log_configuration` - Custom log configuration (defaults to main container's log config)

### 2. Shared Configuration

The sidecar container shares these values with the main container:
- `application_secrets` - Application-specific secrets from Secrets Manager
- `platform_secrets` - Platform secrets from Secrets Manager
- `custom_secrets` - Custom secrets from Secrets Manager
- `platform_config` - Platform configuration
- `common_application_environment` - Common environment variables
- `application_environment` - Environment-specific variables
- `secrets` - Additional secrets map
- `stop_timeout` - Container stop timeout
- `ulimits` - File descriptor limits
- `extra_hosts` - /etc/hosts entries

### 3. Separate Logging

Each sidecar container gets its own CloudWatch log groups:
- `${service_name}-${sidecar_name}-stdout`
- `${service_name}-${sidecar_name}-stderr`

These log groups are automatically created with 7-day retention and optionally configured with Datadog subscriptions if enabled.

### 4. Service Type Compatibility

Sidecar containers work with all service types:
- `service` - Standard ECS service with load balancer
- `service_multiple_load_balancers` - Service with multiple target groups
- `service_no_load_balancer` - Service without load balancer
- `service_for_awsvpc_no_loadbalancer` - AWSVPC network mode without load balancer
- `scheduled_task` - EventBridge scheduled tasks

### 5. Task Definition Integration

The sidecar container is added to the task definition's container array alongside:
1. FireLens log router (if `firelens_configuration` is set)
2. Main application container
3. Sidecar container (if `sidecar_container` is set)

## Usage Examples

### Basic Sidecar (minimal configuration)

```hcl
module "my_service" {
  source = "./terraform-iona-ecs-service-2"

  # ... standard configuration ...

  sidecar_container = {
    name   = "metrics-exporter"
    image  = "my-registry/metrics-exporter:v1.2.3"
    cpu    = "128"
    memory = "256"
    port   = "9090"
  }
}
```

### Advanced Sidecar (custom configuration)

```hcl
module "my_service" {
  source = "./terraform-iona-ecs-service-2"

  # ... standard configuration ...

  sidecar_container = {
    name   = "nginx-proxy"
    image  = "nginx:latest"
    cpu    = "256"
    memory = "512"
    
    port_mappings = [
      {
        containerPort = 80
        protocol      = "tcp"
      },
      {
        containerPort = 443
        protocol      = "tcp"
      }
    ]
    
    mount_points = [
      {
        containerPath = "/etc/nginx/conf.d"
        sourceVolume  = "nginx-config"
        readOnly      = true
      }
    ]
    
    map_environment = {
      NGINX_WORKER_PROCESSES = "4"
      NGINX_WORKER_CONNECTIONS = "1024"
    }
    
    container_labels = {
      proxy_type = "nginx"
    }
  }
}
```

### Sidecar with Scheduled Task

```hcl
module "scheduled_job" {
  source = "./terraform-iona-ecs-service-2"

  service_type        = "scheduled_task"
  schedule_expression = "rate(1 hour)"
  
  # ... other configuration ...

  sidecar_container = {
    name   = "log-shipper"
    image  = "fluent/fluent-bit:latest"
    cpu    = "64"
    memory = "128"
  }
}
```

## Backwards Compatibility

All changes are backwards compatible:
- `sidecar_container` defaults to `null`, so existing configurations work unchanged
- When `sidecar_container` is not set, module behavior is identical to the original
- All original variables and outputs remain unchanged

## Implementation Details

### Module Structure

```
terraform-iona-ecs-service-2/
├── main.tf                    # Added sidecar_container_definition module
├── variables.tf               # Added sidecar_container variable
├── container-definition/      # Unchanged submodule
├── taskdef/                   # Unchanged submodule
└── service/                   # Unchanged submodule
```

### Container Definition Flow

1. `module.service_container_definition` creates main container
2. `module.sidecar_container_definition[0]` conditionally creates sidecar (count = 1 if sidecar_container != null)
3. `local.complete_container_definition` merges FireLens + Main + Sidecar containers
4. `module.taskdef` receives the merged container definitions as JSON

### Resource Naming

- Main container: `${env}-${component}${name_suffix}`
- Sidecar container: Uses the name specified in `sidecar_container.name`
- Log groups: `${full_service_name}-${sidecar_name}-stdout/stderr`

## Testing

Validated with:
```bash
terraform init -upgrade
terraform validate
```

Both commands completed successfully with no errors.
