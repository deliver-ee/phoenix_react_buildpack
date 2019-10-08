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
      info "Downloading and installing yarn lastest..."
      local download_url="https://yarnpkg.com/latest.tar.gz"
    else
      info "Downloading and installing yarn $yarn_version..."
      local download_url="https://yarnpkg.com/downloads/$yarn_version/yarn-v$yarn_version.tar.gz"
    fi

    local code=$(curl "$download_url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/yarn.tar.gz --write-out "%{http_code}")

    if [ "$code" != "200" ]; then
      info "Unable to download yarn: $code" && false
    fi

    rm -rf $(yarn_path)
    mkdir -p "$(yarn_path)"
    # https://github.com/yarnpkg/yarn/issues/770
    if tar --version | grep -q 'gnu'; then
      tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1 --warning=no-unknown-keyword
    else
      tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1
    fi
    chmod +x $(yarn_path)/bin/*
    PATH=$(yarn_path)/bin:$PATH

    info "Installed yarn $(yarn --version)"
  else
    info "Yarn not detected in project: No install needed."
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

  cd "${build_path}/${phx_assets_path}"
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
  PATH="${build_path}/${phx_assets_path}/node_modules/.bin":$PATH
}

install_npm_deps() {
  npm prune | indent
  npm install --quiet --unsafe-perm --userconfig build_path/npmrc 2>&1 | indent
  npm rebuild 2>&1 | indent
  npm --unsafe-perm prune 2>&1 | indent
}

install_yarn_deps() {
  yarn install --check-files --cache-folder ${cache_path}/yarn-cache --pure-lockfile 2>&1
}

compile_frontend() {
  output_section "Build frontend dist"

  cd $(app_frontend_path)
  if [ -f "./yarn.lock" ]; then
    yarn build
  else
    npm build
  fi
}

move_frontend_dist() {
  output_section "Move frontend dist to phoenix priv folder"

  mv $(app_frontend_path)/build "${build_path}priv/front"
}

compile_backend_js() {
  output_section "Build and digest backend js"

  cd "${build_path}/${phx_assets_path}"

  if [ -f "./yarn.lock" ]; then
    yarn deploy
  else
    npm deploy
  fi

  mix phx.digest
}

compile() {
  cd $phoenix_dir
  PATH=$build_dir/.platform_tools/erlang/bin:$PATH
  PATH=$build_dir/.platform_tools/elixir/bin:$PATH

  run_compile
}

run_compile() {
  local custom_compile="${build_dir}/${compile}"

  cd $phoenix_dir

  has_clean=$(
    mix help "${phoenix_ex}.digest.clean" 1>/dev/null 2>&1
    echo $?
  )

  if [ $has_clean = 0 ]; then
    mkdir -p ${cache_path}/phoenix-static
    output_line "Restoring cached assets"
    mkdir -p priv
    rsync -a -v --ignore-existing ${cache_path}/phoenix-static/ priv/static
  fi

  cd $assets_dir

  if [ -f $custom_compile ]; then
    output_line "Running custom compile"
    source $custom_compile 2>&1 | indent
  else
    output_line "Running default compile"
    source ${build_pack_dir}/${compile} 2>&1 | indent
  fi

  cd $phoenix_dir

  if [ $has_clean = 0 ]; then
    output_line "Caching assets"
    rsync -a --delete -v priv/static/ ${cache_path}/phoenix-static
  fi
}

cache_versions() {
  output_line "Caching versions for future builds"
  echo $(node --version) >${cache_path}/node-version
  echo $(npm --version) >${cache_path}/npm-version
}

finalize_node() {
  if [ $remove_node = true ]; then
    remove_node
  else
    write_profile
  fi
}

#write_profile() {
#  output_line "Creating runtime environment"
#  mkdir -p $build_dir/.profile.d
#  local export_line="export PATH=\"\$HOME/.heroku/node/bin:\$HOME/.heroku/yarn/bin:\$HOME/bin:\$HOME/$phoenix_relative_path/node_modules/.bin:\$PATH\""
#  echo $export_line >>$build_dir/.profile.d/phoenix_static_buildpack_paths.sh
#}

#remove_node() {
#  output_line "Removing node and node_modules"
#  rm -rf $assets_dir/node_modules
#  rm -rf $heroku_dir/node
#}

function node_download_file() {
  echo node-v${node_version}-linux-x64.tar.gz
}
