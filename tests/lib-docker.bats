#!/usr/bin/env bats
# Тесты для lib/docker.sh: имя образа в устаревшем реестре, склейка и разбор ссылок.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/lib/docker.sh"
}

sh() {
  run bash -c "source '$LIB'; $*"
}

@test "image_name: собирает docker.pkg.github.com/<user>/<repo>/<repo>" {
  sh "docker_image_name moogur adminer"
  [ "$output" = "docker.pkg.github.com/moogur/adminer/adminer" ]
}

@test "ref: склеивает образ и тег через ':'" {
  sh "docker_ref docker.pkg.github.com/user/repo/repo v1.2.3"
  [ "$output" = "docker.pkg.github.com/user/repo/repo:v1.2.3" ]
}

@test "ref_image: часть до последнего ':'" {
  sh "docker_ref_image docker.pkg.github.com/user/repo/repo:v1.2.3"
  [ "$output" = "docker.pkg.github.com/user/repo/repo" ]
}

@test "ref_tag: часть после последнего ':'" {
  sh "docker_ref_tag docker.pkg.github.com/user/repo/repo:v1.2.3"
  [ "$output" = "v1.2.3" ]
}

@test "ref_image/ref_tag: обратимы относительно ref" {
  sh "ref=\$(docker_ref image v1); [ \"\$(docker_ref_image \"\$ref\")\" = image ] && [ \"\$(docker_ref_tag \"\$ref\")\" = v1 ]"
  [ "$status" -eq 0 ]
}
