#!/usr/bin/env bash
# Deploy and manage versioned releases of the DeployLatch demo service.
# Stop on unhandled command errors, unset variables, and failed pipelines.
set -Eeuo pipefail

# Shared paths used by deployment, rollback, status, and history commands.
ROOT=/opt/deploylatch
RELEASES="$ROOT/releases"
CURRENT="$ROOT/current"
PREVIOUS="$ROOT/previous"
SERVICE=deploylatch-demo.service
LOG=/var/log/deploylatch/deployments.log

# Print a consistent, user-facing error and stop the command.
print_error_and_exit() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# Return the release ID only when the link resolves to an installed JAR.
get_release_id() {
    local link_path="$1"
    local release_path

    if [[ ! -L "$link_path" ]]; then
        return 1
    fi

    if ! release_path=$(readlink -f -- "$link_path"); then
        return 1
    fi

    if [[ "$release_path" != "$RELEASES/"* || ! -f "$release_path/app.jar" ]]; then
        return 1
    fi

    basename -- "$release_path"
}

# Replace the current pointer atomically after preparing its temporary symlink.
activate_release() {
    local release_id="$1"
    local temporary_link="$CURRENT.tmp.$$"

    ln -s "releases/$release_id" "$temporary_link"
    mv -Tf "$temporary_link" "$CURRENT"
}

set_previous_release() {
    local release_id="$1"
    local temporary_link="$PREVIOUS.tmp.$$"

    ln -s "releases/$release_id" "$temporary_link"
    mv -Tf "$temporary_link" "$PREVIOUS"
}

write_deployment_log() {
    local outcome="$1"
    local release_id="$2"
    local message="$3"

    printf '%s | %s | %s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$outcome" "$release_id" "$message" >> "$LOG"
}

check_release_health() {
    local expected_release="$1"
    local attempt health_response version_response

    for ((attempt=1; attempt<=8; attempt++)); do
        # A failed request is expected while the service restarts, so retry it.
        health_response=$(curl -fsS --max-time 2 http://127.0.0.1:8080/health 2>/dev/null || true)
        version_response=$(curl -fsS --max-time 2 http://127.0.0.1:8080/version 2>/dev/null || true)

        # Confirm both service health and that the requested release is running.
        if [[ "$health_response" == OK && "$version_response" == "$expected_release" ]]; then
            return 0
        fi

        sleep 1
    done

    return 1
}

prepare_environment() {
    if (( EUID != 0 )); then
        print_error_and_exit 'Run this command with sudo (for example: sudo ./deploylatch.sh status).'
    fi

    for executable in systemctl curl flock; do
        if ! command -v "$executable" >/dev/null; then
            print_error_and_exit "Required command '$executable' was not found. Install it and try again."
        fi
    done

    if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
        print_error_and_exit "Systemd service '$SERVICE' is not installed. Install its unit file first."
    fi

    install -d -m 0755 "$RELEASES" /var/log/deploylatch
    touch "$LOG"

    # Keep the exclusive lock open for the full command to prevent concurrent changes.
    exec 9>"$ROOT/.deploy.lock"
    if ! flock -n 9; then
        print_error_and_exit 'Another DeployLatch command is running. Wait for it to finish, then retry.'
    fi
}

deploy_release() {
    local source_jar="$1"
    local new_release="$2"
    local old_release=''

    if [[ ! -f "$source_jar" || ! -r "$source_jar" ]]; then
        print_error_and_exit "JAR '$source_jar' does not exist or cannot be read. Check the path and permissions."
    fi

    if [[ ! "$new_release" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        print_error_and_exit "Invalid release ID '$new_release'. Use letters, numbers, dot, underscore, or hyphen; start with a letter or number."
    fi

    if [[ -e "$RELEASES/$new_release" ]]; then
        print_error_and_exit "Release already exists: $new_release"
    fi

    # Record the active release so it can be restored if the new one fails.
    old_release=$(get_release_id "$CURRENT" || true)
    install -d -m 0755 "$RELEASES/$new_release"
    install -m 0644 -- "$source_jar" "$RELEASES/$new_release/app.jar"
    activate_release "$new_release"
    printf 'Deploying %s\n' "$new_release"

    if systemctl restart "$SERVICE" && check_release_health "$new_release"; then
        if [[ -n "$old_release" ]]; then
            set_previous_release "$old_release"
        fi

        write_deployment_log SUCCESS "$new_release" 'Health check passed'
        printf 'Deployment successful: %s\n' "$new_release"
        return 0
    fi

    printf 'Deployment failed: %s\n' "$new_release" >&2

    # With no earlier release, stop the failed service and remove its pointer.
    if [[ -z "$old_release" ]]; then
        systemctl stop "$SERVICE" || true
        rm -f "$CURRENT"
        write_deployment_log FAILED "$new_release" 'No previous release'
        return 1
    fi

    activate_release "$old_release"
    if systemctl restart "$SERVICE" && check_release_health "$old_release"; then
        write_deployment_log ROLLED_BACK "$new_release" "Restored $old_release"
        printf 'Restored %s\n' "$old_release"
    else
        write_deployment_log ROLLBACK_FAILED "$new_release" "Failed to recover $old_release"
        printf 'Automatic recovery failed. Check the service logs with: journalctl -u %s\n' "$SERVICE" >&2
    fi

    # Recovery does not make the requested deployment successful.
    return 1
}

rollback_release() {
    local active_release rollback_target

    if ! active_release=$(get_release_id "$CURRENT"); then
        print_error_and_exit 'No valid active release was found. Deploy a release before rolling back.'
    fi

    if ! rollback_target=$(get_release_id "$PREVIOUS"); then
        print_error_and_exit 'No valid previous release was found. A successful deployment is needed before rollback.'
    fi

    if [[ "$active_release" == "$rollback_target" ]]; then
        print_error_and_exit 'Previous release already active.'
    fi

    activate_release "$rollback_target"
    if systemctl restart "$SERVICE" && check_release_health "$rollback_target"; then
        set_previous_release "$active_release"
        write_deployment_log MANUAL_ROLLBACK "$rollback_target" "Replaced $active_release"
        printf 'Restored %s\n' "$rollback_target"
    else
        # Restore the original pointer and attempt to restart it.
        activate_release "$active_release"
        systemctl restart "$SERVICE" || true
        write_deployment_log ROLLBACK_FAILED "$rollback_target" "Restored pointer to $active_release"
        printf 'Rollback to %s failed; restored the active pointer to %s. Check the service logs with: journalctl -u %s\n' \
            "$rollback_target" "$active_release" "$SERVICE" >&2
        return 1
    fi
}

show_status() {
    local active_release previous_release service_state

    active_release=$(get_release_id "$CURRENT" || true)
    previous_release=$(get_release_id "$PREVIOUS" || true)
    service_state=$(systemctl is-active "$SERVICE" || true)
    printf 'Current: %s\nPrevious: %s\nService: %s\n' \
        "$active_release" "$previous_release" "$service_state"

    if [[ -n "$active_release" ]] && check_release_health "$active_release"; then
        printf 'Health: OK\n'
    else
        printf 'Health: unavailable\n'
    fi
}

show_usage() {
    printf '%s\n' \
        'Usage:' \
        '  deploylatch.sh deploy JAR RELEASE_ID  Install and verify a release' \
        '  deploylatch.sh rollback               Restore the previous release' \
        '  deploylatch.sh status                 Show release and service health' \
        '  deploylatch.sh history                Show recent deployment history' \
        '  deploylatch.sh help                   Show this help'
}

# Read the action first; the remaining arguments belong to that action.
if (( $# == 0 )); then
    show_usage
    printf 'Error: missing command.\n' >&2
    exit 1
fi

action="$1"
shift

case "$action" in
    deploy)
        if (( $# != 2 )); then
            print_error_and_exit 'Deploy needs a JAR path and release ID. Example: ./deploylatch.sh deploy app.jar v1.'
        fi
        prepare_environment
        deploy_release "$1" "$2"
        ;;
    rollback)
        if (( $# != 0 )); then
            print_error_and_exit 'The rollback command does not accept extra arguments.'
        fi
        prepare_environment
        rollback_release
        ;;
    status)
        if (( $# != 0 )); then
            print_error_and_exit 'The status command does not accept extra arguments.'
        fi
        prepare_environment
        show_status
        ;;
    history)
        if (( $# != 0 )); then
            print_error_and_exit 'The history command does not accept extra arguments.'
        fi
        prepare_environment
        if [[ -s "$LOG" ]]; then
            tail -n 20 "$LOG"
        else
            echo 'No history yet.'
        fi
        ;;
    help|-h|--help)
        show_usage
        ;;
    *)
        show_usage
        printf "Error: unknown command '%s'.\n" "$action" >&2
        exit 1
        ;;
esac
