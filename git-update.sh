#!/bin/bash

#
# Git wrapper for tracking cloned repositories and implementing
# "pull-all" to update all cloned repositories from their origins.
#
# Add the following to your bashrc to enable:
# alias git=/PATH/TO/git-wrapper.sh
# Todo: parse out options to clone to avoid completely messing up

set -e
set -o pipefail

GIT_HOOKS_DIR=~/.git_hooks

if [ $# != 1 ]; then
	echo "Usage: $0 project"
	exit 1
fi

now=$(date +%Y%m%dT%H%M%S)

echo "Updating $1 ..."

if [ ! -d $1 ]; then
	echo "The directory does not exist."
	exit 1
fi

cd $1

if [ -e .git/rebase-merge ]; then
	echo "Skipping because you are in the middle of a rebase."
	exit 1
fi

if [ -e .git/MERGE_HEAD ]; then
	echo "Skipping because you are in the middle of a merge."
	exit 1
fi

if [ -e .git/BISECT_LOG ]; then
	echo "Skipping because you are in the middle of a bisect."
	exit 1
fi

if [ -e .git/CHERRY_PICK_HEAD ]; then
	echo "Skipping because you are in the middle of a cherry pick."
	exit 1
fi

# Determine what branch the project is on, or the revision, if it is in a headless state.
ref=$( (git symbolic-ref -q HEAD | sed -e 's/refs\/heads\///') || git rev-parse HEAD )

# If there are any uncommitted changes, stash them.
stashed=false
if [[ $(git status --ignore-submodules --porcelain | grep -v '^??') != "" ]]; then
	stashed=true
	git stash save "auto-${now}"
fi

# If there are any untracked files, add and stash them.
untracked=false
if [[ $(git status --ignore-submodules --porcelain) != "" ]]; then
	untracked=true
	git add .
	git stash save "auto-untracked-${now}"
fi

# If status is non-empty, at this point, something is very wrong, fail.
if [[ $(git status --ignore-submodules --porcelain) != "" ]]; then
	echo "Stopping because there are local modifications, even after stashing."
	exit 1
fi

# If not on master, checkout master.
if [[ $ref != "master" ]]; then
	git checkout master
fi

# Rebase upstream changes.
git pull --rebase

# Restore branch, if necessary.
if [[ $ref != "master" ]]; then
	git checkout ${ref}
fi

# Restore untracked files, unless there is a conflict.
if $untracked; then
	stash_name=$(git stash list | grep ": auto-untracked-${now}\$" | sed "s/^\([^:]*\):.*$/\\1/")
	git stash pop ${stash_name}
	git reset HEAD .
fi

# Restore uncommitted changes, unless there is a conflict.
if $stashed; then
	stash_name=$(git stash list | grep ": auto-${now}\$" | sed "s/^\([^:]*\):.*$/\\1/")
	git stash pop ${stash_name}
fi

# Update submodules.
git submodule init
git submodule update --recursive

# Ensure your hooks are up-to-date.
if [ -d $GIT_HOOKS_DIR ]; then
	find $GIT_HOOKS_DIR -maxdepth 1 -mindepth 1 -type f -exec cp {} /tmp \;
fi

