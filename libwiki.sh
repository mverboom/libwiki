wiki() {
	local _CFG=~/.libwiki
    local action="$1"; shift

	readcfg() {
		local config="$1"
		local found=0
		local proxy

                _CFG=$(realpath $_CFG)
		test $(stat -c %a "$_CFG") -gt 600 && { _LIBWIKI_ERROR="libwiki: config file has unsafe permisions."; return 1; }
                _LIBWIKI_CURL=( "curl" )
		while IFS='= ' read var val; do
			if [[ $var == \[*] ]]
			then
				section=${var:1:-1}
				test "$section" != "$config" -a "$found" = "1" && break
				test "$section" = "$config" && found=1
			elif [[ $val ]]; then
			    test "$found" = "1" && declare -g "_LIBWIKI_${var^^}=$val"
			fi
		done < <(grep -v "^#" "$_CFG")
		test "$found" = "0" && { _LIBWIKI_ERROR="libwiki: no section $config found."; return 1; }
		if test "${_LIBWIKI_proxy}" != ""; then
                   _LIBWIKI_CURL+=( "--proxy" "${_LIBWIKI_proxy}" )
                else
                   _LIBWIKI_CURL+=( "--proxy" "" )
                fi
		return 0
    }

	mediawiki_open() {
		declare -g _LIBWIKIRM
		_LIBWIKI_COOKIE="$(mktemp)"
		_LIBWIKIRM+=( "$_LIBWIKI_COOKIE" )
		trap 'rm -f ${_LIBWIKIRM[@]}' INT TERM EXIT

		_LIBWIKI_AUTH=("--cookie-jar" "$_LIBWIKI_COOKIE"
			"--cookie" "$_LIBWIKI_COOKIE"
			"--insecure" "--silent" )

		local token=$("${_LIBWIKI_CURL[@]}" "${_LIBWIKI_AUTH[@]}" "${_LIBWIKI_URL}/api.php?action=query&meta=tokens&type=login&format=json" | jq -r .query.tokens.logintoken)
		test "$token" = "" && return 1

		res=$("${_LIBWIKI_CURL[@]}" "${_LIBWIKI_AUTH[@]}" \
			--data-urlencode "username=$_LIBWIKI_USER" \
			--data-urlencode "password=$_LIBWIKI_PASSWORD" \
			--data-urlencode "rememberMe=1" \
			--data-urlencode "logintoken=$token" \
			--data-urlencode "loginreturnurl=${_LIBWIKI_URL}/api.php" \
			"${_LIBWIKI_URL}/api.php?action=clientlogin&format=json" | jq -r .clientlogin.status )
		test "$?" -ne 0 && return 1
		test "$res" != "PASS" && return 1
		local csrf=$( "${_LIBWIKI_CURL[@]}" "${_LIBWIKI_AUTH[@]}" "${_LIBWIKI_URL}/api.php?action=query&meta=tokens&format=json" | jq -r .query.tokens.csrftoken)
		test "$csrf" = "" && return 1
		_LIBWIKI_AUTH+=( "--data-urlencode" "token=$csrf" )
        _LIBWIKI_OPEN=1
		return 0
	}

	dokuwiki_open() {
		declare -g _LIBWIKIRM
		_LIBWIKI_COOKIE="$(mktemp)"
		_LIBWIKIRM+=( "$_LIBWIKI_COOKIE" )
		trap 'rm -f ${_LIBWIKIRM[@]}' INT TERM EXIT
		_LIBWIKI_AUTH=("--cookie-jar" "$_LIBWIKI_COOKIE"
			"--cookie" "$_LIBWIKI_COOKIE"
			"--user" "${_LIBWIKI_USER}:${_LIBWIKI_PASSWORD}"
			"--insecure" "--silent"
			"--header" "Content-Type: application/xml" )
		result=$("${_LIBWIKI_CURL[@]}" "${_LIBWIKI_AUTH[@]}" \
			--data "
			<?xml version="1.0"?>
			<methodCall>
				<methodName>dokuwiki.login</methodName>
				<params>
					<param><value>$_LIBWIKI_USER</value></param>
					<param><value>$_LIBWIKI_PASSWORD</value></param>
				</params></methodCall>" \
			"$_LIBWIKI_URL"/lib/exe/xmlrpc.php | sed -n "/boolean/ s#.*oolean>\(.\+\)</boolean.*#\1#p" )
		test "$result" -eq "0" && return 1
        _LIBWIKI_OPEN=1
		return 0
	}

	mediawiki_save() {
		local name="$1"
		local src="$2"
		local output=$(mktemp)
		_LIBWIKIRM+=( "$output" )

		"${_LIBWIKI_CURL[@]}" "${_LIBWIKI_AUTH[@]}" -o "$output" --data-urlencode "title=$name" \
			--data-urlencode text@- \
			"${_LIBWIKI_URL}/api.php?action=edit&format=json" < <(
				if test "$src" = "-"; then
					cat
				else
					cat "$src"
				fi )
		if test "$(jq -r .edit.result < "$output")" != "Success"; then
			jq -r '.error.code, .error.info' < "$output"
			return 1
		fi
		return 0
	}

	dokuwiki_save() {
		local name="$1"
		local src="$2"
		local page=$(mktemp)
		_LIBWIKIRM+=( "$page" )
		echo "
			<?xml version="1.0"?>
			<methodCall>
				<methodName>wiki.putPage</methodName>
				<params>
					<param><value><string>$name</string></value></param>
					<param><value><string>" > "$page"
		if test "$src" = "-"; then
			cat | sed 's/</\&lt;/g; s/>/\&gt;/g; s/[^m]*m//g; s/\r//g' >> "$page"
		else
			test -e "$src" || { _LIBWIKI_ERROR="libwiki: file $src does not exist."; return 1; }
			cat "$src" | sed 's/</\&lt;/g; s/>/\&gt;/g; s/[^m]*m//g; s/\r//g' >> "$page"
		fi
		echo "</string></value></param></params></methodCall>" >> "$page"

		result=$( "${_LIBWIKI_CURL[@]}" "${_LIBWIKI_AUTH[@]}" \
			--data-binary @${page} \
			"$_LIBWIKI_URL"/lib/exe/xmlrpc.php | sed -n "/boolean/ s#.*oolean>\(.\+\)</boolean.*#\1#p" )
		test "$result" = "0" && return 1
		return 0
	}

	case "$action" in
		"profile")
			test -e "$_CFG" || { _LIBWIKI_ERROR="libwiki: No config file $_CFG"; return 1; }
                        test "$1" = "" && { _LIBWIKI_ERROR="libwiki: Empty profile name"; return 1; }
			readcfg "$1" || return 1
            _LIBWIKI_OPEN=0
            return 0
			;;
		"type")
			if test "$_LIBWIKI_OPEN" != ""; then
               echo "${_LIBWIKI_TYPE}"
               return 0
            else
			   _LIBWIKI_ERROR="libwiki: No wiki config read"
               return 1
            fi
			;;
		"error")
			test "${_LIBWIKI_ERROR}" != "" && echo "${_LIBWIKI_ERROR}"
            unset _LIBWIKI_ERROR
            return 0
			;;
		"connect")
			test "$_LIBWIKI_OPEN" = "" && { _LIBWIKI_ERROR="libwiki: No wiki config read"; return 1; }
			${_LIBWIKI_TYPE}_open 2> /dev/null ||
				{ _LIBWIKI_ERROR="libwiki: Unable to connect to wiki"; return 1; }
            return 0
			;;
		"save")
			test "$_LIBWIKI_OPEN" != "1" && { _LIBWIKI_ERROR="libwiki: No wiki connected"; return 1; }
			test "$#" -ne 2 && { _LIBWIKI_ERROR="libwiki: save requires 2 parameters."; return 1; }
			${_LIBWIKI_TYPE}_save "$1" "$2" || { _LIBWIKI_ERROR="libwiki: Unable save page"; return 1; }
            return 0
			;;
		*) _LIBWIKI_ERROR="libwiki: Unknown action $action"; return 1; ;;
	esac
}
