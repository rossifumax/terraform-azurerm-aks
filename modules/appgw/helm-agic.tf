resource "kubernetes_namespace" "agic" {
  metadata {
    name = "system-agic"
    labels = {
      deployed-by = "Terraform"
    }
  }
}

resource "azurerm_role_assignment" "agic" {
  principal_id         = var.aks_aad_pod_identity_principal_id
  scope                = azurerm_application_gateway.app_gateway.id
  role_definition_name = "Contributor"
}

data "azurerm_resource_group" "appgw-rg" {
  name = var.rg_name
}

resource "azurerm_role_assignment" "agic-rg" {
  principal_id         = var.aks_aad_pod_identity_principal_id
  scope                = data.azurerm_resource_group.appgw-rg.id
  role_definition_name = "Reader"
}

data "helm_repository" "agic" {
  name = "agic"
  url  = "https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/"
}

data "azurerm_subscription" "current" {}

resource "helm_release" "agic" {
  depends_on = [azurerm_role_assignment.agic, azurerm_role_assignment.agic-rg, null_resource.install_crd]
  name       = "ingress-azure"
  repository = data.helm_repository.agic.metadata.0.name
  chart      = "ingress-azure"
  namespace  = kubernetes_namespace.agic.metadata.0.name


  dynamic "set" {
    for_each = local.appgw_ingress_settings
    iterator = setting
    content {
      name  = setting.key
      value = setting.value
    }
  }
}

resource "random_string" "kube-config-file-name" {
  length  = 10
  special = false
}

// FIXME https://github.com/Azure/application-gateway-kubernetes-ingress/issues/720
resource "null_resource" "install_crd" {
  // Get AKS Credentials
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${var.rg_name} --name ${var.aks_name} --admin -f /tmp/${random_string.kube-config-file-name.result}"
  }

  provisioner "local-exec" {
    command     = "KUBECONFIG=/tmp/${random_string.kube-config-file-name.result} kubectl apply -f https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/crds/AzureIngressProhibitedTarget.yaml"
    interpreter = ["bash", "-c"]
  }
}