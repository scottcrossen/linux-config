#!/bin/bash
#author scottcrossen

# Some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Calls ssh and then su on an interactive terminal
function ssu {
    ssh $@ -t "bash -ic 'sudo su'"
}

function pushorigin {
    if /usr/bin/git rev-parse --git-dir > /dev/null 2> /dev/null; then
        git add *
        git commit --amend --no-edit && git push origin +"$(git rev-parse --abbrev-ref HEAD)"
        return $?
    else
        echo "Not a git repository"
    fi
}

function pushfork {
    if /usr/bin/git rev-parse --git-dir > /dev/null 2> /dev/null; then
        git add *
        git commit --amend --no-edit && git push fork +"$(git rev-parse --abbrev-ref HEAD)"
        return $?
    else
        echo "Not a git repository"
    fi
}

alias showcert='openssl x509 -text -noout -in'
alias subiss='showcert /dev/stdin | sed -n '"'"'/Issuer:/,/Subject:/p'"'"' | sed '"'"'s/^ \{8\}//g'"'"
alias recentdl='echo ~/Downloads/"$(ls -t ~/Downloads/ | head  -n 1)"'
