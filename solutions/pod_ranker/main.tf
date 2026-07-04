resource "kubernetes_namespace" "pod_ranker" {
  metadata {
    name = "pod-ranker"
  }
}

resource "kubernetes_config_map" "pod_ranker_cm" {
  metadata {
    name      = "pod-ranker"
    namespace = kubernetes_namespace.pod_ranker.metadata[0].name
  }

  data = {
    OLD_PODS_COUNT  = "1"
    "pod_ranker.sh" = file("${path.module}/scripts/pod_ranker.sh")
  }
}

resource "kubernetes_service_account" "pod_ranker_sa" {
  metadata {
    name      = "pod-ranker"
    namespace = kubernetes_namespace.pod_ranker.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "pod_ranker_cr" {
  metadata {
    name = "pod-ranker"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "pod_ranker_rb" {
  metadata {
    name = "pod-ranker"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.pod_ranker_sa.metadata[0].name
    namespace = kubernetes_namespace.pod_ranker.metadata[0].name
  }

  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.pod_ranker_cr.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

data "aws_caller_identity" "current" {}

resource "kubernetes_cron_job_v1" "pod_ranker" {
  metadata {
    name      = "pod-ranker"
    namespace = kubernetes_namespace.pod_ranker.metadata[0].name
  }

  spec {
    schedule = "*/15 * * * *"

    job_template {
      metadata {
        name = "pod-ranker-job"
      }
      spec {
        template {
          metadata {
            labels = {
              app_name = "pod-ranker"
            }
          }
          spec {
            service_account_name = "pod-ranker"
            restart_policy       = "OnFailure"

            container {
              name              = "kubectl"
              image             = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/utils:master-4a2b269-kubectl"
              image_pull_policy = "IfNotPresent"

              env {
                name = "OLD_PODS_COUNT"
                value_from {
                  config_map_key_ref {
                    name = kubernetes_config_map.pod_ranker_cm.metadata[0].name
                    key  = "OLD_PODS_COUNT"
                  }
                }
              }

              command = ["/bin/bash", "-c", "bash /scripts/pod_ranker.sh"]

              volume_mount {
                name       = "script-volume"
                mount_path = "/scripts"
              }
            }

            volume {
              name = "script-volume"
              config_map {
                name = kubernetes_config_map.pod_ranker_cm.metadata[0].name
                items {
                  key  = "pod_ranker.sh"
                  path = "pod_ranker.sh"
                }
              }
            }
          }
        }
      }
    }
  }
}


