# Global aliases can break things. Unset before using any non-builtins.
[[ -o aliases ]] && _vim_mode_shopt_aliases=1
builtin set -o no_aliases

bindkey -v

#${(%):-%x}_debug () { print -r "$(date) $@" >> /tmp/zsh-debug-vim-mode.log 2>&1 }


# Special keys {{{1

# NB: The terminfo sequences are meant to be used with the terminal
# in *application mode*. This is properly initiated with `echoti smkx`,
# usually in a zle line-init hook widget. But it may cause problems:
# https://github.com/robbyrussell/oh-my-zsh/pull/5113
#
# So for now, leave smkx untouched, and let the framework deal with it.
# Instead, read from terminfo but also hard-code values that various
# terminals use.
#
# Please open an issue if your special keys (Home, End, arrow keys,
# etc.) are not being recognized here!
#
# Extra info:
# http://invisible-island.net/xterm/xterm.faq.html#xterm_arrows
# https://stackoverflow.com/a/29408977/749778

zmodload zsh/terminfo

typeset -A -H vim_mode_special_keys

function vim-mode-define-special-key () {
    local name="$1" tiname="$2"
    local -a seqs
    # Note that (V) uses the "^[" notation for <Esc>, and "^X" for <Ctrl-x>
    [[ -n $tiname && -n $terminfo[$tiname] ]] && seqs+=${(V)terminfo[$tiname]}
    for seq in ${@[3,-1]}; do
        seqs+=$seq
    done
    vim_mode_special_keys[$name]=${${(uOqqq)seqs}}
}

# Explicitly check for VT100 versions (both normal and application mode)
vim-mode-define-special-key Left       kcub1 "^[[D" "^[OD"
vim-mode-define-special-key Right      kcuf1 "^[[C" "^[OC"
vim-mode-define-special-key Up         kcuu1 "^[[A" "^[OA"
vim-mode-define-special-key Down       kcud1 "^[[B" "^[OB"
# These are XTerm and various others
vim-mode-define-special-key Home       khome "^[[1~" "^[[H"
vim-mode-define-special-key End        kend  "^[[4~" "^[[F"
vim-mode-define-special-key PgUp       kpp   "^[[5~"
vim-mode-define-special-key PgDown     knp   "^[[6~"
vim-mode-define-special-key Insert     kich1 "^[[2~"
vim-mode-define-special-key Delete     kdch1 "^[[3~"
vim-mode-define-special-key Shift-Tab  kcbt  "^[[Z"
# These aren't in terminfo; these are for:   XTerm  &  Rxvt
vim-mode-define-special-key Ctrl-Left  ''    "^[[1;5D" "^[Od"
vim-mode-define-special-key Ctrl-Right ''    "^[[1;5C" "^[Oc"
vim-mode-define-special-key Ctrl-Up    ''    "^[[1;5A" "^[Oa"
vim-mode-define-special-key Ctrl-Down  ''    "^[[1;5B" "^[Ob"
vim-mode-define-special-key Alt-Left   ''    "^[[1;3D" "^[^[[D"
vim-mode-define-special-key Alt-Right  ''    "^[[1;3C" "^[^[[C"
vim-mode-define-special-key Alt-Up     ''    "^[[1;3A" "^[^[[A"
vim-mode-define-special-key Alt-Down   ''    "^[[1;3B" "^[^[[B"

#for k in ${(k)vim_mode_special_keys}; do
#    printf '%-12s' "$k:";
#    for x in ${(z)vim_mode_special_keys[$k]}; do printf "%8s" ${(Q)x}; done;
#    printf "\n";
#done


# + vim-mode-bindkey {{{1
function vim-mode-bindkey () {
    local -a maps
    local command

    while (( $# )); do
        [[ $1 = '--' ]] && break
        maps+=$1
        shift
    done
    shift

    command=$1
    shift

    # A key combo can be made of more than one key press, so a binding for
    # <Home> <End> will map to '^[[1~^[[4~', for example. XXX Except this
    # doesn't seem to work. ZLE just wants a single special key for viins
    # & vicmd (multiples work in emacs). Oh, well, this accumulator
    # doesn't hurt and may come in handy. Just only call vim-mode-bindkey
    # with one special key.

    function vim-mode-accum-combo () {
        typeset -g -a combos
        local combo="$1"; shift
        if (( $#@ )); then
            local cur="$1"; shift
            if (( ${+vim_mode_special_keys[$cur]} )); then
                for seq in ${(z)vim_mode_special_keys[$cur]}; do
                    vim-mode-accum-combo "$combo${(Q)seq}" "$@"
                done
            else
                vim-mode-accum-combo "$combo$cur" "$@"
            fi
        else
            combos+="$combo"
        fi
    }

    local -a combos
    vim-mode-accum-combo '' "$@"
    for c in ${combos}; do
        for m in ${maps}; do
            bindkey -M $m "$c" $command
        done
    done
}

if [[ -z $VIM_MODE_NO_DEFAULT_BINDINGS ]]; then
    # Emacs-like bindings {{{1
    vim-mode-bindkey viins -- beginning-of-line                  '^A'
    vim-mode-bindkey viins -- backward-char                      '^B'
    vim-mode-bindkey viins -- end-of-line                        '^E'
    vim-mode-bindkey viins -- forward-char                       '^F'
    vim-mode-bindkey viins -- kill-line                          '^K'
    vim-mode-bindkey viins -- backward-kill-line                 '^U'
    vim-mode-bindkey viins -- backward-kill-word                 '^W'
    vim-mode-bindkey viins -- yank                               '^Y'

    # Avoid key bindings that conflict with <Esc> entering NORMAL mode, like
    # - common movement keys (hljk...)
    # - common actions (dxcr...)
    # But make this configurable: some people will never use ^[b and would
    # rather be sure not to have a conflict, while others use it a lot and will
    # rarely type 'b' as the first key in NORMAL mode. Which behavior shoudl win
    # is very user-dependent.
    vim-mode-maybe-bind() {
        local k="$1"; shift
        if (( $+VIM_MODE_VICMD_KEY )) \
            || [[ ${VIM_MODE_ESC_PREFIXED_WANTED-^?^Hbdf.g} = *${k}* ]];
        then
            vim-mode-bindkey "$@"
        fi
    }

    vim-mode-maybe-bind '^?' viins vicmd -- backward-kill-word         '^[^?'
    vim-mode-maybe-bind '^H' viins vicmd -- backward-kill-word         '^[^H'
    vim-mode-maybe-bind b viins vicmd -- backward-word                 '^[b'
    vim-mode-maybe-bind d viins vicmd -- kill-word                     '^[d'
    vim-mode-maybe-bind f viins vicmd -- forward-word                  '^[f'
    vim-mode-maybe-bind h viins       -- run-help                      '^[h'
    # u is not likely to cause conflict, but keep it here with l
    vim-mode-maybe-bind u viins       -- up-case-word                  '^[u'
    vim-mode-maybe-bind l viins       -- down-case-word                '^[l'

    # Some <Esc>-prefixed bindings that should rarely conflict with NORMAL mode,
    # so always define them
    # '.' usually comes after some other keystrokes
    vim-mode-maybe-bind . viins vicmd -- insert-last-word              '^[.'
    # 'g...' bindings are not commonly-used; see `bindkey -pM vicmd g`
    vim-mode-maybe-bind g viins       -- get-line                      '^[g'
    vim-mode-bindkey viins       -- push-line                          '^Q'

    vim-mode-bindkey viins vicmd -- beginning-of-line                  Home
    vim-mode-bindkey viins vicmd -- end-of-line                        End
    vim-mode-bindkey viins vicmd -- backward-word                      Ctrl-Left
    vim-mode-bindkey viins vicmd -- backward-word                      Alt-Left
    vim-mode-bindkey viins vicmd -- forward-word                       Ctrl-Right
    vim-mode-bindkey viins vicmd -- forward-word                       Alt-Right
    vim-mode-bindkey viins vicmd -- up-line-or-history                 PgUp
    vim-mode-bindkey viins vicmd -- down-line-or-history               PgDown

    vim-mode-bindkey vicmd       -- end-of-buffer-or-history           'G'
    vim-mode-bindkey vicmd       -- up-line                            gk
    vim-mode-bindkey vicmd       -- down-line                          gj

    vim-mode-bindkey viins       -- overwrite-mode                     Insert
    vim-mode-bindkey viins       -- delete-char                        Delete
    vim-mode-bindkey viins       -- reverse-menu-complete              Shift-Tab
    vim-mode-bindkey viins       -- delete-char-or-list                '^D'
    vim-mode-bindkey viins       -- backward-delete-char               '^H'
    vim-mode-bindkey viins       -- backward-delete-char               '^?'
    vim-mode-bindkey viins       -- redisplay                          '^X^R'
    vim-mode-bindkey viins       -- exchange-point-and-mark            '^X^X'

    vim-mode-bindkey       vicmd -- run-help                           'H'
    vim-mode-bindkey       vicmd -- redo                               'U'
    vim-mode-bindkey       vicmd -- vi-yank-eol                        'Y'

    autoload -U edit-command-line
    zle -N edit-command-line
    vim-mode-bindkey viins vicmd -- edit-command-line                  '^X^E'
    vim-mode-bindkey       vicmd -- edit-command-line                  '^V'

    if [[ -n $HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND ]]; then
        vim-mode-bindkey viins vicmd -- history-substring-search-up    '^P'
        vim-mode-bindkey viins vicmd -- history-substring-search-down  '^N'
        vim-mode-bindkey viins vicmd -- history-substring-search-up    Up
        vim-mode-bindkey viins vicmd -- history-substring-search-down  Down
    else
        autoload -Uz history-search-end
        zle -N history-beginning-search-backward-end history-search-end
        zle -N history-beginning-search-forward-end history-search-end

        vim-mode-bindkey viins vicmd -- history-beginning-search-backward-end '^P'
        vim-mode-bindkey viins vicmd -- history-beginning-search-forward-end  '^N'
        vim-mode-bindkey viins vicmd -- history-beginning-search-backward-end Up
        vim-mode-bindkey viins vicmd -- history-beginning-search-forward-end  Down
    fi

    # Compatibility with zsh-autosuggestions; see issue #25
    if zle -la up-line-or-beginning-search; then
        vim-mode-bindkey       vicmd -- down-line-or-beginning-search  j
        vim-mode-bindkey       vicmd -- up-line-or-beginning-search    k
    fi

    vim-mode-bindkey       vicmd -- down-history  '^[J'
    vim-mode-bindkey       vicmd -- up-history    '^[K'

    # Enable surround text-objects (quotes, brackets) {{{1

    autoload -U select-bracketed
    zle -N select-bracketed
    for m in visual viopp; do
        for c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
            vim-mode-bindkey $m -- select-bracketed $c
        done
    done

    autoload -U select-quoted
    zle -N select-quoted
    for m in visual viopp; do
        for c in {a,i}{\',\",\`}; do
            vim-mode-bindkey $m -- select-quoted $c
        done
    done

    autoload -Uz surround
    zle -N delete-surround surround
    zle -N change-surround surround
    zle -N add-surround surround
    vim-mode-bindkey vicmd         -- change-surround gsr
    vim-mode-bindkey vicmd         -- delete-surround gsd
    vim-mode-bindkey vicmd visual  -- add-surround    gsa


    # Escape shortcut {{{1
    # From http://bewatermyfriend.org/posts/2010/08-08.21-16-02-computer.html
    #   > Copyright (c) 2010, Frank Terbeck <ft@bewatermyfriend.org>
    #   > The same licensing terms as with zsh apply.
    if (( $+VIM_MODE_VICMD_KEY )); then
        vim-mode-bindkey viins -- vi-cmd-mode "$VIM_MODE_VICMD_KEY"

        case $VIM_MODE_VICMD_KEY in
            ^[Dd] )
                builtin set -o ignore_eof
                vim-mode-bindkey vicmd -- vim-mode-accept-or-eof "$VIM_MODE_VICMD_KEY"

                function vim-mode-accept-or-eof() {
                    if [[ $#BUFFER = 0 ]]; then
                        exit
                    else
                        zle accept-line
                    fi
                }
                zle -N vim-mode-accept-or-eof
                ;;
        esac
    fi

    unfunction vim-mode-maybe-bind
fi

# Identifying the editing mode {{{1

if [[ $VIM_MODE_TRACK_KEYMAP != no ]]; then
    # Export the main variable so higher-level processes can view it;
    # e.g., github:starship/starship uses this
    export VIM_MODE_KEYMAP

    autoload -Uz add-zsh-hook
    autoload -Uz add-zle-hook-widget

    # Compatibility with old variable names
    (( $+MODE_INDICATOR_I )) && : ${MODE_INDICATOR_VIINS=MODE_INDICATOR_I}
    (( $+MODE_INDICATOR_N )) && : ${MODE_INDICATOR_VICMD=MODE_INDICATOR_N}
    (( $+MODE_INDICATOR_C )) && : ${MODE_INDICATOR_SEARCH=MODE_INDICATOR_C}

    typeset -g -a vim_mode_keymap_funcs=()

    vim-mode-precmd           () { vim-mode-handle-event precmd           "$KEYMAP" }
    add-zsh-hook precmd vim-mode-precmd

    vim-mode-isearch-update   () { vim-mode-handle-event isearch-update   "$KEYMAP" }
    vim-mode-isearch-exit     () { vim-mode-handle-event isearch-exit     "$KEYMAP" }
    vim-mode-line-pre-redraw  () { vim-mode-handle-event line-pre-redraw  "$KEYMAP" }
    vim-mode-line-init        () { vim-mode-handle-event line-init        "$KEYMAP" }

    () {
        local w; for w in "$@"; do add-zle-hook-widget $w vim-mode-$w; done
    } isearch-exit isearch-update line-pre-redraw line-init

    typeset -g vim_mode_keymap_state=

    vim-mode-handle-event () {
        #${(%):-%x}_debug "handle-event [${(qq)@}][cur:${VIM_MODE_KEYMAP}]"

        local hook="$1"
        local keymap="$2"
        rc=0  # Assume we'll succeed

        case $hook in
        line-init )
            [[ $VIM_MODE_KEYMAP = vicmd ]] && zle && zle vi-cmd-mode
            ;;
        line-pre-redraw )
            # This hook is called (maybe several times) on every action except
            # for the initial prompt drawing
            case $vim_mode_keymap_state in
            '' )
                vim_mode_set_keymap "$keymap"
                ;;
            *-escape )
                vim_mode_set_keymap "${vim_mode_keymap_state%-escape}"
                vim_mode_keymap_state=
                ;;
            *-update )
                # Normal update in isearch mode
                vim_mode_keymap_state=${vim_mode_keymap_state%-update}
                vim_mode_set_keymap isearch
                ;;
            * )
                # ^C was hit during isearch mode!
                vim_mode_set_keymap "$vim_mode_keymap_state"
                vim_mode_keymap_state=
                ;;
            esac
            ;;
        isearch-update )
            if [[ $keymap = vicmd ]]; then
                # This is an abnormal exit from search (like <Esc>)
                vim_mode_keymap_state+='-escape'
            elif [[ $VIM_MODE_KEYMAP != isearch ]]; then
                # Normal update, starting search mode
                vim_mode_keymap_state=${VIM_MODE_KEYMAP}-update
            else
                # Normal update, staying in search mode
                vim_mode_keymap_state+=-update
            fi
            ;;
        isearch-exit )
            if [[ $VIM_MODE_KEYMAP = isearch ]]; then
                # This could be a normal (movement key) exit, but it could also
                # be ^G which behaves almost like <Esc>. So don't trust $keymap.
                vim_mode_keymap_state+='-escape'
            fi

            # Otherwise, we already exited search via abnormal isearch-update,
            # so there is nothing to do here.
            ;;
        precmd )
            # When the prompt is first shown line-pre-redraw does not get called
            # so the state must be initialized here
            vim_mode_keymap_state=
            vim_mode_set_keymap $(vim-mode-initial-keymap)
            ;;
        * )
            # Should not happen
            zle && zle -M "zsh-vim-mode internal error: bad hook $hook"
            rc=1  # Oops
            ;;
        esac

        return $rc
    }

    vim_mode_set_keymap () {
        local keymap="$1"

        [[ $keymap = main || $keymap = '' ]] && keymap=viins

        if [[ $keymap = vicmd ]]; then
            local active=${REGION_ACTIVE:-0}
            if [[ $active = 1 ]]; then
                keymap=visual
            elif [[ $active = 2 ]]; then
                keymap=vline
            fi
        elif [[ $keymap = viins ]]; then
            [[ $ZLE_STATE = *overwrite* ]] && keymap=replace
        fi

        #${(%):-%x}_debug "     -> $keymap"

        [[ $VIM_MODE_KEYMAP = $keymap ]] && return

        # Can be used by prompt themes, etc.
        VIM_MODE_KEYMAP=$keymap

        local func
        for func in ${vim_mode_keymap_funcs[@]}; do
            ${func} "$keymap"
        done
    }

    vim-mode-initial-keymap () {
        case ${VIM_MODE_INITIAL_KEYMAP:-viins} in
            last)
                case $VIM_MODE_KEYMAP in
                    vicmd|visual|vline) print vicmd ;;
                    *)                  print viins ;;
                esac
                ;;
            vicmd)
                print vicmd ;;
            *)
                print viins ;;
        esac
    }

    # Editing mode indicator - Prompt string {{{1

    # Unique prefix to tag the mode indicator text in the prompt.
    # If ZLE_RPROMPT_INDENT is < 1, zle gets confused if $RPS1 isn't empty but
    # printing it doesn't move the cursor.
    (( ${ZLE_RPROMPT_INDENT:-1} > 0 )) \
        && vim_mode_indicator_pfx="%837(l,,)" \
        || vim_mode_indicator_pfx="%837(l,, )"

    # If mode indicator wasn't setup by theme, define default
    vim-mode-set-up-indicators () {
        local indicator=${MODE_INDICATOR_VICMD-${MODE_INDICATOR-DEFAULT}}
        local set=$((
            $+MODE_INDICATOR_VIINS +
            $+MODE_INDICATOR_REPLACE +
            $+MODE_INDICATOR_VICMD +
            $+MODE_INDICATOR_SEARCH +
            $+MODE_INDICATOR_VISUAL +
            $+MODE_INDICATOR_VLINE))

        if [[ -n $indicator || $set > 0 ]]; then
            if (( ! $set )); then
                if [[ $indicator = DEFAULT ]]; then
                    MODE_INDICATOR_VICMD='%F{10}<%F{2}<<%f'
                    MODE_INDICATOR_REPLACE='%F{9}<%F{1}*<%f'
                    MODE_INDICATOR_SEARCH='%F{13}<%F{5}?<%f'
                    MODE_INDICATOR_VISUAL='%F{12}<%F{4}-<%f'
                    MODE_INDICATOR_VLINE='%F{12}<%F{4}=<%f'
                else
                    MODE_INDICATOR_VICMD=$indicator
                fi

                # Replace / Search indicator defaults to viins
                (( $+MODE_INDICATOR_VIINS )) && \
                    : ${MODE_INDICATOR_REPLACE=$MODE_INDICATOR_VIINS}
                (( $+MODE_INDICATOR_VIINS )) && \
                    : ${MODE_INDICATOR_SEARCH=$MODE_INDICATOR_VIINS}

                # Visual indicator defaults to vicmd
                (( $+MODE_INDICATOR_VICMD )) && \
                    : ${MODE_INDICATOR_VISUAL=$MODE_INDICATOR_VICMD}
                (( $+MODE_INDICATOR_VISUAL )) && \
                    : ${MODE_INDICATOR_VLINE=$MODE_INDICATOR_VISUAL}

                MODE_INDICATOR_PROMPT=${vim_mode_indicator_pfx}${MODE_INDICATOR_VIINS}

                if (( !$+RPS1 )); then
                    [[ -o promptsubst ]] \
                        && RPS1='${MODE_INDICATOR_PROMPT}' \
                        || RPS1="$MODE_INDICATOR_PROMPT"
                fi
            fi
        else
            unset MODE_INDICATOR_PROMPT
        fi
    }

    vim-mode-update-prompt () {
        local keymap="$1"

        # See if user requested indicators since last time
        (( $+MODE_INDICATOR_PROMPT )) || vim-mode-set-up-indicators
        (( $+MODE_INDICATOR_PROMPT )) || return

        local -A modes=(
            I  ${vim_mode_indicator_pfx}${MODE_INDICATOR_VIINS}
            C  ${vim_mode_indicator_pfx}${MODE_INDICATOR_VICMD}
            R  ${vim_mode_indicator_pfx}${MODE_INDICATOR_REPLACE}
            S  ${vim_mode_indicator_pfx}${MODE_INDICATOR_SEARCH}
            V  ${vim_mode_indicator_pfx}${MODE_INDICATOR_VISUAL}
            L  ${vim_mode_indicator_pfx}${MODE_INDICATOR_VLINE}
            # In case user has changed the mode string since last call, look
            # for the previous value as well as set of current values
            p  ${MODE_INDICATOR_PROMPT}
        )

        # Pattern that will match any value from $modes. Reverse sort, so that
        # if one pattern is a prefix of a longer one, it will be tried after.
        local any_mode=${(j:|:)${(Obu)modes}}

        (( $+RPROMPT )) && : ${RPS1=$RPROMPT}
        local prompts="$PS1 $RPS1"

        case $keymap in
            vicmd)        MODE_INDICATOR_PROMPT=$modes[C] ;;
            replace)      MODE_INDICATOR_PROMPT=$modes[R] ;;
            isearch)      MODE_INDICATOR_PROMPT=$modes[S] ;;
            visual)       MODE_INDICATOR_PROMPT=$modes[V] ;;
            vline)        MODE_INDICATOR_PROMPT=$modes[L] ;;
            main|viins|*) MODE_INDICATOR_PROMPT=$modes[I] ;;
        esac

        if [[ ${(SN)prompts#${~any_mode}} > 0 ]]; then
            PS1=${PS1//${~any_mode}/$MODE_INDICATOR_PROMPT}
            RPS1=${RPS1//${~any_mode}/$MODE_INDICATOR_PROMPT}
        fi

        zle || return
        zle reset-prompt
    }

    # Compatibility with oh-my-zsh vi-mode
    function vi_mode_prompt_info() {
        print ${MODE_INDICATOR_PROMPT}
    }

    vim-mode-set-up-indicators
    vim_mode_keymap_funcs+=vim-mode-update-prompt


    # Editing mode indicator - Cursor shape {{{1
    #
    # Compatibility with old variable names
    (( $+ZSH_VIM_MODE_CURSOR_VIINS )) \
        && : ${MODE_CURSOR_VIINS=ZSH_VIM_MODE_CURSOR_VIINS}
    (( $+ZSH_VIM_MODE_CURSOR_REPLACE )) \
        && : ${MODE_CURSOR_REPLACE=ZSH_VIM_MODE_CURSOR_REPLACE}
    (( $+ZSH_VIM_MODE_CURSOR_VICMD )) \
        && : ${MODE_CURSOR_VICMD=ZSH_VIM_MODE_CURSOR_VICMD}
    (( $+ZSH_VIM_MODE_CURSOR_ISEARCH )) \
        && : ${MODE_CURSOR_SEARCH=ZSH_VIM_MODE_CURSOR_ISEARCH}
    (( $+ZSH_VIM_MODE_CURSOR_VISUAL )) \
        && : ${MODE_CURSOR_VISUAL=ZSH_VIM_MODE_CURSOR_VISUAL}
    (( $+ZSH_VIM_MODE_CURSOR_VLINE )) \
        && : ${MODE_CURSOR_VLINE=ZSH_VIM_MODE_CURSOR_VLINE}
    (( $+ZSH_VIM_MODE_CURSOR_DEFAULT )) \
        && : ${MODE_CURSOR_DEFAULT=ZSH_VIM_MODE_CURSOR_DEFAULT}

    # You may want to set this to '', if your cursor stops blinking
    # when you didn't ask it to. Some terminals, e.g., xterm, don't blink
    # initially but do blink after the set-to-default sequence. So this
    # forces it to steady, which should match most default setups.
    : ${MODE_CURSOR_DEFAULT:=steady}

    send-terminal-sequence() {
        local sequence="$1"
        local is_tmux

        # Older TMUX (before 1.5) does not handle cursor styling and needs
        # to be told to pass those escape sequences directly to the terminal
        if [[ $TMUX_PASSTHROUGH = 1 ]]; then
            # Double each escape (see zshbuiltins(1) echo for backslash escapes)
            # And wrap it in the TMUX DCS passthrough
            sequence=${sequence//\\(e|x27|033|[uU]00*1[bB])/\\e\\e}
            sequence="\ePtmux;$sequence\e\\"
        fi
        print -n "$sequence"
    }

    set-terminal-cursor-style() {
        local steady=
        local shape=
        local color=

        for setting in ${=MODE_CURSOR_DEFAULT} "$@"; do
            case $setting in
                blinking)  steady=0 ;;
                steady)    steady=1 ;;
                block)     shape=1 ;;
                underline) shape=3 ;;
                beam|bar)  shape=5 ;;
                *)         color="$setting" ;;
            esac
        done

        # OSC Ps ; Pt BEL
        #   Ps = 1 2  -> Change text cursor color to Pt.
        #   Ps = 1 1 2  -> Reset text cursor color.

        if [[ -z $color ]]; then
            # Reset cursor color
            send-terminal-sequence "\e]112\a"
        else
            # Note: Color is "specified by name or RGB specification as per
            # XParseColor", according to XTerm docs
            send-terminal-sequence "\e]12;${color}\a"
        fi

        # CSI Ps SP q
        #   Set cursor style (DECSCUSR), VT520.
        #     Ps = 0  -> blinking block.
        #     Ps = 1  -> blinking block (default).
        #     Ps = 2  -> steady block.
        #     Ps = 3  -> blinking underline.
        #     Ps = 4  -> steady underline.
        #     Ps = 5  -> blinking bar (xterm).
        #     Ps = 6  -> steady bar (xterm).

        if [[ -z $steady && -z $shape ]]; then
            send-terminal-sequence "\e[0 q"
        else
            [[ -z $shape ]] && shape=1
            [[ -z $steady ]] && steady=1
            send-terminal-sequence "\e[$((shape + steady)) q"
        fi
    }

    vim-mode-set-cursor-style() {
        local keymap="$1"

        if [[ -n $MODE_CURSOR_VIINS \
           || -n $MODE_CURSOR_REPLACE \
           || -n $MODE_CURSOR_VICMD \
           || -n $MODE_CURSOR_SEARCH \
           || -n $MODE_CURSOR_VISUAL \
           || -n $MODE_CURSOR_VLINE \
           ]]
        then
            case $keymap in
                DEFAULT) set-terminal-cursor-style ;;
                replace) set-terminal-cursor-style ${=MODE_CURSOR_REPLACE-$=MODE_CURSOR_VIINS} ;;
                vicmd)   set-terminal-cursor-style ${=MODE_CURSOR_VICMD} ;;
                isearch) set-terminal-cursor-style ${=MODE_CURSOR_SEARCH-$=MODE_CURSOR_VIINS} ;;
                visual)  set-terminal-cursor-style ${=MODE_CURSOR_VISUAL-$=MODE_CURSOR_VIINS} ;;
                vline)   set-terminal-cursor-style ${=MODE_CURSOR_VLINE-${=MODE_CURSOR_VISUAL-$=MODE_CURSOR_VIINS}} ;;

                main|viins|*)
                         set-terminal-cursor-style ${=MODE_CURSOR_VIINS} ;;
            esac
        fi

        # Success
        return 0
    }

    vim-mode-cursor-init-hook() {
        vim-mode-set-cursor-style $(vim-mode-initial-keymap)
    }

    vim-mode-cursor-finish-hook() {
        vim-mode-set-cursor-style DEFAULT
    }

    # See https://github.com/softmoth/zsh-vim-mode/issues/6#issuecomment-413606070
    if [[ $TERM = (dumb|linux|eterm-color) ]] || (( $+KONSOLE_PROFILE_NAME )); then
        # Disable cursor styling on unsupported terminals
        :
    else
        vim_mode_keymap_funcs+=vim-mode-set-cursor-style

        add-zsh-hook        precmd      vim-mode-cursor-init-hook
        add-zle-hook-widget line-finish vim-mode-cursor-finish-hook
    fi
fi

# Restore shell option 'aliases'. This must be the last thing here.
if [[ $_vim_mode_shopt_aliases = 1 ]]; then
   unset _vim_mode_shopt_aliases
   set -o aliases
fi

# vim:set ft=zsh sw=4 et fdm=marker:
