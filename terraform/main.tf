# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project}-${var.environment}-${var.location_short}"
  location = var.location

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Storage Account
# (required by Azure Functions runtime)
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "sa" {
  name                     = "st${var.project}${var.environment}${var.location_short}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable public blob access — functions runtime uses account key internally
  allow_nested_items_to_be_public = false

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Application Insights
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

resource "azurerm_application_insights" "ai" {
  name                = "appi-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id

  tags = var.tags
}
# resource "azurerm_application_insights" "ai" {
#   name                = "appi-${var.project}-${var.environment}-${var.location_short}"
#   resource_group_name = azurerm_resource_group.rg.name
#   location            = azurerm_resource_group.rg.location
#   application_type    = "web"
# 
#   tags = var.tags
# }

# ---------------------------------------------------------------------------
# Consumption Plan (Free Tier — Y1)
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "plan" {
  name                = "asp-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "Y1" # Consumption (Free) plan

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Function App
# ---------------------------------------------------------------------------
resource "azurerm_windows_function_app" "func" {
  name                = "func-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.plan.id

  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key

  site_config {
    application_stack {
      dotnet_version              = "v8.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.ai.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
    FUNCTIONS_EXTENSION_VERSION           = "~4"
    FUNCTIONS_WORKER_RUNTIME              = "dotnet-isolated"
  }

  tags = var.tags
}