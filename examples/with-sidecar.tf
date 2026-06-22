# Example: ECS Service with Sidecar Container
#
# This example shows how to deploy an application with a sidecar container
# for metrics collection or logging

module "app_with_sidecar" {
  source = "../"

  env = "dev"

  release = {
    component = "my-app"
    team      = "platform"
    version   = "1.0.0"
    image_id  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:1.0.0"
  }

  # Main container configuration
  cpu    = "512"
  memory = "1024"
  port   = "8080"

  ecs_cluster                  = "my-cluster"
  target_group_arn             = "arn:aws:elasticloadbalancing:..."
  network_configuration_subnets         = ["subnet-12345", "subnet-67890"]
  network_configuration_security_groups = ["sg-12345"]

  desired_count = 3

  platform_config = {
    datadog_log_subscription_arn = ""
  }

  application_environment = {
    APP_PORT = "8080"
    LOG_LEVEL = "info"
  }

  # Sidecar container for metrics export
  sidecar_container = {
    name   = "prometheus-exporter"
    image  = "prom/statsd-exporter:v0.26.0"
    cpu    = "128"
    memory = "256"
    port   = "9102"

    map_environment = {
      STATSD_LISTEN_UDP = "0.0.0.0:8125"
      PROM_LISTEN_HTTP  = "0.0.0.0:9102"
    }

    container_labels = {
      purpose = "metrics"
    }
  }
}

# Example output showing both containers are deployed
output "task_definition_arn" {
  value = module.app_with_sidecar.task_definition_arn
}

output "service_name" {
  value = module.app_with_sidecar.name
}
