{
  config,
  lib,
  pkgs,
  ...
}:
let
  service = "trakt-backup";
  cfg = config.homelab.services.${service};
  hl = config.homelab;

  traktBackupScript = pkgs.writeShellScript "trakt-backup" ''
    set -euo pipefail

    CLIENT_ID="$(cat "${config.age.secrets.traktClientId.path}")"
    CLIENT_SECRET="$(cat "${config.age.secrets.traktClientSecret.path}")"
    USERNAME="${cfg.username}"
    TOKEN_FILE="${cfg.dataDir}/tokens.json"
    BACKUP_DIR="${cfg.backupDir}"
    API_BASE="https://api.trakt.tv"

    log() { echo "[trakt-backup] $*"; }
    warn() { echo "[trakt-backup] WARNING: $*" >&2; }
    fail() { echo "[trakt-backup] ERROR: $*" >&2; exit 1; }

    # --- Token Management ---

    device_code_flow() {
      log "No tokens found. Starting device code flow..."
      local response
      response=$(${pkgs.curl}/bin/curl -sf -X POST "$API_BASE/oauth/device/code" \
        -H "Content-Type: application/json" \
        -d "{\"client_id\": \"$CLIENT_ID\"}")

      local device_code user_code verification_url expires_in interval
      device_code=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.device_code')
      user_code=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.user_code')
      verification_url=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.verification_url')
      expires_in=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.expires_in')
      interval=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.interval')

      log "============================================"
      log "Go to: $verification_url"
      log "Enter code: $user_code"
      log "Waiting for authorization (expires in ''${expires_in}s)..."
      log "============================================"

      local elapsed=0
      while [ "$elapsed" -lt "$expires_in" ]; do
        sleep "$interval"
        elapsed=$((elapsed + interval))

        local token_response http_code
        token_response=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -X POST "$API_BASE/oauth/device/token" \
          -H "Content-Type: application/json" \
          -d "{\"code\": \"$device_code\", \"client_id\": \"$CLIENT_ID\", \"client_secret\": \"$CLIENT_SECRET\"}")

        http_code=$(echo "$token_response" | tail -1)
        local body
        body=$(echo "$token_response" | sed '$d')

        if [ "$http_code" = "200" ]; then
          echo "$body" | ${pkgs.jq}/bin/jq '{access_token, refresh_token, created_at, expires_in}' > "$TOKEN_FILE"
          chmod 600 "$TOKEN_FILE"
          log "Authorization successful! Tokens saved."
          return 0
        elif [ "$http_code" = "400" ]; then
          # Pending - user hasn't authorized yet
          continue
        elif [ "$http_code" = "404" ]; then
          fail "Invalid device code"
        elif [ "$http_code" = "409" ]; then
          fail "Code already used"
        elif [ "$http_code" = "410" ]; then
          fail "Code expired"
        elif [ "$http_code" = "418" ]; then
          fail "User denied the authorization"
        elif [ "$http_code" = "429" ]; then
          warn "Polling too fast, slowing down..."
          interval=$((interval + 1))
        fi
      done

      fail "Device code flow timed out. Please try again."
    }

    refresh_token() {
      log "Refreshing access token..."
      local refresh_tok
      refresh_tok=$(${pkgs.jq}/bin/jq -r '.refresh_token' "$TOKEN_FILE")

      local response http_code
      response=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -X POST "$API_BASE/oauth/token" \
        -H "Content-Type: application/json" \
        -d "{\"refresh_token\": \"$refresh_tok\", \"client_id\": \"$CLIENT_ID\", \"client_secret\": \"$CLIENT_SECRET\", \"grant_type\": \"refresh_token\", \"redirect_uri\": \"urn:ietf:wg:oauth:2.0:oob\"}")

      http_code=$(echo "$response" | tail -1)
      local body
      body=$(echo "$response" | sed '$d')

      if [ "$http_code" = "200" ]; then
        echo "$body" | ${pkgs.jq}/bin/jq '{access_token, refresh_token, created_at, expires_in}' > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        log "Token refreshed successfully."
      else
        fail "Token refresh failed (HTTP $http_code): $body"
      fi
    }

    ensure_token() {
      if [ ! -f "$TOKEN_FILE" ]; then
        device_code_flow
        return
      fi

      local access_token
      access_token=$(${pkgs.jq}/bin/jq -r '.access_token' "$TOKEN_FILE")

      # Test the token with a lightweight request
      local http_code
      http_code=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" \
        "$API_BASE/users/$USERNAME/settings" \
        -H "Authorization: Bearer $access_token" \
        -H "trakt-api-key: $CLIENT_ID" \
        -H "trakt-api-version: 2")

      if [ "$http_code" = "401" ]; then
        refresh_token
      elif [ "$http_code" != "200" ]; then
        warn "Unexpected status $http_code when testing token, attempting refresh..."
        refresh_token
      else
        log "Token is valid."
      fi
    }

    # --- API Fetching ---

    fetch_endpoint() {
      local endpoint="$1"
      local output_file="$2"
      local access_token
      access_token=$(${pkgs.jq}/bin/jq -r '.access_token' "$TOKEN_FILE")

      local page=1
      local all_data="[]"

      while true; do
        local response headers http_code body
        response=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -D- \
          "$API_BASE/$endpoint$(echo "$endpoint" | grep -q '?' && echo '&' || echo '?')extended=gdpr&page=$page&limit=1000" \
          -H "Authorization: Bearer $access_token" \
          -H "trakt-api-key: $CLIENT_ID" \
          -H "trakt-api-version: 2" \
          -H "Content-Type: application/json")

        # Split headers and body - curl -D- writes headers then body
        # With -w, the http_code is on the last line
        http_code=$(echo "$response" | tail -1)
        # Remove last line (http_code), split on empty line between headers and body
        local full_response
        full_response=$(echo "$response" | sed '$d')
        headers=$(echo "$full_response" | sed '/^\r$/q')
        body=$(echo "$full_response" | sed '1,/^\r$/d')

        if [ "$http_code" != "200" ]; then
          warn "Endpoint $endpoint page $page returned HTTP $http_code"
          break
        fi

        all_data=$(echo "$all_data" "$body" | ${pkgs.jq}/bin/jq -s '.[0] + .[1]')

        local page_count
        page_count=$(echo "$headers" | grep -i 'x-pagination-page-count' | tr -d '\r' | awk -F': ' '{print $2}')

        if [ -z "$page_count" ] || [ "$page" -ge "$page_count" ]; then
          break
        fi

        page=$((page + 1))
      done

      echo "$all_data" | ${pkgs.jq}/bin/jq '.' > "$output_file"
      log "Fetched $endpoint -> $(echo "$all_data" | ${pkgs.jq}/bin/jq 'length') items"
    }

    # --- Main ---

    ensure_token

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    ENDPOINTS=(
      "users/$USERNAME/watchlist/movies:watchlist-movies.json"
      "users/$USERNAME/watchlist/shows:watchlist-shows.json"
      "users/$USERNAME/ratings/movies:ratings-movies.json"
      "users/$USERNAME/ratings/shows:ratings-shows.json"
      "users/$USERNAME/ratings/seasons:ratings-seasons.json"
      "users/$USERNAME/ratings/episodes:ratings-episodes.json"
      "users/$USERNAME/history/movies:history-movies.json"
      "users/$USERNAME/history/episodes:history-episodes.json"
      "users/$USERNAME/collection/movies:collection-movies.json"
      "users/$USERNAME/collection/shows:collection-shows.json"
      "users/$USERNAME/comments:comments.json"
      "users/$USERNAME/notes/ratings:notes-ratings.json"
      "users/$USERNAME/favorites:favorites.json"
      "users/$USERNAME/recommendations/movies:recommendations-movies.json"
      "users/$USERNAME/recommendations/shows:recommendations-shows.json"
    )

    FAILED=0
    for entry in "''${ENDPOINTS[@]}"; do
      endpoint="''${entry%%:*}"
      filename="''${entry##*:}"
      fetch_endpoint "$endpoint" "$TMPDIR/$filename" || FAILED=$((FAILED + 1))
    done

    # Fetch custom lists and their items
    log "Fetching custom lists..."
    ACCESS_TOKEN=$(${pkgs.jq}/bin/jq -r '.access_token' "$TOKEN_FILE")
    lists_response=$(${pkgs.curl}/bin/curl -sf \
      "$API_BASE/users/$USERNAME/lists" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "trakt-api-key: $CLIENT_ID" \
      -H "trakt-api-version: 2" \
      -H "Content-Type: application/json") || true

    if [ -n "$lists_response" ] && [ "$lists_response" != "null" ]; then
      echo "$lists_response" | ${pkgs.jq}/bin/jq '.' > "$TMPDIR/lists.json"
      list_slugs=$(echo "$lists_response" | ${pkgs.jq}/bin/jq -r '.[].ids.slug // empty')
      for slug in $list_slugs; do
        fetch_endpoint "users/$USERNAME/lists/$slug/items" "$TMPDIR/list-$slug.json" || FAILED=$((FAILED + 1))
      done
    fi

    TOTAL=''${#ENDPOINTS[@]}
    if [ "$FAILED" -ge "$TOTAL" ]; then
      fail "All endpoints failed. Aborting."
    fi

    # Package into zip
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
    ZIP_FILE="$BACKUP_DIR/''${TIMESTAMP}-$USERNAME.zip"
    (cd "$TMPDIR" && ${pkgs.zip}/bin/zip -q "$ZIP_FILE" ./*.json)

    log "Backup complete: $ZIP_FILE"
  '';
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption "Trakt account backup";
    username = lib.mkOption {
      type = lib.types.str;
      default = "magic_sk";
      description = "Trakt username to back up";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/${service}";
      description = "Directory for token state";
    };
    backupDir = lib.mkOption {
      type = lib.types.str;
      default = "${hl.mounts.Nitor}/Backups/trakt";
      description = "Directory for backup zip files";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "Systemd calendar expression for backup frequency";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 ${hl.user} ${hl.group} -"
      "d ${cfg.backupDir} 0775 ${hl.user} ${hl.group} -"
    ];

    environment.persistence."/".directories = [
      {
        directory = cfg.dataDir;
        user = hl.user;
        group = hl.group;
        mode = "0700";
      }
    ];

    systemd.services.${service} = {
      description = "Trakt account backup";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = hl.user;
        Group = hl.group;
        ExecStart = "${traktBackupScript}";
      };
    };

    systemd.timers.${service} = {
      description = "Weekly Trakt backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
