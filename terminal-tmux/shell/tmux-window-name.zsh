# Keep tmux window names aligned with the foreground command. Agent hooks may
# temporarily add an emoji prefix; returning to the zsh prompt always restores
# the current directory name.
autoload -Uz add-zsh-hook

_tmux_window_name_set() {
    local name="${1:-}"
    local state="${2:-command}"
    local target window_id owner_pane owner_window owner_status
    local active_pane active_name active_command active_path

    [[ -n "${TMUX:-}" && -n "$name" ]] || return 0
    command -v tmux >/dev/null 2>&1 || return 0

    target="${TMUX_PANE:-}"
    if [[ -z "$target" ]]; then
        target="$(tmux display-message -p '#{pane_id}' 2>/dev/null)" || return 0
    fi
    window_id="$(tmux display-message -p -t "$target" '#{window_id}' 2>/dev/null)" || return 0

    tmux set-option -pq -t "$target" @tmux_activity_name "$name" >/dev/null 2>&1 || true

    owner_pane="$(tmux show-options -wqv -t "$window_id" @codex_owner_pane 2>/dev/null)" || true

    if [[ "$state" == "idle" && "$owner_pane" == "$target" ]]; then
        tmux set-option -wuq -t "$window_id" @codex_owner_pane 2>/dev/null || true
        tmux set-option -puq -t "$target" @codex_status 2>/dev/null || true
        owner_pane=""
    fi

    if [[ -n "$owner_pane" ]]; then
        owner_window="$(tmux display-message -p -t "$owner_pane" '#{window_id}' 2>/dev/null)" || owner_window=""
        owner_status="$(tmux show-options -pqv -t "$owner_pane" @codex_status 2>/dev/null)" || owner_status=""
        if [[ "$owner_window" == "$window_id" && -n "$owner_status" ]]; then
            return 0
        fi

        tmux set-option -wuq -t "$window_id" @codex_owner_pane 2>/dev/null || true
        tmux set-option -puq -t "$owner_pane" @codex_status 2>/dev/null || true
    fi

    active_pane="$(tmux list-panes -t "$window_id" -F '#{?pane_active,#{pane_id},}' 2>/dev/null | sed -n '/./{p;q;}')" || active_pane=""
    [[ -n "$active_pane" ]] || active_pane="$target"

    active_name="$(tmux show-options -pqv -t "$active_pane" @tmux_activity_name 2>/dev/null)" || true
    if [[ -z "$active_name" ]]; then
        active_command="$(tmux display-message -p -t "$active_pane" '#{pane_current_command}' 2>/dev/null)" || active_command=""
        if [[ "$active_command" == "zsh" ]]; then
            active_path="$(tmux display-message -p -t "$active_pane" '#{pane_current_path}' 2>/dev/null)" || active_path=""
            active_name="${active_path:t}"
            [[ -n "$active_name" ]] || active_name="/"
        else
            active_name="$active_command"
        fi
    fi

    [[ -n "$active_name" ]] && tmux rename-window -t "$window_id" "$active_name" >/dev/null 2>&1 || true
}

_tmux_window_name_precmd() {
    local directory_name="${PWD:t}"
    [[ -n "$directory_name" ]] || directory_name="/"
    _tmux_window_name_set "$directory_name" idle
}

_tmux_window_name_preexec() {
    local command_line="${1:-}"
    local -a words
    local index=1
    local command_path command_name word script_name=""

    words=(${(z)command_line})
    (( ${#words} > 0 )) || return 0

    while (( index <= ${#words} )); do
        word="${words[$index]}"
        if [[ "$word" =~ '^[A-Za-z_][A-Za-z0-9_]*=' ]]; then
            (( index++ ))
            continue
        fi
        case "$word" in
            command|builtin|exec|noglob|nocorrect|nohup)
                (( index++ ))
                continue
                ;;
        esac
        break
    done

    (( index <= ${#words} )) || return 0
    command_path="${words[$index]}"
    command_name="${command_path:t}"

    case "$command_name" in
        python|python[0-9]*|pythonw|pypy|pypy[0-9]*)
            (( index++ ))
            while (( index <= ${#words} )); do
                word="${words[$index]}"
                case "$word" in
                    -m)
                        (( index++ ))
                        (( index <= ${#words} )) && script_name="${words[$index]}"
                        break
                        ;;
                    -c)
                        break
                        ;;
                    -W|-X|--check-hash-based-pycs)
                        (( index += 2 ))
                        continue
                        ;;
                    --)
                        (( index++ ))
                        (( index <= ${#words} )) && script_name="${words[$index]}"
                        break
                        ;;
                    -*)
                        (( index++ ))
                        continue
                        ;;
                    *)
                        script_name="$word"
                        break
                        ;;
                esac
            done
            ;;
        node|node[0-9]*)
            (( index++ ))
            while (( index <= ${#words} )); do
                word="${words[$index]}"
                case "$word" in
                    -e|--eval|-p|--print)
                        break
                        ;;
                    -r|--require|--loader|--import|--conditions|--inspect-port|--title)
                        (( index += 2 ))
                        continue
                        ;;
                    --)
                        (( index++ ))
                        (( index <= ${#words} )) && script_name="${words[$index]}"
                        break
                        ;;
                    -*)
                        (( index++ ))
                        continue
                        ;;
                    *)
                        script_name="$word"
                        break
                        ;;
                esac
            done
            ;;
    esac

    if [[ -n "$script_name" ]]; then
        _tmux_window_name_set "${script_name:t}"
    elif [[ -n "$command_name" ]]; then
        _tmux_window_name_set "$command_name"
    fi
}

add-zsh-hook precmd _tmux_window_name_precmd
add-zsh-hook preexec _tmux_window_name_preexec
