#!/usr/bin/env bash
# usage: run.sh HARNESS TASKID
set -u
h=$1; id=$2; prompt=$(awk -F'\t' -v id="$id" '$1==id{print $2}' tasks.tsv)
d=$PWD/$h-$id; rm -rf "$d"; mkdir -p "$d"; cd "$d"
start=$(date +%s.%N)
if [ "$h" = claude ]; then
  timeout 1200 claude -p "$prompt" --output-format stream-json --verbose --dangerously-skip-permissions > transcript.jsonl 2> stderr.log
else
  timeout 1200 codex exec --json --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -C "$d" "$prompt" > transcript.jsonl 2> stderr.log
fi
rc=$?
echo "$h $id rc=$rc seconds=$(awk -v s=$start -v n=$(date +%s.%N) 'BEGIN{printf "%.0f", n-s}')" | tee -a ../results.txt
