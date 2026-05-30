output "resource_group_name" {
  description = "Name of the provisioned resource group"
  value       = azurerm_resource_group.rg.name
}

output "function_app_name" {
  description = "Name of the Function App — used in the func CLI deploy command"
  value       = azurerm_windows_function_app.func.name
}

output "function_app_url" {
  description = "Base URL of the Function App"
  value       = "https://${azurerm_windows_function_app.func.default_hostname}"
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.ai.connection_string
  sensitive   = true
}