#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

mapfile -d '' tracked_files < <(git ls-files --cached -z)

for file in "${tracked_files[@]}"; do
    [[ -f "$file" ]] || continue
    IFS= read -r first_line < "$file" || true
    case "$first_line" in
        '#!'*bash*|'#!/bin/sh'*)
            bash -n "$file"
            ;;
        '#!'*python*)
            python3 - "$file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_bytes(), str(path), "exec")
PY
            ;;
    esac
done

zsh -n .zshrc

while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    python3 - "$file" <<'PY'
import json
import pathlib
import sys


def strip_jsonc(source):
    result = []
    index = 0
    in_string = False
    escaped = False
    while index < len(source):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            result.append(char)
            index += 1
            continue
        if char == "/" and next_char == "/":
            index += 2
            while index < len(source) and source[index] not in "\r\n":
                index += 1
            continue
        if char == "/" and next_char == "*":
            end = source.find("*/", index + 2)
            if end == -1:
                raise ValueError("unterminated block comment")
            index = end + 2
            continue
        result.append(char)
        index += 1

    without_comments = "".join(result)
    result = []
    index = 0
    in_string = False
    escaped = False
    while index < len(without_comments):
        char = without_comments[index]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            result.append(char)
            index += 1
            continue
        if char == ",":
            lookahead = index + 1
            while (
                lookahead < len(without_comments)
                and without_comments[lookahead].isspace()
            ):
                lookahead += 1
            if (
                lookahead < len(without_comments)
                and without_comments[lookahead] in "}]"
            ):
                index += 1
                continue
        result.append(char)
        index += 1
    return "".join(result)


path = pathlib.Path(sys.argv[1])
json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
PY
done < <(git ls-files --cached '*.json' '*.jsonc')

while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    python3 - "$file" <<'PY'
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as stream:
    tomllib.load(stream)
PY
done < <(git ls-files --cached '*.toml')

LUAC="$(command -v luac || command -v luac5.4 || true)"
[[ -n "$LUAC" ]] || fail "luac не найден"
while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    "$LUAC" -p "$file"
done < <(git ls-files --cached '*.lua')

if git grep --cached -nE \
    -e '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----' \
    -e 'github_pat_[A-Za-z0-9_]{20,}' \
    -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
    -e 'sk-[A-Za-z0-9_-]{20,}' \
    -e '(TG_API_ID|TELEGRAM_API_ID)=[0-9]{4,}' \
    -e '(TG_API_HASH|TELEGRAM_API_HASH)=[0-9a-fA-F]{20,}'
then
    fail "похожий на секрет литерал попал в отслеживаемые файлы"
fi

git diff --check
git diff --cached --check

printf '[OK] repo validation passed\n'
