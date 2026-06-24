## First locals block replicates the things going into the original
## container-definition module.

locals {
  team        = lookup(var.docker_labels, "team", "")
  env         = lookup(var.docker_labels, "env", "")
  component   = lookup(var.docker_labels, "component", "")
  extra_hosts = jsonencode(var.extra_hosts)
}

## Data resources locate platform and application secret ARNs
## Mirroring the rigid path definitions from the original module

## var.application_secrets and var.platform_secrets are both lists of secret names
## i.e.: ["PLATFORM_SECRET_1", "PLATFORM_SECRET_2", etc... ]
# The data resource builds the complete name and returns the ARN

data "aws_secretsmanager_secret" "secret" {
  count = length(var.application_secrets)
  name  = "${local.team}/${local.env}/${local.component}/${element(var.application_secrets, count.index)}"
}

data "aws_secretsmanager_secret" "platform_secrets" {
  count = length(var.platform_secrets)
  name  = "platform_secrets/${element(var.platform_secrets, count.index)}"
}

## Attempt at doing a custom secrets path
data "aws_secretsmanager_secret" "custom_secrets" {
  count = length(var.custom_secrets)
  name  = element(var.custom_secrets, count.index)
}

## Second local block uses the above data resources to format the map of 
## environment variable to ARN, but not in a way that AWS will understand yet
## i.e.: { PLATFORM_SECRET_1 = "arn:aws:secretsmanager:us-west-2:254076036999:secret:capplatformbsg/sfrazer-test/container-def-testing/PLATFORM_SECRET_1-nAUu3i"}

locals {
  sorted_application_secrets = {
    for k, v in data.aws_secretsmanager_secret.secret :
    element(split("/", v.name), 3) => "${v.arn}"
  }

  sorted_platform_secrets = {
    for k, v in data.aws_secretsmanager_secret.platform_secrets :
    element(split("/", v.name), 1) => "${v.arn}"
  }

  ## Future attempt at doing a custom secrets path
  sorted_custom_secrets = {
    for k, v in data.aws_secretsmanager_secret.custom_secrets :
    element(split("/", v.name), length(split("/", v.name)) - 1) => "${v.arn}"
  }

  final_secrets = merge(local.sorted_application_secrets, local.sorted_platform_secrets, local.sorted_custom_secrets)
}

## The remainder of this file is cribbed from the cloudposse implementation originally at:
## https://github.com/cloudposse/terraform-aws-ecs-container-definition/blob/main/main.tf
## with some additional comments thrown in

locals {
  ## This part allows us to submit environment and secrets as either a map of strings. i.e.:
  ##  { STATSD_HOST = "172.17.42.1" }
  ## or a list of objects, each containing 2 maps. i.e.:
  ##  [
  ##    { name = "STATSD_HOST" value = "172.17.42.1" }
  ##  ]
  ## with the former taking precedence if both are submitted.
  ## The original code for secrets was changed to match our secrets format

  # Sort environment variables & secrets so terraform will not try to recreate on each plan/apply
  ## This is a useful step as randomly applying the order results in unnecessary restarts
  env_as_map     = var.map_environment != null ? var.map_environment : var.environment != null ? { for m in var.environment : m.name => m.value } : null
  secrets_as_map = local.final_secrets != null ? local.final_secrets : null

  ## This part then takes the output from above and turns it into the object form that the container_definition expects
  # https://www.terraform.io/docs/configuration/expressions.html#null
  final_environment_vars = local.env_as_map != null ? [
    for k, v in local.env_as_map :
    {
      name  = k
      value = v
    }
  ] : null
  final_secrets_vars = local.secrets_as_map != null ? [
    for k, v in local.final_secrets :
    {
      name      = k
      valueFrom = v
    }
  ] : null

  ## Log configuration object
  ## For more details, see https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html"
  ## and firelens: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_FirelensConfiguration.html
  log_configuration_without_null = var.log_configuration == null ? null : {
    for k, v in var.log_configuration :
    k => v
    if v != null
  }
  user = var.firelens_configuration != null ? "0" : var.user

  ## Restart policy
  ## https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerRestartPolicy.html
  restart_policy_without_null = var.restart_policy == null ? null : {
    for k, v in var.restart_policy :
    k => v
    if v != null
  }

  ## With all the preliminary massaging out of the way, we move to the complete container definition
  ## generated from the individual variables:

  container_definition = {
    name                   = var.container_name
    image                  = var.container_image
    essential              = var.essential
    entryPoint             = var.entrypoint
    command                = var.command
    workingDirectory       = var.working_directory
    readonlyRootFilesystem = var.readonly_root_filesystem
    mountPoints            = var.mount_points
    dnsServers             = var.dns_servers
    dnsSearchDomains       = var.dns_search_domains
    ulimits                = var.ulimits
    repositoryCredentials  = var.repository_credentials
    links                  = var.links
    volumesFrom            = var.volumes_from
    user                   = local.user
    dependsOn              = var.container_depends_on
    privileged             = var.privileged
    portMappings           = var.port_mappings
    healthCheck            = var.healthcheck
    firelensConfiguration  = var.firelens_configuration
    linuxParameters        = var.linux_parameters
    logConfiguration       = local.log_configuration_without_null
    memory                 = var.container_memory
    memoryReservation      = var.container_memory_reservation
    cpu                    = var.container_cpu
    environment            = local.final_environment_vars
    environmentFiles       = var.environment_files
    secrets                = local.final_secrets_vars
    dockerLabels           = var.docker_labels
    startTimeout           = var.start_timeout
    stopTimeout            = var.stop_timeout
    systemControls         = var.system_controls
    extraHosts             = var.extra_hosts
    hostname               = var.hostname
    disableNetworking      = var.disable_networking
    interactive            = var.interactive
    pseudoTerminal         = var.pseudo_terminal
    dockerSecurityOptions  = var.docker_security_options
    resourceRequirements   = var.resource_requirements
    restartPolicy          = local.restart_policy_without_null
    versionConsistency     = var.version_consistency
  }

  ## It's possible (probable) that some of those values are null and AWS won't like that, so this removes any null parameters

  container_definition_without_null = {
    for k, v in local.container_definition :
    k => v
    if v != null
  }

  ## So... What if we wanted to pass a complete object to this module and just spit it back out?
  ## This ensures that any nulls from that are removed
  container_definition_override_without_null = {
    for k, v in var.container_definition :
    k => v
    if v != null
  }

  ## Now merge the two together, allowing us to have passed a variable object and several standalone
  ## variable separately, but still have them show up in the returned definition.
  ## We could probably get rid of that and the HUGE object in variables if we wanted to enforce
  ## configuration by individual variable

  final_container_definition = merge(local.container_definition_without_null, local.container_definition_override_without_null)

  ## Encode the json to return
  ## Note in outputs.tf there are actually 6 ways to request the returned definition, 3 marked "sensitive" and 3 regular
  ## The json_map_encoded_list or sensitive_json_map_encoded_list are the ones that fit into our current taskdef module.

  json_map = jsonencode(local.final_container_definition)
}
