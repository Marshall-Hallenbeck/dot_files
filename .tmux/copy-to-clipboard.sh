#!/bin/bash

content=$(cat)
# skip if under 2 chars or if its only whitespace
if [ ${#content} -gt 2 ] && [[ "$content" =~ [^[:space:]] ]]; then
    encoded=$(printf '%s' "$content" | base64 | tr -d '\n')
    tty=$(tmux display-message -p '#{client_tty}')
    printf '\033]52;c;%s\a' "$encoded" > "$tty"
fi
