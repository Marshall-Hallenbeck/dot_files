#!/bin/bash
# Only copy to system clipboard if selection is more than 1 character.
# Prevents accidental clipboard overwrites from single clicks on panes.
content=$(cat)
if [ ${#content} -gt 1 ]; then
    printf '%s' "$content" | xclip -in -selection clipboard
fi
