job "{{BRANCH}}" {
  datacenters = ["dc1"]

  group "web" {
    network {
      port "http" { static = {{PORT}} }
    }

    task "app" {
      driver = "docker"

      config {
        image = "app1:{{BRANCH}}"
        ports = ["http"]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
