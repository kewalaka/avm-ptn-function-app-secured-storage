locals {
  endpoints = toset(["blob", "queue", "table", "file"])
}

# https://learn.microsoft.com/en-us/azure/azure-functions/configure-networking-how-to?tabs=portal#secure-storage-during-function-app-creation
module "storage_account" {
  # TODO replace with 0.1.2 when it is published - this is needed to fix an issue in 0.1.1
  source = "git::https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount?ref=5c5af3b08b3b4f60ab4fb3315a2079b672bca38d"
  #version                  = "~> 0.1.2"
  account_replication_type      = "LRS"
  name                          = var.function_app_storage_account_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  public_network_access_enabled = false
  # this is necessary as managed identity does work with Elastic Premium Plans due to missing authentication support in Azure Files
  shared_access_key_enabled = true


  private_endpoints = {
    for endpoint in local.endpoints :
    endpoint => {
      name                          = "pe-${endpoint}-${var.function_app_storage_account_name}"
      subnet_resource_id            = var.private_endpoint_subnet_resource_id
      subresource_name              = [endpoint]
      private_dns_zone_resource_ids = ["/subscriptions/${var.private_dns_zone_subscription_id}/resourceGroups/${var.private_dns_zone_resource_group_name}/providers/Microsoft.Network/privateDnsZones/privatelink.${endpoint}.core.windows.net"]
      tags                          = var.tags
    }
  }

  role_assignments = {
    storage_blob_data_owner = {
      role_definition_id_or_name = "Storage Blob Data Owner"
      principal_id               = module.function_app.resource.identity[0].principal_id
    }
    storage_account_contributor = {
      role_definition_id_or_name = "Storage Account Contributor"
      principal_id               = module.function_app.resource.identity[0].principal_id
    }
    storage_queue_data_contributor = {
      role_definition_id_or_name = "Storage Queue Data Contributor"
      principal_id               = module.function_app.resource.identity[0].principal_id
    }
  }

  shares = {
    function_app_share = {
      name  = var.function_app_storage_account_name
      quota = 100
    }
  }

  tags = var.tags
}

module "function_app" {
  #source  = "Azure/avm-res-web-site/azurerm"
  #version = "0.1.2"
  source = "git::https://github.com/kewalaka/terraform-azurerm-avm-res-web-site.git?ref=fix/system_assigned_mi_docs_error"


  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  https_only                    = true
  os_type                       = var.os_type # "Linux" / "Windows" / azurerm_service_plan.example.os_type
  public_network_access_enabled = false
  service_plan_resource_id      = var.service_plan_resource_id

  storage_account_name          = module.storage_account.name
  storage_uses_managed_identity = true
  #storage_account_access_key = module.storage_account.resource.primary_connection_string

  managed_identities = {
    system_assigned = true
  }

  private_endpoints = {
    primary = {
      name                          = "pe-${var.name}"
      private_dns_zone_resource_ids = ["/subscriptions/${var.private_dns_zone_subscription_id}/resourceGroups/${var.private_dns_zone_resource_group_name}/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"]
      subnet_resource_id            = var.private_endpoint_subnet_resource_id
      tags                          = var.tags
    }
  }

  site_config = merge(
    var.site_config,
    {
      # application_insights_connection_string = ""
      vnet_route_all_enabled = true
    }
  )

  # https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings
  app_settings = merge(
    var.app_settings,
    {

      # these are used by managed identity, but MI can only be used on dedicated plans, not on elastic premium
      # ref: # https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings     
      AzureWebJobsStorage__blobServiceUri  = "https://${module.storage_account.name}.blob.core.windows.net"
      AzureWebJobsStorage__queueServiceUri = "https://${module.storage_account.name}.queue.core.windows.net"
      AzureWebJobsStorage__tableServiceUri = "https://${module.storage_account.name}.table.core.windows.net"

      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = module.storage_account.resource.primary_connection_string
      WEBSITE_CONTENTSHARE                     = var.function_app_storage_account_name

      WEBSITE_CONTENTOVERVNET = 1
    }
  )
}
