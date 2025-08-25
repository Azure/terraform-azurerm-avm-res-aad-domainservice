# Graph provider still in Beta release, will include this functionality after GA.
provider "msgraph" {
}

# TODO: 
# 1. Add scoped synchronization in Graph
# 2. Add the creation of the required AD group "AAD DC Administrators" https://docs.azure.cn/en-us/entra/identity/domain-services/powershell-create-instance#create-required-microsoft-entra-resources
# 2.1. Add the required users to the group

#Create an application in Microsoft Graph to use with Azure AD Domain Services extensions. All extentions must be associated with an app.
# See documentation: 
# Deploying apps with MS Graph Terraform provider: https://learn.microsoft.com/en-us/graph/templates/terraform/reference/v1.0/applications#microsoftgraphrequiredresourceaccess
# Peremission granting reference: 
#  1. https://learn.microsoft.com/en-us/graph/permissions-reference   
#  2. https://learn.microsoft.com/en-us/graph/permissions-reference
# How to manage extensions in Entra: https://learn.microsoft.com/en-us/graph/extensibility-overview?utm_source=chatgpt.com&tabs=http

# Create the application to hold the extensions + grant permissions to write extensions on all users
# TODO: allow 

resource "msgraph_resource" "aad_sync_app" {
  url = "servicePrincipals"

  body = {
    "appId" : "2565bd9d-da50-47d4-8b85-4c97f669dc36"
  }
}

# This is the managed application, imported into terraform and then we can control the extensions
# import command: terraform import msgraph_resource.graph_app_managed "applications/2565bd9d-da50-47d4-8b85-4c97f669dc36" <- app id can probably be fetched dynamically
# Add extensions with addins, remove by removing the internal extension definition and leaving the addin
resource "msgraph_resource" "graph_app_managed" {
  url = "applications"

  body = {
    # displayName = "Azure AD Domain Services Sync"
    addIns = [
      {
        id = "3d079dc9-9db2-4234-a219-a84094f4d4a8" # This is the ID of the add-in that allows for AADDS custom attributes
        properties = [
          {
            key   = "directoryExtension"
            value = "extension_4df2d7f54df14446aef73041b9c85eb9_fromTerraformTestExt" # This is the name of the extension property to be created
          }
        ]
        type = "AADDSCustomAttributes"
      }
    ]
  }

  lifecycle {
    ignore_changes = [
      body.DisplayName
    ]
  }
}

# This is an app for creating custom user extentions
resource "msgraph_resource" "graph_app_addins" {
  url = "applications"

  body = {
    displayName = "appFromTerraform"
    uniqueName  = "appFromTerraform"
    description = "This app was created by Terraform Graph API provider"
    requiredResourceAccess = [
      {
        resourceAccess = [
          {
            id   = "741f803b-c850-494e-b5df-cde7c675a1ca" # App id to give User.ReadWrite.All and is constant across tenants
            type = "Role"
          }
        ]
        resourceAppId = "00000003-0000-0000-c000-000000000000" # This is the application ID of Microsoft Graph and is constant across tenants. 
      }
    ]
  }
}

# Create the extension property for the application
resource "msgraph_resource" "application_extensionProperties" {
  url = "applications/${resource.msgraph_resource.graph_app_addins.id}/extensionProperties"

  body = {
    "name" : "fromTerraformTestExt",
    "dataType" : "String",
    "targetObjects" : [
      "User"
    ]
  }
}


#############################################################################################
# Group filtering
# raw request from network recording
# {"requests":[{"url":"/servicePrincipals/e95b152d-b7c1-40c0-b8c1-f014723b16f6/appRoleAssignments/","method":"POST","id":"1","body":{"appRoleId":"e7bdf2ef-aa80-4a18-9801-0aa9e01feb8c","principalId":"ef4127e9-4ec8-4e6e-964b-0ab33a8e42cc","resourceId":"e95b152d-b7c1-40c0-b8c1-f014723b16f6"},"headers":{"Content-Type":"application/json","Accept":"application/json"}}]}

resource "msgraph_resource" "aad_filters" {
  url = "/servicePrincipals/e95b152d-b7c1-40c0-b8c1-f014723b16f6/appRoleAssignments"

  body = {
    appRoleId   = "e7bdf2ef-aa80-4a18-9801-0aa9e01feb8c"
    principalId = "ef4127e9-4ec8-4e6e-964b-0ab33a8e42cc"
    resourceId  = "e95b152d-b7c1-40c0-b8c1-f014723b16f6"
  }
}