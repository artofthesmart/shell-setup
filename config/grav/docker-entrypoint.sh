#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

GRAV_HOME="/var/www/html"
GRAV_VERSION="${GRAV_VERSION:-latest}"
GRAV_CHANNEL="${GRAV_CHANNEL:-stable}"

# ── PGID-only group remapping ────────────────────────────────────────────────
# Add www-data to the shared host group (grav-data) so Apache can write to
# group-writable workspace directories WITHOUT changing www-data's UID.
# The container process stays as UID 33, which has no special host privileges
# if it were to escape the container namespace.
remap_www_data() {
    local target_gid="${PGID:-}"

    if [ -z "${target_gid}" ]; then
        # No PGID set — nothing to remap.
        return
    fi

    log_info "Adding www-data to supplemental GID ${target_gid}..."

    # Ensure the target group exists inside the container (it won't by default
    # since it only exists on the host). Create a placeholder if needed.
    if ! getent group "${target_gid}" > /dev/null 2>&1; then
        groupadd --gid "${target_gid}" grav-data 2>/dev/null || true
    fi

    # Add www-data as a supplemental member of the group.
    usermod -aG "${target_gid}" www-data 2>/dev/null || true

    log_info "www-data now has supplemental GID ${target_gid}."
}

install_grav() {
    local download_url

    if [ "${GRAV_VERSION}" = "latest" ]; then
        # Use getgrav.org for stable/beta latest lookups (unchanged upstream behaviour)
        if [ "${GRAV_CHANNEL}" = "beta" ]; then
            log_info "Installing Grav CMS (latest beta)..."
            download_url="https://getgrav.org/download/core/grav-admin/latest?beta"
        else
            log_info "Installing Grav CMS (latest stable)..."
            download_url="https://getgrav.org/download/core/grav-admin/latest"
        fi
    else
        # Check whether this is a prerelease tag (contains "-rc.", "-beta.", "-alpha.")
        if echo "${GRAV_VERSION}" | grep -qE '\-(rc|beta|alpha)\.'; then
            # Prerelease builds live only on GitHub, not on getgrav.org
            log_info "Installing Grav CMS (prerelease: ${GRAV_VERSION}) from GitHub..."
            download_url="https://github.com/getgrav/grav/releases/download/${GRAV_VERSION}/grav-admin-v${GRAV_VERSION}.zip"
        else
            # Stable pinned version via getgrav.org
            log_info "Installing Grav CMS (version: ${GRAV_VERSION})..."
            download_url="https://getgrav.org/download/core/grav-admin/${GRAV_VERSION}"
        fi
    fi

    cd /tmp
    log_info "Downloading from: ${download_url}"
    curl -fsSL -o grav-admin.zip "${download_url}"
    unzip -q grav-admin.zip

    if [ -d "${GRAV_HOME}" ] && [ "$(ls -A ${GRAV_HOME})" ]; then
        cp -rn /tmp/grav-admin/* "${GRAV_HOME}/" 2>/dev/null || true
        cp -rn /tmp/grav-admin/.[!.]* "${GRAV_HOME}/" 2>/dev/null || true
    else
        mkdir -p "${GRAV_HOME}"
        mv /tmp/grav-admin/* "${GRAV_HOME}/"
        mv /tmp/grav-admin/.[!.]* "${GRAV_HOME}/" 2>/dev/null || true
    fi

    rm -rf /tmp/grav-admin /tmp/grav-admin.zip
    log_info "Grav installation complete!"
}

is_grav_installed() {
    [ -f "${GRAV_HOME}/index.php" ] && [ -f "${GRAV_HOME}/system/defines.php" ]
}

fix_permissions() {
    log_info "Setting permissions..."
    chown -R www-data:www-data "${GRAV_HOME}"
    find "${GRAV_HOME}" -type d -exec chmod 755 {} \;
    find "${GRAV_HOME}" -type f -exec chmod 644 {} \;
    if [ -d "${GRAV_HOME}/bin" ]; then
        chmod +x "${GRAV_HOME}/bin/"*
    fi
    log_info "Permissions set!"
}

setup_cron() {
    log_info "Setting up Grav scheduler cron job..."
    CRON_JOB="* * * * * cd ${GRAV_HOME} && /usr/local/bin/php bin/grav scheduler 1>> /dev/null 2>&1"
    (crontab -u www-data -l 2>/dev/null | grep -v "grav scheduler"; echo "${CRON_JOB}") | crontab -u www-data -
    log_info "Cron job configured!"
}

# ── Base URL injection ────────────────────────────────────────────────────────
# Writes (or updates) the custom_base_url key in system.yaml so the admin2
# SvelteKit SPA gets the correct serverUrl regardless of how Apache sees the
# request (e.g. when sitting behind a Tailscale sidecar on localhost).
configure_base_url() {
    if [ -z "${GRAV_BASE_URL}" ]; then
        return
    fi

    local system_yaml="${GRAV_HOME}/user/config/system.yaml"
    mkdir -p "$(dirname "${system_yaml}")"

    if [ ! -f "${system_yaml}" ]; then
        log_info "Creating system.yaml with custom_base_url..."
        echo "custom_base_url: '${GRAV_BASE_URL}'" > "${system_yaml}"
        chown www-data:www-data "${system_yaml}"
        chmod 644 "${system_yaml}"
        return
    fi

    if grep -q "^custom_base_url:" "${system_yaml}"; then
        # Update existing line in-place
        sed -i "s|^custom_base_url:.*|custom_base_url: '${GRAV_BASE_URL}'|" "${system_yaml}"
        log_info "Updated custom_base_url to '${GRAV_BASE_URL}' in system.yaml."
    else
        # Prepend so it's easy to spot at the top of the file
        sed -i "1s|^|custom_base_url: '${GRAV_BASE_URL}'\n\n|" "${system_yaml}"
        log_info "Injected custom_base_url '${GRAV_BASE_URL}' into system.yaml."
    fi
}

main() {
    log_info "Starting Grav Docker container..."
    log_info "PHP Version: $(php -v | head -n 1)"

    # Remap www-data UID/GID before touching any files so ownership is correct
    # from the first write.
    remap_www_data

    if ! is_grav_installed; then
        if [ "${GRAV_SETUP:-true}" = "true" ]; then
            install_grav
            fix_permissions
        else
            log_warn "Grav not installed and GRAV_SETUP=false. Skipping installation."
            log_warn "Mount your existing Grav installation to ${GRAV_HOME}"
        fi
    else
        log_info "Existing Grav installation detected. Skipping installation."
        if [ "${FIX_PERMISSIONS:-false}" = "true" ]; then
            fix_permissions
        fi
        # After a GID remap, runtime-writable dirs must be re-owned so Apache
        # can write to files that may have been created under a different group
        # on a previous run.
        if [ -n "${PGID:-}" ]; then
            log_info "Re-chowning runtime-writable directories to www-data..."
            for dir in cache logs tmp images backup assets; do
                [ -d "${GRAV_HOME}/${dir}" ] && chown -R www-data:www-data "${GRAV_HOME}/${dir}"
            done
            [ -d "${GRAV_HOME}/user/config" ] && chown -R www-data:www-data "${GRAV_HOME}/user/config"
        fi
    fi

    # Always (re-)apply base URL so it survives container restarts and rebuilds.
    configure_base_url

    if [ "${GRAV_SCHEDULER:-true}" = "true" ]; then
        setup_cron
        service cron start
    fi

    if [ -d "/docker-entrypoint.d" ]; then
        for f in /docker-entrypoint.d/*.sh; do
            if [ -x "$f" ]; then
                log_info "Running custom script: $f"
                "$f"
            fi
        done
    fi

    log_info "Container initialization complete!"
    log_info "Starting Apache..."
    exec "$@"
}

main "$@"
