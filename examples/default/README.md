<!-- BEGIN_TF_DOCS -->
# Default example

This deploys the pattern in its simplest form.

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.97.0"
    }
  }
}

provider "azurerm" {
  features {
  }
  skip_provider_registration = true
}

data "azurerm_client_config" "this" {}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = ">= 0.3.0"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = "AustraliaEast"
  name     = module.naming.resource_group.name_unique
}

# A vnet is required for the private endpoint.
resource "azurerm_virtual_network" "this" {
  address_space       = ["192.168.0.0/24"]
  location            = azurerm_resource_group.this.location
  name                = module.naming.virtual_network.name_unique
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "this" {
  address_prefixes     = ["192.168.0.0/25"]
  name                 = module.naming.subnet.name_unique
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
}

resource "azurerm_subnet" "app_service" {
  address_prefixes     = ["192.168.0.128/25"]
  name                 = "${module.naming.subnet.name_unique}-appservice"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  delegation {
    name = "Microsoft.Web/serverFarms"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}


# We make private DNS zones to be able to run the end to end tests
resource "azurerm_private_dns_zone" "function_app" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.this.name
}

locals {
  endpoints = toset(["blob", "queue", "table", "file"])
}

resource "azurerm_private_dns_zone" "storage_account" {
  for_each = local.endpoints

  name                = "privatelink.${each.value}.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

# add app insights
resource "azurerm_log_analytics_workspace" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.log_analytics_workspace.name_unique
  resource_group_name = azurerm_resource_group.this.name
  retention_in_days   = 30
  sku                 = "PerGB2018"
}

resource "azurerm_application_insights" "this" {
  name                = module.naming.application_insights.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.workspace_id
}


# pre-requisites for app services
resource "azurerm_service_plan" "this" {
  name                = module.naming.app_service_plan.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "EP1"
}

# This is the module call
# Do not specify location here due to the randomization above.
# Leaving location as `null` will cause the module to use the resource group location
# with a data source.
module "function_app_secured_storage" {
  source = "../../"
  # source             = "Azure/avm-ptn-function-app-secured-storage/azurerm"
  # ...
  name                                 = module.naming.function_app.name_unique
  location                             = azurerm_resource_group.this.location
  resource_group_name                  = azurerm_resource_group.this.name
  private_dns_zone_resource_group_name = azurerm_resource_group.this.name
  private_dns_zone_subscription_id     = data.azurerm_client_config.this.subscription_id
  function_app_storage_account_name    = module.naming.storage_account.name_unique
  os_type                              = "Linux"
  service_plan_resource_id             = azurerm_service_plan.this.id
  private_endpoint_subnet_resource_id  = azurerm_subnet.this.id
  virtual_network_subnet_id            = azurerm_subnet.app_service.id

  site_config = {
    application_insights_connection_string = azurerm_application_insights.this.connection_string
  }
}
```

<!-- markdownlint-disable MD033 -->
## Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) (>= 1.5.0)

- <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) (~> 3.97.0)

## Providers

The following providers are used by this module:

- <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) (~> 3.97.0)

## Resources

The following resources are used by this module:

- [azurerm_application_insights.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) (resource)
- [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) (resource)
- [azurerm_private_dns_zone.function_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) (resource)
- [azurerm_private_dns_zone.storage_account](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) (resource)
- [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) (resource)
- [azurerm_service_plan.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) (resource)
- [azurerm_subnet.app_service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) (resource)
- [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) (resource)
- [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) (resource)
- [azurerm_client_config.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) (data source)

<!-- markdownlint-disable MD013 -->
## Required Inputs

No required inputs.

## Optional Inputs

No optional inputs.

## Outputs

No outputs.

## Modules

The following Modules are called:

### <a name="module_function_app_secured_storage"></a> [function\_app\_secured\_storage](#module\_function\_app\_secured\_storage)

Source: ../../

Version:

### <a name="module_naming"></a> [naming](#module\_naming)

Source: Azure/naming/azurerm

Version: >= 0.3.0

<!-- markdownlint-disable-next-line MD041 -->
## Data Collection

The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services. You may turn off the telemetry as described in the repository. There are also some features in the software that may enable you and Microsoft to collect data from users of your applications. If you use these features, you must comply with applicable law, including providing appropriate notices to users of your applications together with a copy of Microsoft’s privacy statement. Our privacy statement is located at <https://go.microsoft.com/fwlink/?LinkID=824704>. You can learn more about data collection and use in the help documentation and our privacy statement. Your use of the software operates as your consent to these practices.
<!-- END_TF_DOCS -->