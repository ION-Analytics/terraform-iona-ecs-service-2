# Backwards Compatibility Comparison

This document demonstrates that the fork maintains complete backwards compatibility with the original module.

## Without Sidecar (Original Behavior)

```hcl
module "original_service" {
  source = "../"

  env = "dev"
  release = {
    component = "my-app"
    team      = "platform"
    version   = "1.0.0"
    image_id  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:1.0.0"
  }
  
  cpu    = "512"
  memory = "1024"
  port   = "8080"

  ecs_cluster      = "my-cluster"
  target_group_arn = "arn:aws:elasticloadbalancing:..."
  
  desired_count = 3
  
  platform_config = {
    datadog_log_subscription_arn = ""
  }
}
```

**Result:** Identical behavior to terraform-iona-ecs-service
- Single container in task definition
- Standard CloudWatch log groups
- All original features work unchanged

## With Sidecar (New Feature)

```hcl
module "service_with_sidecar" {
  source = "../"

  env = "dev"
  release = {
    component = "my-app"
    team      = "platform"
    version   = "1.0.0"
    image_id  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:1.0.0"
  }
  
  cpu    = "512"
  memory = "1024"
  port   = "8080"

  ecs_cluster      = "my-cluster"
  target_group_arn = "arn:aws:elasticloadbalancing:..."
  
  desired_count = 3
  
  platform_config = {
    datadog_log_subscription_arn = ""
  }
  
  # NEW: Optional sidecar container
  sidecar_container = {
    name   = "metrics-exporter"
    image  = "prom/statsd-exporter:v0.26.0"
    cpu    = "128"
    memory = "256"
    port   = "9102"
  }
}
```

**Result:** Enhanced with sidecar support
- Two containers in task definition (main + sidecar)
- Additional CloudWatch log groups for sidecar
- Both containers share secrets, environment, timeouts
- All original features still work

## Service Type Compatibility

### Standard Service

```hcl
service_type = "service"  # Default

sidecar_container = {
  name  = "nginx-proxy"
  image = "nginx:latest"
  port  = "80"
}
```
✅ Works - Sidecar gets load balancer access if configured

### Service Without Load Balancer

```hcl
service_type = "service_no_load_balancer"

sidecar_container = {
  name  = "log-shipper"
  image = "fluent/fluent-bit:latest"
}
```
✅ Works - Sidecar runs alongside main container

### Scheduled Task

```hcl
service_type        = "scheduled_task"
schedule_expression = "rate(1 hour)"

sidecar_container = {
  name  = "cleanup-helper"
  image = "my-cleanup:latest"
}
```
✅ Works - Both containers run on schedule

## Resource Usage

### Main Container Only
- CPU: As specified in `cpu` variable
- Memory: As specified in `memory` variable
- Total task resources: CPU + Memory

### Main + Sidecar
- Main CPU: As specified in `cpu` variable
- Sidecar CPU: As specified in `sidecar_container.cpu` (or defaults to main `cpu`)
- Total task resources: Main CPU + Sidecar CPU + Main Memory + Sidecar Memory

**Important:** Ensure your ECS cluster has sufficient capacity for the combined resource requirements.

## Shared vs. Unique Configuration

### Shared by Both Containers
- `application_secrets` - All secrets available to both
- `platform_secrets` - Platform-wide secrets
- `custom_secrets` - Custom secret paths
- `stop_timeout` - Same stop timeout
- `ulimits` - Same file descriptor limits
- `extra_hosts` - Same /etc/hosts entries
- `common_application_environment` - Base environment
- `application_environment` - Environment-specific vars

### Unique to Each Container
- `name` - Different container names
- `image` - Different Docker images
- `cpu` - Can be different (sidecar can default to main)
- `memory` - Can be different (sidecar can default to main)
- `port` / `port_mappings` - Different ports
- `map_environment` - Additional container-specific env vars
- `container_labels` - Additional container-specific labels
- `log_configuration` - Can override log config per container

## Migration Path

### Step 1: No Changes Required
Existing modules using terraform-iona-ecs-service work as-is with terraform-iona-ecs-service-2.

### Step 2: Add Sidecar When Needed
```hcl
# Original configuration...

# Add this block when you need a sidecar
sidecar_container = {
  name   = "your-sidecar"
  image  = "your-image:tag"
  cpu    = "128"
  memory = "256"
}
```

### Step 3: Deploy
The sidecar will be added to the task definition on the next apply.

## Testing Validation

```bash
# Clone and test
cd /Users/isaac.hollander/src
cp -r terraform-iona-ecs-service terraform-iona-ecs-service-2

cd terraform-iona-ecs-service-2

# Validate without sidecar
terraform init
terraform validate
# ✅ Success!

# Test with sidecar by creating a test module
# (See examples/with-sidecar.tf)
```
