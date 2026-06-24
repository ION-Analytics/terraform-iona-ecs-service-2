# Multi-Container ECS Service Example

This example demonstrates using `multiple_images = true` to deploy multiple containers within a single ECS task.

## Scenario

Deploy two containers in a single task:
- **app-a**: Main application listening on port 8080, connected to 3 target groups (2 on internal ALB, 1 on external ALB)
- **app-b**: Sidecar service listening on port 9090, connected to 1 target group on internal ALB

## Configuration

```hcl
# Target groups (assumed to exist)
resource "aws_alb_target_group" "app_a_internal_primary" {
  name     = "app-a-internal-primary"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }
}

resource "aws_alb_target_group" "app_a_internal_secondary" {
  name     = "app-a-internal-secondary"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_alb_target_group" "app_a_external" {
  name     = "app-a-external"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_alb_target_group" "app_b" {
  name     = "app-b"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

# Multi-container ECS service
module "multi_container_service" {
  source = "ION-Analytics/ecs-service/iona"

  multiple_images = true

  tasks = [
    {
      image  = "123456789.dkr.ecr.us-west-2.amazonaws.com/my-app:v1.0"
      cpu    = "512"
      memory = "1024"
      
      # Single port
      port = "8080"
      
      # Multiple target groups for this container
      target_group_arns = [
        aws_alb_target_group.app_a_internal_primary.arn,
        aws_alb_target_group.app_a_internal_secondary.arn,
        aws_alb_target_group.app_a_external.arn,
      ]
      
      # Container-specific settings
      privileged         = false
      nofile_soft_ulimit = "8192"
      stop_timeout       = "30"
      
      container_labels = {
        "app.role" = "primary"
      }
    },
    {
      image  = "123456789.dkr.ecr.us-west-2.amazonaws.com/sidecar:v2.0"
      cpu    = "256"
      memory = "512"
      port   = "9090"
      
      # Single target group for this container
      target_group_arns = [
        aws_alb_target_group.app_b.arn,
      ]
      
      container_labels = {
        "app.role" = "sidecar"
      }
    },
  ]

  # Shared configuration
  env             = terraform.workspace
  ecs_cluster     = "my-cluster"
  release = {
    component = "my-service"
    team      = "my-team"
    version   = "1.0.0"
    image_id  = "" # Not used when multiple_images = true
  }
  platform_config = module.platform_config.config

  # Shared environment variables
  common_application_environment = {
    LOG_LEVEL = "info"
  }

  application_environment = {
    ENVIRONMENT = terraform.workspace
  }

  # Shared secrets
  application_secrets = ["DATABASE_URL", "API_KEY"]
  platform_secrets    = ["DATADOG_API_KEY"]
}
```

## Container Naming

With the configuration above, containers will be named:
- `my-service-my-app` (extracted from `my-app:v1.0`)
- `my-service-sidecar` (extracted from `sidecar:v2.0`)

## Advanced: Multiple Port Mappings

To expose multiple ports from a single container, use `container_port_mappings`:

```hcl
tasks = [
  {
    image  = "123456789.dkr.ecr.us-west-2.amazonaws.com/multi-port-app:v1.0"
    cpu    = "512"
    memory = "1024"
    
    # Use container_port_mappings for multiple ports (overrides port)
    container_port_mappings = jsonencode([
      { containerPort = 8080, protocol = "tcp" },
      { containerPort = 8081, protocol = "tcp" },
      { containerPort = 9090, protocol = "udp" },
    ])
    
    target_group_arns = [
      aws_alb_target_group.http_primary.arn,
      aws_alb_target_group.http_secondary.arn,
    ]
  }
]
```

## Important Notes

1. **Desired Count**: When `multiple_images = true`, the service's `desired_count` is automatically set to `1`. Each task instance runs all containers.

2. **Ignored Variables**: When `multiple_images = true`, the following root-level variables are ignored:
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

3. **Shared Configuration**: All containers share:
   - Environment variables
   - Secrets
   - Logging configuration
   - Volume mounts
   - Base Docker labels

4. **Service Types**: Multi-container tasks work with all service types:
   - `service` (single load balancer)
   - `service_multiple_load_balancers`
   - `service_no_load_balancer`
   - `service_for_awsvpc_no_loadbalancer`
   - `scheduled_task`

5. **Validation**: The module validates that:
   - When `multiple_images = true`, the `tasks` list must not be empty
   - When `multiple_images = false`, the `tasks` list must be empty
