#!/system/bin/sh

scripts=$(realpath "$0")
scripts_dir=$(dirname "${scripts}")
source /data/adb/box/settings.ini

# whether use ghproxy to accelerate github download
use_ghproxy=false

# Updating files from URLs
update_file() {
  file="$1"
  update_url="$2"
  file_bak="${file}.bak"
  if [ -f "${file}" ]; then
    mv "${file}" "${file_bak}" || return 1
  fi
  # Use ghproxy
  if [ "${use_ghproxy}" == true ] && [[ "${update_url}" == @(https://github.com/*|https://raw.githubusercontent.com/*|https://gist.github.com/*|https://gist.githubusercontent.com/*) ]]; then
    update_url="https://mirror.ghproxy.com/${update_url}"
  fi
  # request
  request="busybox wget"
  request+=" --no-check-certificate"
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
  # PIDS=("clash" "xray" "sing-box" "v2fly")
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

# Check and update geoip and geosite
update_geox() {
  # su -c /data/adb/box/scripts/box.tool geox
  geodata_mode=$(busybox awk '!/^ *#/ && /geodata-mode:*./{print $2}' "${clash_config}")
  [ -z "${geodata_mode}" ] && geodata_mode=false
  case "${bin_name}" in
    clash)
      geoip_file="${box_dir}/clash/$(if [[ "${geodata_mode}" == "false" ]]; then echo "Country.mmdb"; else echo "GeoIP.dat"; fi)"
      geoip_url="https://github.com/d2184/geoip/raw/release/$(if [[ "${geodata_mode}" == "false" ]]; then echo "Country.mmdb"; else echo "geoip.dat"; fi)"
      geosite_file="${box_dir}/clash/GeoSite.dat"
      geosite_url="https://github.com/d2184/geosite/raw/release/geosite.dat"
      ;;
    sing-box)
      echo "sing-box v1.8.0+ doesn't support geoip/geosite"
      ;;
    *)
      geoip_file="${box_dir}/${bin_name}/geoip.dat"
      geoip_url="https://github.com/d2184/geoip/raw/release/geoip.dat"
      geosite_file="${box_dir}/${bin_name}/geosite.dat"
      geosite_url="https://github.com/d2184/geosite/raw/release/geosite.dat"
      ;;
  esac

  if [ "${update_geox}" = "true" ] && [ "${bin_name}" != "sing-box" ] && { log Info "daily updates geox" && log Debug "Downloading ${geoip_url}"; } && update_file "${geoip_file}" "${geoip_url}" && { log Debug "Downloading ${geosite_url}" && update_file "${geosite_file}" "${geosite_url}"; }; then

    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.db.bak" -delete
    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.dat.bak" -delete
    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.mmdb.bak" -delete
    log Debug "Update geox $(date +"%F %R")"
    if [ -f "${box_pid}" ]; then
      reload
    fi
  else
    return 1
  fi
}

update_kernel() {
  # su -c /data/adb/box/scripts/box.tool update_kernel
  mkdir -p "${bin_dir}/backup"
  if [ -f "${bin_dir}/${bin_name}" ]; then
    cp "${bin_dir}/${bin_name}" "${bin_dir}/backup/${bin_name}.bak" >/dev/null 2>&1
  fi
  case $(uname -m) in
    "aarch64") arch="arm64"; platform="android" ;;
    "armv7l"|"armv8l") arch="armv7"; platform="linux" ;;
    "i686") arch="386"; platform="linux" ;;
    "x86_64") arch="amd64"; platform="linux" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  # Do anything else below
  file_kernel="$(if [[ "${bin_name}" = "clash" ]]; then echo "mihomo"; else echo "${bin_name}"; fi)-${arch}" 
  case "${bin_name}" in
    "sing-box")
      url_down="https://github.com/d2184/sing-box/releases"
      if [ "$use_ghproxy" == true ]; then
        url_down="https://ghproxy.com/${url_down}"
      fi
      sing_box_version=$(busybox wget --no-check-certificate -qO- "${url_down}" | grep -oE '/tag/v[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9]+' | head -1 | busybox awk -F'/' '{print $3}')
      download_link="${url_down}/download/${sing_box_version}/sing-box-${sing_box_version}-${platform}-${arch}.tar.gz"
      log Debug "download ${download_link}"
      update_file "${box_dir}/${file_kernel}.tar.gz" "${download_link}" && extra_kernel
      ;;
    "clash")
      # set download link and get the latest version
      download_link="https://github.com/MetaCubeX/mihomo/releases"
      if [ "$use_ghproxy" == true ]; then
        download_link="https://mirror.ghproxy.com/${download_link}"
      fi
      tag="Prerelease-Alpha"
      latest_version=$(busybox wget --no-check-certificate -qO- "${download_link}/expanded_assets/${tag}" | grep -oE "alpha-[0-9a-z]+" | head -1)
      # set the filename based on platform and architecture
      filename="mihomo-${platform}-${arch}-${latest_version}"
      # download and update the file
      log Debug "download ${download_link}/download/${tag}/${filename}.gz"
      update_file "${box_dir}/${file_kernel}.gz" "${download_link}/download/${tag}/${filename}.gz" && extra_kernel
    ;;
    "xray"|"v2fly")
      [ "${bin_name}" = "xray" ] && bin='Xray' || bin='v2ray'
      api_url="https://api.github.com/repos/$(if [ "${bin_name}" = "xray" ]; then echo "XTLS/Xray-core/releases"; else echo "v2fly/v2ray-core/releases"; fi)"
      # set download link and get the latest version
      latest_version=$(busybox wget --no-check-certificate -qO- ${api_url} | grep "tag_name" | grep -o "v[0-9.]*" | head -1)
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
      update_file "${box_dir}/${file_kernel}.zip" "${download_link}/download/${latest_version}/${download_file}" && extra_kernel
    ;;
    *)
      log Error "<${bin_name}> unknown binary."
      exit 1
      ;;
  esac
}

# Check and update kernel
extra_kernel() {
  case "${bin_name}" in
    "clash")
      gunzip_command="gunzip"
      if ! command -v gunzip >/dev/null 2>&1; then
        gunzip_command="busybox gunzip"
      fi

      if ${gunzip_command} "${box_dir}/${file_kernel}.gz" >&2 && mv "${box_dir}/${file_kernel}" "${bin_dir}/clash"; then
        rm -rf "${bin_dir}/backup"
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

      if ${tar_command} -xf "${box_dir}/${file_kernel}.tar.gz" -C "${bin_dir}" >&2 &&
        mv "${bin_dir}/sing-box-${sing_box_version#v}-${platform}-${arch}/sing-box" "${bin_dir}/${bin_name}"; then
        rm -rf "${bin_dir}/backup"
        if [ -f "${box_pid}" ]; then
          rm -rf "${box_dir}/${bin_name}/cache.db"
          restart_box
        else
          log Debug "${bin_name} does not need to be restarted."
        fi
      else
        log Error "Failed to extract ${box_dir}/${file_kernel}.tar.gz."
      fi
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
update_dashboard() {
  # su -c /data/adb/box/scripts/box.tool upyacd
  if [[ "${bin_name}" == @(clash|sing-box) ]]; then
    file_dashboard="${box_dir}/${bin_name}/dashboard.zip"
    url="https://github.com/d2184/yacd/archive/gh-pages.zip"
    if [ "$use_ghproxy" == true ]; then
      url="https://mirror.ghproxy.com/${url}"
    fi
    dir_name="yacd-gh-pages"
    log Debug "Download ${url}"
    if busybox wget --no-check-certificate "${url}" -O "${file_dashboard}" >&2; then
      if [ ! -d "${box_dir}/${bin_name}/dashboard" ]; then
        log Info "dashboard folder not exist, creating it"
        mkdir "${box_dir}/${bin_name}/dashboard"
      else
        rm -rf "${box_dir}/${bin_name}/dashboard/"*
      fi
      if command -v unzip >/dev/null 2>&1; then
        unzip_command="unzip"
      else
        unzip_command="busybox unzip"
      fi
      "${unzip_command}" -o "${file_dashboard}" "${dir_name}/*" -d "${box_dir}/${bin_name}/dashboard" >&2
      mv -f "${box_dir}/${bin_name}/dashboard/$dir_name"/* "${box_dir}/${bin_name}/dashboard/"
      rm -f "${file_dashboard}"
      rm -rf "${box_dir}/${bin_name}/dashboard/${dir_name}"
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

# Function for detecting ports used by a process
port_detection() {
  sleep 1
  # Use 'command' function to check availability of 'ss'
  if command -v ss > /dev/null ; then
    # Use 'awk' with a regular expression to match the process ID
    ports=$(ss -antup | busybox awk -v PID="$(busybox pidof "${bin_name}")" '$7 ~ PID {print $5}' | busybox awk -F ':' '{print $2}' | sort -u) >/dev/null 2>&1
    # Make a note of the detected ports
    if busybox pidof "${bin_name}" >/dev/null 2>&1; then
      if [ -t 1 ]; then
        echo -n "${orange}${current_time} [Debug]: ${bin_name} port detected:${normal}"
      else
        echo -n "${current_time} [Debug]: ${bin_name} port detected:" | tee -a "${box_log}" >> /dev/null 2>&1
      fi
      # write ports
      while read -r port; do
        sleep 0.5
        [ -t 1 ] && (echo -n "${red}${port} $normal") || (echo -n "${port} " | tee -a "${box_log}" >> /dev/null 2>&1)
      done <<< "${ports}"
      # Add a newline to the output if running in terminal
      [ -t 1 ] && echo -e "\033[1;31m""\033[0m" || echo "" >> "${box_log}" 2>&1
    else
      return 1
    fi
  else
    log Debug "ss command not found, skipping port detection." >&2
    return 1
  fi
}

# Check config
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
    xray|v2fly)
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
  case "${bin_name}" in
    "clash")
      if ( curl -X PUT -H "Authorization: Bearer ${secret}" "http://${ip_port}/configs?force=true" -d '{"path": "", "payload": ""}' ) 2>&1; then
        echo "${bin_name} config reload success"
      else
        echo "${bin_name} config reload failed !"
        exit 1
      fi
      ;;
    "sing-box")
      if ( curl -X PUT -H "Authorization: Bearer ${secret}" "http://${ip_port}/configs?force=true" -d '{"path": "", "payload": ""}' ) 2>&1; then
        echo "${bin_name} config reload success"
      else
        echo "${bin_name} config reload failed !"
        exit 1
      fi
      ;;
    *)
      log error "${bin_name} not support use api to reload config."
      exit 1
      ;;
  esac
}

case "$1" in
  check)
    check
    ;;
  upyacd)
    update_dashboard
    ;;
  upcore)
    update_kernel
    ;;
  port)
    port_detection
    ;;
  upgeox)
    update_geox
    ;;
  reload)
    reload
    ;;
  all)
    update_dashboard
    update_geox
    update_kernel
    ;;
  *)
    echo "${red}$0 $1 no found${normal}"
    echo "${yellow}usage${normal}: ${green}$0${normal} {${yellow}check|upyacd|upcore|port|upgeox|reload|all${normal}}"
    ;;
esac