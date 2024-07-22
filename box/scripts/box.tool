#!/system/bin/sh

scripts_dir="${0%/*}"
source /data/adb/box/settings.ini

# user agent
user_agent="box_for_magisk"
# whether use ghproxy to accelerate github download
url_ghproxy="https://mirror.ghproxy.com"
use_ghproxy="true"
# whether to download the mihomo Alpha kernel
dev="true"

# Updating files from URLs
upfile() {
  file="$1"
  update_url="$2"
  file_bak="${file}.bak"
  if [ -f "${file}" ]; then
    mv "${file}" "${file_bak}" || return 1
  fi
  # Use ghproxy
  if [ "${use_ghproxy}" == true ] && [[ "${update_url}" == @(https://github.com/*|https://raw.githubusercontent.com/*|https://gist.github.com/*|https://gist.githubusercontent.com/*) ]]; then
    update_url="${url_ghproxy}/${update_url}"
  fi
  # request
  request="busybox wget"
  request+=" --no-check-certificate"
  request+=" --user-agent ${user_agent}"
  request+=" -O ${file}"
  request+=" ${update_url}"
  echo "${yellow}${request}${normal}"
  ${request} >&2 || {
    if [ -f "${file_bak}" ]; then
      mv "${file_bak}" "${file}" || true
    fi
    log Error "Download ${request} ${orange}failed${normal}"
    return 1
  }
  return 0
}

# Restart the binary, after stopping and running again
restart_box() {
  "${scripts_dir}/box.service" restart
  # PIDS=("clash" "xray" "sing-box" "v2fly" "hysteria")
  PIDS=(${bin_name})
  PID=""
  i=0
  while [ -z "$PID" ] && [ "$i" -lt "${#PIDS[@]}" ]; do
    PID=$(busybox pidof "${PIDS[$i]}")
    i=$((i+1))
  done

  if [ -n "$PID" ]; then
    log Debug "${bin_name} Restart complete [$(date +"%F %R")]"
  else
    log Error "Failed to restart ${bin_name}."
    ${scripts_dir}/box.iptables disable >/dev/null 2>&1
  fi
}

# Check Configuration
check() {
  # su -c /data/adb/box/scripts/box.tool rconf
  case "${bin_name}" in
    sing-box)
      if ${bin_path} check -D "${box_dir}/${bin_name}" -c "${sing_config}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "${sing_config} passed"
      else
        log Debug "${sing_config}"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    clash)
      if ${bin_path} -t -d "${box_dir}/clash" -f "${clash_config}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "${clash_config} passed"
      else
        log Debug "${clash_config}"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    xray)
      export XRAY_LOCATION_ASSET="${box_dir}/xray"
      if ${bin_path} -test -confdir "${box_dir}/${bin_name}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "configuration passed"
      else
        echo "$(ls ${box_dir}/${bin_name})"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    v2fly)
      export V2RAY_LOCATION_ASSET="${box_dir}/v2fly"
      if ${bin_path} test -d "${box_dir}/${bin_name}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "configuration passed"
      else
        echo "$(ls ${box_dir}/${bin_name})"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    hysteria)
      true
      ;;
    *)
      log Error "<${bin_name}> unknown binary."
      exit 1
      ;;
  esac
}

# reload base config
reload() {
  curl_command="curl"
  if ! command -v curl >/dev/null 2>&1; then
    if [ ! -e "${bin_dir}/curl" ]; then
      log Debug "$bin_dir/curl file not found, unable to reload configuration"
      log Debug "start to download from github"
      upcurl || exit 1
    fi
    curl_command="${bin_dir}/curl"
  fi

  check

  case "${bin_name}" in
    "clash")
      endpoint="http://${ip_port}/configs?force=true"

      if ${curl_command} -X PUT -H "Authorization: Bearer ${secret}" "${endpoint}" -d '{"path": "", "payload": ""}' 2>&1; then
        log Info "${bin_name} config reload success"
        return 0
      else
        log Error "${bin_name} config reload failed !"
        return 1
      fi
      ;;
    "sing-box")
      endpoint="http://${ip_port}/configs?force=true"
      if ${curl_command} -X PUT -H "Authorization: Bearer ${secret}" "${endpoint}" -d '{"path": "", "payload": ""}' 2>&1; then
        log Info "${bin_name} config reload success."
        return 0
      else
        log Error "${bin_name} config reload failed !"
        return 1
      fi
      ;;
    "xray"|"v2fly"|"hysteria")
      if [ -f "${box_pid}" ]; then
        if kill -0 "$(<"${box_pid}" 2>/dev/null)"; then
          restart_box
        fi
      fi
      ;;
    *)
      log warning "${bin_name} not supported using API to reload config."
      return 1
      ;;
  esac
}

# Get latest curl
upcurl() {
  local arch
  case $(uname -m) in
    "aarch64") arch="aarch64" ;;
    "armv7l"|"armv8l") arch="armv7" ;;
    "i686") arch="i686" ;;
    "x86_64") arch="amd64" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac

  mkdir -p "${bin_dir}/backup"
  [ -f "${bin_dir}/curl" ] && cp "${bin_dir}/curl" "${bin_dir}/backup/curl.bak" >/dev/null 2>&1

  local latest_version=$(busybox wget --no-check-certificate -qO- "https://api.github.com/repos/stunnel/static-curl/releases" | grep "tag_name" | busybox grep -oE "[0-9.]*" | head -1)

  local download_link="https://github.com/stunnel/static-curl/releases/download/${latest_version}/curl-linux-${arch}-${latest_version}.tar.xz"

  log Debug "Download ${download_link}"
  upfile "${bin_dir}/curl.tar.xz" "${download_link}"

  if ! busybox tar -xJf "${bin_dir}/curl.tar.xz" -C "${bin_dir}" >&2; then
    log Error "Failed to extract ${bin_dir}/curl.tar.xz" >&2
    cp "${bin_dir}/backup/curl.bak" "${bin_dir}/curl" >/dev/null 2>&1 && log Info "Restored curl" || return 1
  fi

  chown "${box_user_group}" "${box_dir}/bin/curl"
  chmod 0700 "${bin_dir}/curl"

  rm -r "${bin_dir}/curl.tar.xz"
}

# Get latest yq
upyq() {
  local arch platform
  case $(uname -m) in
    "aarch64") arch="arm64"; platform="android" ;;
    "armv7l"|"armv8l") arch="arm"; platform="android" ;;
    "i686") arch="386"; platform="android" ;;
    "x86_64") arch="amd64"; platform="android" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac

  local download_link="https://github.com/taamarin/yq/releases/download/prerelease/yq_${platform}_${arch}"

  log Debug "Download ${download_link}"
  upfile "${box_dir}/bin/yq" "${download_link}"

  chown "${box_user_group}" "${box_dir}/bin/yq"
  chmod 0700 "${box_dir}/bin/yq"
}

# Check and update geoip and geosite
upgeox() {
  # su -c /data/adb/box/scripts/box.tool geox
  geodata_mode=$(busybox awk '!/^ *#/ && /geodata-mode:*./{print $2}' "${clash_config}")
  [ -z "${geodata_mode}" ] && geodata_mode=false
  case "${bin_name}" in
    clash)
      geoip_file="${box_dir}/clash/$(if [[ "${bin_name}" == "clash" && "${geodata_mode}" == "false" ]]; then echo "country.mmdb"; else echo "geoip.dat"; fi)"
      geoip_url="https://github.com/d2184/geoip/raw/release/$(if [[ "${bin_name}" == "clash" && "${geodata_mode}" == "false" ]]; then echo "country-tidy.mmdb"; else echo "geoip-tidy.dat"; fi)"
      geosite_file="${box_dir}/clash/geosite.dat"
      geosite_url="https://github.com/d2184/geosite/raw/release/geosite.dat"
      ;;
    sing-box)
      #geoip_file="${box_dir}/sing-box/geoip.db"
      #geoip_url="https://github.com/d2184/geoip/raw/release/geoip-tidy.db"
      #geosite_file="${box_dir}/sing-box/geosite.db"
      #geosite_url="https://github.com/d2184/geosite/raw/release/geosite.db"
      echo "sing-box v1.8.0+ not support geox"
      ;;
    *)
      geoip_file="${box_dir}/${bin_name}/geoip.dat"
      geoip_url="https://github.com/d2184/geoip/raw/release/geoip-tidy.dat"
      geosite_file="${box_dir}/${bin_name}/geosite.dat"
      geosite_url="https://github.com/d2184/geosite/raw/release/geosite.dat"
      ;;
  esac
  if [ "${update_geox}" = "true" ] && { log Info "daily updates geox" && log Debug "Downloading ${geoip_url}"; } && upfile "${geoip_file}" "${geoip_url}" && { log Debug "Downloading ${geosite_url}" && upfile "${geosite_file}" "${geosite_url}"; }; then

    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.db.bak" -delete
    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.dat.bak" -delete
    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.mmdb.bak" -delete

    log Debug "update geox $(date "+%F %R")"
    return 0
  else
   return 1
  fi
}

upkernel() {
  # su -c /data/adb/box/scripts/box.tool upkernel
  mkdir -p "${bin_dir}/backup"
  if [ -f "${bin_dir}/${bin_name}" ]; then
    cp "${bin_dir}/${bin_name}" "${bin_dir}/backup/${bin_name}.bak" >/dev/null 2>&1
  fi
  case $(uname -m) in
    "aarch64") if [ "${bin_name}" = "clash" ]; then arch="arm64-v8"; else arch="arm64"; fi; platform="android" ;;
    "armv7l"|"armv8l") arch="armv7"; platform="linux" ;;
    "i686") arch="386"; platform="linux" ;;
    "x86_64") arch="amd64"; platform="linux" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  # Do anything else below
  file_kernel="$(if [[ "${bin_name}" = "clash" ]]; then echo "mihomo"; else echo "${bin_name}"; fi)-${arch}"
  case "${bin_name}" in
    "sing-box")
      api_url="https://api.github.com/repos/SagerNet/sing-box/releases"
      url_down="https://github.com/SagerNet/sing-box/releases"

      latest_version=$(busybox wget --no-check-certificate -qO- "${api_url}" | grep "tag_name" | busybox grep -oE "v[0-9].*" | head -1 | cut -d'"' -f1)
      download_link="${url_down}/download/${latest_version}/sing-box-${latest_version#v}-${platform}-${arch}.tar.gz"
      log Debug "download ${download_link}"
      upfile "${box_dir}/${file_kernel}.tar.gz" "${download_link}" && xkernel
      ;;
    "clash")
      # set download link
      download_link="https://github.com/MetaCubeX/mihomo/releases"

      if [ "$dev" == false ]; then
        latest_version=$(busybox wget --no-check-certificate -qO- "https://api.github.com/repos/MetaCubeX/mihomo/releases" | grep "tag_name" | busybox grep -oE "v[0-9.]*" | head -1)
        tag="$latest_version"
      else
        tag="Prerelease-Alpha"
        latest_version=$(busybox wget --no-check-certificate -qO- "${download_link}/expanded_assets/${tag}" | busybox grep -oE "alpha-[0-9a-z]+" | head -1)
      fi
      # set the filename based on platform and architecture
      filename="mihomo-${platform}-${arch}-${latest_version}"
      # download and update the file
      log Debug "download ${download_link}/download/${tag}/${filename}.gz"
      upfile "${box_dir}/${file_kernel}.gz" "${download_link}/download/${tag}/${filename}.gz" && xkernel
      ;;
    "xray"|"v2fly")
      [ "${bin_name}" = "xray" ] && bin='Xray' || bin='v2ray'
      api_url="https://api.github.com/repos/$(if [ "${bin_name}" = "xray" ]; then echo "XTLS/Xray-core/releases"; else echo "v2fly/v2ray-core/releases"; fi)"
      # set download link and get the latest version
      latest_version=$(busybox wget --no-check-certificate -qO- ${api_url} | grep "tag_name" | busybox grep -oE "v[0-9.]*" | head -1)

      case $(uname -m) in
        "i386") download_file="$bin-linux-32.zip" ;;
        "x86_64") download_file="$bin-linux-64.zip" ;;
        "armv7l"|"armv8l") download_file="$bin-linux-arm32-v7a.zip" ;;
        "aarch64") download_file="$bin-android-arm64-v8a.zip" ;;
        *) log Error "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
      esac
      # Do anything else below
      download_link="https://github.com/$(if [ "${bin_name}" = "xray" ]; then echo "XTLS/Xray-core/releases"; else echo "v2fly/v2ray-core/releases"; fi)"
      log Debug "Downloading ${download_link}/download/${latest_version}/${download_file}"
      upfile "${box_dir}/${file_kernel}.zip" "${download_link}/download/${latest_version}/${download_file}" && xkernel
      ;;
    "hysteria")
      local arch
      case $(uname -m) in
        "aarch64") arch="arm64" ;;
        "armv7l" | "armv8l") arch="armv7" ;;
        "i686") arch="386" ;;
        "x86_64") arch="amd64" ;;
        *)
          log Warning "Unsupported architecture: $(uname -m)"
          return 1
          ;;
      esac

      # Create backup directory if it doesn't exist
      mkdir -p "${bin_dir}/backup"

      # Backup existing Hysteria binary if it exists
      if [ -f "${bin_dir}/hysteria" ]; then
        cp "${bin_dir}/hysteria" "${bin_dir}/backup/hysteria.bak" >/dev/null 2>&1
      fi

      # Fetch the latest version of Hysteria from GitHub releases
      local latest_version=$(busybox wget --no-check-certificate -qO- "https://api.github.com/repos/apernet/hysteria/releases" | grep "tag_name" | grep -oE "[0-9.].*" | head -1 | sed 's/,//g' | cut -d '"' -f 1)

      local download_link="https://github.com/apernet/hysteria/releases/download/app%2Fv${latest_version}/hysteria-android-${arch}"

      log Debug "Downloading ${download_link}"
      upfile "${bin_dir}/hysteria" "${download_link}" && xkernel
      ;;
    *)
      log Error "<${bin_name}> unknown binary."
      exit 1
      ;;
  esac
}

# Check and update kernel
xkernel() {
  case "${bin_name}" in
    "clash")
      gunzip_command="gunzip"
      if ! command -v gunzip >/dev/null 2>&1; then
        gunzip_command="busybox gunzip"
      fi

      if ${gunzip_command} "${box_dir}/${file_kernel}.gz" >&2 && mv "${box_dir}/${file_kernel}" "${bin_dir}/clash"; then
        if [ -f "${box_pid}" ]; then
          restart_box
        else
          log Debug "${bin_name} does not need to be restarted."
        fi
      else
        log Error "Failed to extract or move the kernel."
      fi
      ;;
    "sing-box")
      tar_command="tar"
      if ! command -v tar >/dev/null 2>&1; then
        tar_command="busybox tar"
      fi
      if ${tar_command} -xf "${box_dir}/${file_kernel}.tar.gz" -C "${bin_dir}" >&2; then
        mv "${bin_dir}/sing-box-${latest_version#v}-${platform}-${arch}/sing-box" "${bin_dir}/${bin_name}"
        if [ -f "${box_pid}" ]; then
          rm -rf /data/adb/box/sing-box/cache.db
          restart_box
        else
          log Debug "${bin_name} does not need to be restarted."
        fi
      else
        log Error "Failed to extract ${box_dir}/${file_kernel}.tar.gz."
      fi
      [ -d "${bin_dir}/sing-box-${latest_version#v}-${platform}-${arch}" ] && \
        rm -r "${bin_dir}/sing-box-${latest_version#v}-${platform}-${arch}"
      ;;
    "v2fly"|"xray")
      bin="xray"
      if [ "${bin_name}" != "xray" ]; then
        bin="v2ray"
      fi
      unzip_command="unzip"
      if ! command -v unzip >/dev/null 2>&1; then
        unzip_command="busybox unzip"
      fi

      mkdir -p "${bin_dir}/update"
      if ${unzip_command} -o "${box_dir}/${file_kernel}.zip" "${bin}" -d "${bin_dir}/update" >&2; then
        if mv "${bin_dir}/update/${bin}" "${bin_dir}/${bin_name}"; then
          if [ -f "${box_pid}" ]; then
            restart_box
          else
            log Debug "${bin_name} does not need to be restarted."
          fi
        else
          log Error "Failed to move the kernel."
        fi
      else
        log Error "Failed to extract ${box_dir}/${file_kernel}.zip."
      fi
      rm -rf "${bin_dir}/update"
      ;;
    "hysteria")
      if [ -f "${box_pid}" ]; then
        restart_box
      else
        log Debug "${bin_name} does not need to be restarted."
      fi
      ;;
    *)
      log Error "<${bin_name}> unknown binary."
      exit 1
      ;;
  esac

  find "${box_dir}" -maxdepth 1 -type f -name "${file_kernel}.*" -delete
  chown ${box_user_group} ${bin_path}
  chmod 6755 ${bin_path}
}

# Check and update yacd
upxui() {
  # su -c /data/adb/box/scripts/box.tool upxui
  xdashboard="${bin_name}/dashboard"
  if [[ "${bin_name}" == @(clash|sing-box) ]]; then
    file_dashboard="${box_dir}/${xdashboard}.zip"
    url="https://github.com/d2184/xd/archive/gh-pages.zip"
    if [ "$use_ghproxy" == true ]; then
      url="${url_ghproxy}/${url}"
    fi
    dir_name="xd-gh-pages"
    log Debug "Download ${url}"
    if busybox wget --no-check-certificate "${url}" -O "${file_dashboard}" >&2; then
      if [ ! -d "${box_dir}/${xdashboard}" ]; then
        log Info "dashboard folder not exist, creating it"
        mkdir "${box_dir}/${xdashboard}"
      else
        rm -rf "${box_dir}/${xdashboard}/"*
      fi
      if command -v unzip >/dev/null 2>&1; then
        unzip_command="unzip"
      else
        unzip_command="busybox unzip"
      fi
      "${unzip_command}" -o "${file_dashboard}" "${dir_name}/*" -d "${box_dir}/${xdashboard}" >&2
      mv -f "${box_dir}/${xdashboard}/$dir_name"/* "${box_dir}/${xdashboard}/"
      rm -f "${file_dashboard}"
      rm -rf "${box_dir}/${xdashboard}/${dir_name}"
    else
      log Error "Failed to download dashboard" >&2
      return 1
    fi
    return 0
  else
    log Debug "${bin_name} does not support dashboards"
    return 1
  fi
}

bond0() {
  # Menonaktifkan mode low latency untuk TCP
  sysctl -w net.ipv4.tcp_low_latency=0 >/dev/null 2>&1
  log Debug "tcp low latency: 0"

  # Mengatur panjang antrian transmisi (txqueuelen) menjadi 3000 untuk semua interface wireless (wlan*)
  for dev in /sys/class/net/wlan*; do ip link set dev $(basename $dev) txqueuelen 3000; done
  log Debug "wlan* txqueuelen: 3000"

  # Mengatur panjang antrian transmisi (txqueuelen) menjadi 1000 untuk semua interface rmnet_data*
  for txqueuelen in /sys/class/net/rmnet_data*; do txqueuelen_name=$(basename $txqueuelen); ip link set dev $txqueuelen_name txqueuelen 1000; done
  log Debug "rmnet_data* txqueuelen: 1000"

  # Mengatur MTU (Maximum Transmission Unit) menjadi 1500 untuk semua interface rmnet_data*
  for mtu in /sys/class/net/rmnet_data*; do mtu_name=$(basename $mtu); ip link set dev $mtu_name mtu 1500; done
  log Debug "rmnet_data* mtu: 1500"
}

bond1() {
  # Mengaktifkan mode low latency untuk TCP
  sysctl -w net.ipv4.tcp_low_latency=1 >/dev/null 2>&1
  log Debug "tcp low latency: 1"

  # Mengatur panjang antrian transmisi (txqueuelen) menjadi 4000 untuk semua interface wireless (wlan*)
  for dev in /sys/class/net/wlan*; do ip link set dev $(basename $dev) txqueuelen 4000; done
  log Debug "wlan* txqueuelen: 4000"

  # Mengatur panjang antrian transmisi (txqueuelen) menjadi 2000 untuk semua interface rmnet_data*
  for txqueuelen in /sys/class/net/rmnet_data*; do txqueuelen_name=$(basename $txqueuelen); ip link set dev $txqueuelen_name txqueuelen 2000; done
  log Debug "rmnet_data* txqueuelen: 2000"

  # Mengatur MTU (Maximum Transmission Unit) menjadi 9000 untuk semua interface rmnet_data*
  for mtu in /sys/class/net/rmnet_data*; do mtu_name=$(basename $mtu); ip link set dev $mtu_name mtu 9000; done
  log Debug "rmnet_data* mtu: 9000"
}

case "$1" in
  check)
    check
    ;;
  bond0|bond1)
    $1
    ;;
  upgeox)
    upgeox
    if [ -f "${box_pid}" ]; then
      kill -0 "$(<"${box_pid}" 2>/dev/null)" && reload
    fi
    ;;
  upcore)
    upkernel
    ;;
  upyacd)
    upxui
    ;;
  upyq|upcurl)
    $1
    ;;
  reload)
    reload
    ;;
  all)
    upyq
    upcurl
    for bin_name in "${bin_list[@]}"; do
      upkernel
      upgeox
      upxui
    done
    ;;
  *)
    echo "${red}$0 $1 no found${normal}"
    echo "${yellow}usage${normal}: ${green}$0${normal} {${yellow}check|upgeox|upcore|upyacd|upyq|upcurl|reload|bond0|bond1|all${normal}}"
    ;;
esac