#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/opt/deploylatch
RELEASES="$ROOT/releases"
CURRENT="$ROOT/current"
PREVIOUS="$ROOT/previous"
SERVICE=deploylatch-demo.service
LOG=/var/log/deploylatch/deployments.log

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
release_at() {
    local path
    [[ -L "$1" ]] || return 1
    path=$(readlink -f -- "$1") || return 1
    [[ "$path" == "$RELEASES/"* && -f "$path/app.jar" ]] || return 1
    basename -- "$path"
}
activate() {
    local temporary="$CURRENT.tmp.$$"
    ln -s "releases/$1" "$temporary"
    mv -Tf "$temporary" "$CURRENT"
}
set_previous() {
    local temporary="$PREVIOUS.tmp.$$"
    ln -s "releases/$1" "$temporary"
    mv -Tf "$temporary" "$PREVIOUS"
}
record() {
    printf '%s | %s | %s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >> "$LOG"
}
healthy() {
    local expected="$1" attempt health version
    for ((attempt=1; attempt<=8; attempt++)); do
        health=$(curl -fsS --max-time 2 http://127.0.0.1:8080/health 2>/dev/null || true)
        version=$(curl -fsS --max-time 2 http://127.0.0.1:8080/version 2>/dev/null || true)
        [[ "$health" == OK && "$version" == "$expected" ]] && return 0
        sleep 1
    done
    return 1
}
prepare() {
    (( EUID == 0 )) || die 'Use sudo.'
    for executable in systemctl curl flock; do
        command -v "$executable" >/dev/null || die "Missing $executable"
    done
    systemctl cat "$SERVICE" >/dev/null 2>&1 || die "Install $SERVICE first."
    install -d -m 0755 "$RELEASES" /var/log/deploylatch
    touch "$LOG"
    exec 9>"$ROOT/.deploy.lock"
    flock -n 9 || die 'Another deployment is running.'
}
deploy() {
    local source="$1" version="$2" old=''
    [[ -f "$source" && -r "$source" ]] || die 'JAR not readable.'
    [[ "$version" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die 'Invalid release ID.'
    [[ ! -e "$RELEASES/$version" ]] || die "Release already exists: $version"
    old=$(release_at "$CURRENT" || true)
    install -d -m 0755 "$RELEASES/$version"
    install -m 0644 -- "$source" "$RELEASES/$version/app.jar"
    activate "$version"
    printf 'Deploying %s\n' "$version"
    if systemctl restart "$SERVICE" && healthy "$version"; then
        [[ -z "$old" ]] || set_previous "$old"
        record SUCCESS "$version" 'Health check passed'
        printf 'Deployment successful: %s\n' "$version"
        return 0
    fi
    printf 'Deployment failed: %s\n' "$version" >&2
    if [[ -z "$old" ]]; then
        systemctl stop "$SERVICE" || true
        rm -f "$CURRENT"
        record FAILED "$version" 'No previous release'
        return 1
    fi
    activate "$old"
    if systemctl restart "$SERVICE" && healthy "$old"; then
        record ROLLED_BACK "$version" "Restored $old"
        printf 'Restored %s\n' "$old"
    else
        record ROLLBACK_FAILED "$version" "Failed to recover $old"
        printf 'Recovery failed; inspect journalctl.\n' >&2
    fi
    return 1
}
rollback() {
    local before target
    before=$(release_at "$CURRENT") || die 'No active release.'
    target=$(release_at "$PREVIOUS") || die 'No previous release.'
    [[ "$before" != "$target" ]] || die 'Previous release already active.'
    activate "$target"
    if systemctl restart "$SERVICE" && healthy "$target"; then
        set_previous "$before"
        record MANUAL_ROLLBACK "$target" "Replaced $before"
        printf 'Restored %s\n' "$target"
    else
        activate "$before"
        systemctl restart "$SERVICE" || true
        record ROLLBACK_FAILED "$target" "Restored pointer to $before"
        return 1
    fi
}
status() {
    local active previous service
    active=$(release_at "$CURRENT" || true)
    previous=$(release_at "$PREVIOUS" || true)
    service=$(systemctl is-active "$SERVICE" || true)
    printf 'Current: %s\nPrevious: %s\nService: %s\n' "$active" "$previous" "$service"
    if [[ -n "$active" ]] && healthy "$active"; then
        printf 'Health: OK\n'
    else
        printf 'Health: unavailable\n'
    fi
}
usage() {
    printf '%s\n' 'Usage: deploylatch.sh deploy JAR RELEASE_ID | rollback | status | history'
}
(( $# >= 1 )) || { usage; exit 1; }
action="$1"
shift
case "$action" in
    deploy) (( $# == 2 )) || die 'Expected JAR and release ID.'; prepare; deploy "$1" "$2" ;;
    rollback) (( $# == 0 )) || die 'Unexpected arguments.'; prepare; rollback ;;
    status) (( $# == 0 )) || die 'Unexpected arguments.'; prepare; status ;;
    history) (( $# == 0 )) || die 'Unexpected arguments.'; prepare; if [[ -s "$LOG" ]]; then tail -n 20 "$LOG"; else echo 'No history yet.'; fi ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
esac
