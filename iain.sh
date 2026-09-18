# iain.sh
#
# Personal shell helpers (aliases + functions) sourced into ~/.zshrc by
# install.sh. Keep machine-specific bits (PATH, secrets, tool-managed blocks)
# in ~/.zshrc itself; everything reusable lives here so it's version controlled.

# --- generic dev env --------------------------------------------------------
export COMPOSE_BAKE=true
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1
export AWS_PROFILE=dev

# --- aliases ----------------------------------------------------------------
alias ll='ls -alF'
alias python='python3'
alias py='python3'
alias gu="$HOME/dev/scripts/gu.sh"

# --- aws (from Tony) --------------------------------------------------------
alias awsli='aws sso login --sso-session asi-inc'
alias awsce="aws configure export-credentials --profile dev --format env"
alias awscen="aws configure export-credentials --profile dev --format env-no-export"
alias awscep="aws configure export-credentials --profile prod --format env"
alias awscepn="aws configure export-credentials --profile prod --format env-no-export"

function awscene() {
    local creds
    creds=$(awscen) || return 1

    if [ ! -f .env-local ]; then
        echo "$creds"
        return
    fi

    while IFS= read -r line; do
        local varname="${line%%=*}"
        local value="${line#*=}"
        if grep -q "^${varname}=" .env-local; then
            awk -v var="$varname" -v val="$value" '
                $0 ~ "^" var "=" { print var "=" val; next }
                { print }
            ' .env-local > .env-local.tmp && mv .env-local.tmp .env-local
        else
            echo "$line" >> .env-local
        fi
    done <<< "$creds"

    echo "Updated .env-local with AWS credentials"
}

# CodeArtifact tokens are good for ~12h, but they only ever lived in the shell
# that ran awsfix, so every new terminal started blank and had to re-run it.
# Now awsfix caches the token (+ expiry) to a file, and every new shell reloads
# it via _asi_load_codeartifact at the bottom of this file — no re-auth needed
# until the token actually expires.
_ASI_CA_CACHE="$HOME/.cache/asi/codeartifact.env"
_ASI_CA_DURATION=43200 # 12h, the CodeArtifact maximum

# Derive the registry vars from a token and export them into this shell.
function _asi_export_codeartifact() {
    local token="$1"
    export CODEARTIFACT_AUTH_TOKEN="$token"
    export DEVPI_URL="https://aws:${token}@uni-codeartifact-209479306031.d.codeartifact.us-east-2.amazonaws.com/pypi/uni-codeartifact/simple/"
    export UV_DEFAULT_INDEX="$DEVPI_URL"
    export CARGO_REGISTRIES_UNI_TOKEN="$token"
    # Index + provider live in ~/.cargo/config.toml for native builds, but the
    # Docker build has no config.toml and reads them only from these env vars
    # (passed through as build args). Export them so awsfix alone suffices.
    export CARGO_REGISTRIES_UNI_INDEX="sparse+https://uni-codeartifact-209479306031.d.codeartifact.us-east-2.amazonaws.com/cargo/uni-codeartifact/"
    export CARGO_REGISTRIES_UNI_CREDENTIAL_PROVIDER="cargo:token"
}

# Load a still-valid cached token into this shell. Returns non-zero (silently)
# if there's no cache or it has expired, so callers can decide whether to fetch.
function _asi_load_codeartifact() {
    [ -f "$_ASI_CA_CACHE" ] || return 1

    local token expiry now
    # shellcheck disable=SC1090
    source "$_ASI_CA_CACHE"
    token="$_ASI_CA_TOKEN"
    expiry="$_ASI_CA_EXPIRY"
    now=$(date +%s)

    # Treat the token as stale 5 min early to avoid edge-of-expiry failures.
    if [ -z "$token" ] || [ -z "$expiry" ] || [ "$now" -ge "$((expiry - 300))" ]; then
        return 1
    fi

    _asi_export_codeartifact "$token"
}

function awsfix() {
    export AWS_PROFILE=artifacts

    # If the cached CodeArtifact token is still valid we authenticated recently
    # and nothing has expired: load it into this shell and stop. No browser, no
    # re-fetch, no docker re-login. This is the common case, so awsfix becomes a
    # near no-op in a fresh shell instead of opening the browser every time.
    if _asi_load_codeartifact; then
        return 0
    fi

    # Cache is missing or stale. Only open the browser when the SSO session has
    # actually expired -- a still-valid session lets `aws sso login` be skipped
    # entirely. `aws sts get-caller-identity` succeeds silently while the cached
    # SSO token is good.
    if ! aws sts get-caller-identity --profile dev >/dev/null 2>&1; then
        aws sso login
    fi

    aws ecr get-login-password --region us-east-2 --profile dev \
        | docker login --username AWS --password-stdin 209479306031.dkr.ecr.us-east-2.amazonaws.com

    local token
    token=$(aws codeartifact get-authorization-token \
        --domain uni-codeartifact \
        --domain-owner 209479306031 \
        --region us-east-2 \
        --duration-seconds "$_ASI_CA_DURATION" \
        --query authorizationToken \
        --output text) || return 1

    # Cache the token so new shells pick it up without re-authenticating.
    mkdir -p "$(dirname "$_ASI_CA_CACHE")"
    umask 077
    {
        echo "_ASI_CA_TOKEN='$token'"
        echo "_ASI_CA_EXPIRY=$(( $(date +%s) + _ASI_CA_DURATION ))"
    } > "$_ASI_CA_CACHE"

    _asi_export_codeartifact "$token"
}

# --- misc helpers -----------------------------------------------------------
function h() {
    history | grep $1
}

function g() {
    git fetch && git switch $1
}

function a() {
    source ./.venv/bin/activate
}

function e() {
    code ~/.zshrc
}

function p() {
    npm run prettier:fix
    git add -A
    git commit -m "make the code so pretty :)"
    git push
}

function r() {
    source ~/.zshrc
}

function gsm() {
    git add -A
    git stash save
    git switch main
    git pull
    git stash pop
}

function ds() {
    docker stop $(docker ps -q)
}

function cr() {
    cd ~/dev/projects/rams
}

# Pick up a cached CodeArtifact token on shell startup (no-op if missing/stale).
_asi_load_codeartifact
