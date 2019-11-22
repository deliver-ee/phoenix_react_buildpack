load_previous_npm_node_versions() {
  if [ -f ${cache_path}/npm-version ]; then
    old_npm=$(<${cache_path}/npm-version)
  fi
  if [ -f ${cache_path}/npm-version ]; then
    old_node=$(<${cache_path}/node-version)
  fi
}

download_node() {
  local platform=linux-x64
  output_section "Fetching Node ${node_version}"

  cached_node=${cache_path}/$(node_download_file)

  if [ ! -f ${cached_node} ]; then
    echo "Resolving node version $node_version..."
    if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$node_version" "https://nodebin.herokai.com/v1/node/$platform/latest.txt"); then
      fail_bin_install node $node_version
    fi

    echo "Downloading node $number..."
    local code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o ${cached_node} --write-out "%{http_code}")
    if [ "$code" != "200" ]; then
      echo "Unable to download node: $code" && false
    fi
  else
    output_line "Using cached node ${node_version}..."
  fi
}

install_node() {
  output_section "Installing Node ${node_version}"

  cached_node=${cache_path}/$(node_download_file)

  tar xzf ${cached_node} -C /tmp

  if [ -d $(node_path) ]; then
    echo " !     Error while installing Node $node_version."
    echo "       Please remove any prior buildpack that installs Node."
    exit 1
  else
    mkdir -p $(node_path)
    # Move node (and npm) into .heroku/node and make them executable
    mv /tmp/node-v$node_version-linux-x64/* $(node_path)
    chmod +x $(node_path)/bin/*
    PATH=$(node_path)/bin:$PATH
  fi
}

install_yarn() {
  output_section "Installing Yarn ${yarn_version}"

  frontend_yarn="$(app_frontend_path)/yarn.lock"
  backend_yarn="$(app_backend_assets_path)/yarn.lock"

  if [ -f $frontend_yarn -a -f $backend_yarn ]; then

    if [ ! $yarn_version ]; then
      output_line "Downloading and installing yarn lastest..."
      local download_url="https://yarnpkg.com/latest.tar.gz"
    else
      output_line "Downloading and installing yarn $yarn_version..."
      local download_url="https://yarnpkg.com/downloads/$yarn_version/yarn-v$yarn_version.tar.gz"
    fi

    local code=$(curl "$download_url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/yarn.tar.gz --write-out "%{http_code}")

    if [ "$code" != "200" ]; then
      output_line "Unable to download yarn: $code" && false
    fi

    rm -rf $(yarn_path)
    mkdir -p "$(yarn_path)"
    tar xzf /tmp/yarn.tar.gz -C $(yarn_path) --strip 1
    chmod +x $(yarn_path)/bin/*
    PATH=$(yarn_path)/bin:$PATH

    output_line "Installed yarn $(yarn --version)"
  else
    output_line "Yarn not detected in project: No install needed."
  fi
}

install_frontend_deps() {
  output_section "Installing and caching frontend node modules"

  cd $(app_frontend_path)
  if [ -d ${cache_path}/front/node_modules ]; then
    mkdir -p node_modules
    cp -r ${cache_path}/front/node_modules/* node_modules/
  fi

  if [ -f "./yarn.lock" ]; then
    install_yarn_deps
  else
    install_npm_deps
  fi

  cp -r node_modules "${cache_path}/front"
  PATH=$(app_frontend_path)/node_modules/.bin:$PATH
}

install_backend_js_deps() {
  output_section "Installing and caching backend assets node modules"

  cd "$(app_backend_path)/${phx_assets_path}"
  if [ -d ${cache_path}/node_modules ]; then
    mkdir -p node_modules
    cp -r ${cache_path}/node_modules/* node_modules/
  fi

  if [ -f "./yarn.lock" ]; then
    install_yarn_deps
  else
    install_npm_deps
  fi

  cp -r node_modules "${cache_path}"
  PATH="$(app_backend_path)/${phx_assets_path}/node_modules/.bin":$PATH
}

install_npm_deps() {
  npm prune | indent
  npm install --only=production --quiet --unsafe-perm --userconfig build_path/npmrc 2>&1 | indent
  npm rebuild 2>&1 | indent
  npm --unsafe-perm prune 2>&1 | indent
}

install_yarn_deps() {
  yarn install --production --check-files --pure-lockfile 2>&1
}

compile_frontend() {
  output_section "Build frontend dist"

  cd $(app_frontend_path)
  if [ -f "./yarn.lock" ]; then
    REACT_APP_API_BASE_URL="/api" REACT_APP_GRAPHQL_URL="/graphql" yarn build
  else
    REACT_APP_API_BASE_URL="/api" REACT_APP_GRAPHQL_URL="/graphql" npm build
  fi
}

move_frontend_dist() {
  output_section "Move frontend dist to phoenix priv folder"

  cp -r $(app_frontend_path)/build "$(app_backend_path)/priv/static/app"
}

compile_backend_js() {
  output_section "Build and digest backend js"

  cd "$(app_backend_path)/${phx_assets_path}"

  if [ -f "./yarn.lock" ]; then
    yarn deploy
  else
    npm deploy
  fi

  cd "$(app_backend_path)"
  mix phx.digest
}

delete_node() {
  output_section "Deleting node at $(node_path)"
  rm -rf $(node_path)
}

cache_versions() {
  output_line "Caching versions for future builds"
  echo $(node --version) >${cache_path}/node-version
  echo $(npm --version) >${cache_path}/npm-version
}

function node_download_file() {
  echo node-v${node_version}-linux-x64.tar.gz
}
