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
  workspace_id        = azurerm_log_analytics_workspace.this.id
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
