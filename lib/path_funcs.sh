function platform_tools_path() {
  echo "${build_path}/.platform_tools"
}

function erlang_path() {
  echo "$(platform_tools_path)/erlang"
}

function runtime_platform_tools_path() {
  echo "${runtime_path}/.platform_tools"
}

function runtime_erlang_path() {
  echo "$(runtime_platform_tools_path)/erlang"
}

function elixir_path() {
  echo "$(platform_tools_path)/elixir"
}

function node_path() {
  echo "$(platform_tools_path)/node"
}

function yarn_path() {
  echo "$(platform_tools_path)/yarn"
}

function erlang_build_path() {
  echo "${cache_path}/erlang"
}

function deps_backup_path() {
  echo "${cache_path}/deps_backup"
}

function build_backup_path() {
  echo "${cache_path}/build_backup"
}

function mix_backup_path() {
  echo "${cache_path}/.mix"
}

function hex_backup_path() {
  echo "${cache_path}/.hex"
}

function app_frontend_path() {
  echo "${build_path}/front"
}

function app_backend_path() {
  echo "${build_path}/back"
}

function app_backend_assets_path() {
  echo "${build_path}/back/${phx_assets_path}"
}
