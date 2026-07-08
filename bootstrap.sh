#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

basic=(
	.bash_aliases
	.bash_completion
	.bash_profile
	.bash_prompt
	.bashrc
	.exports
	.functions
	.inputrc
	.tmux.conf
	.vimrc
	.vim/
	#bin/
)

full=(
	.curlrc
	.editorconfig
	.gitattributes
	.gitconfig
	.wgetrc
)

old_public_ssh_keys=(
)

# Bare keys, no comment — the comment is appended at install time from
# DOTFILES_EMAIL (see the .env handling below).
public_ssh_keys=(
	"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJUB8GWXqqqCizbOJhYN6/Bo+IGmaipLi5fBje21nxUG"
)

tier="basic"
force=0
update_ssh_keys=0
for arg in "$@"; do
	case "$arg" in
		basic|full) tier="$arg" ;;
		ssh) update_ssh_keys=1 ;;
		-f|--force) force=1 ;;
		*)
			echo "usage: $0 [basic|full] [ssh] [-f|--force]" >&2
			exit 1
			;;
	esac
done

# Local, untracked options (see .gitignore): created interactively on the
# first run, loaded on every subsequent one. Edit or delete the file to
# change the answers.
env_file=".env"
if [ -f "$env_file" ]; then
	# shellcheck source=/dev/null
	source "$env_file"
else
	echo "No $env_file found — a few questions to create it:"
	read -rp "Is this a shared account? [y/N]: " answer
	if [ "$answer" = "y" ]; then
		DOTFILES_SHARED=1
		DOTFILES_NAME=""
	else
		DOTFILES_SHARED=0
		read -rp "Full name (Git identity): " DOTFILES_NAME
	fi
	read -rp "Email (Git identity, SSH key comment): " DOTFILES_EMAIL
	printf '%s\n' \
		"# Local bootstrap options; untracked. Delete to be asked again." \
		"DOTFILES_SHARED=${DOTFILES_SHARED}" \
		"DOTFILES_NAME=\"${DOTFILES_NAME}\"" \
		"DOTFILES_EMAIL=\"${DOTFILES_EMAIL}\"" \
		> "$env_file"
	echo "Saved to $env_file."
fi
DOTFILES_SHARED="${DOTFILES_SHARED:-0}"
DOTFILES_NAME="${DOTFILES_NAME:-}"
DOTFILES_EMAIL="${DOTFILES_EMAIL:-}"

replace=("${basic[@]}")
if [ "$tier" = "full" ]; then
	replace+=("${full[@]}")
fi

# The tracked .gitconfig would overwrite a pre-existing ~/.gitconfig and
# lose its machine-local settings (identity, credentials, …). Offer to
# preserve them as ~/.gitconfig.local, which the tracked .gitconfig pulls
# in via its trailing `[include]`.
if [ "$tier" = "full" ] && [ -f "$HOME/.gitconfig" ] && [ ! -e "$HOME/.gitconfig.local" ] \
	&& ! git --no-pager diff --no-index --quiet -- "$HOME/.gitconfig" .gitconfig 2> /dev/null; then
	move_gitconfig="$force"
	if [ "$force" -eq 0 ]; then
		read -rp "Move current ~/.gitconfig to ~/.gitconfig.local? [y]es/[N]o: " answer
		[ "$answer" = "y" ] && move_gitconfig=1
	fi
	if [ "$move_gitconfig" -eq 1 ]; then
		mv "$HOME/.gitconfig" "$HOME/.gitconfig.local"
		echo "Moved ~/.gitconfig to ~/.gitconfig.local."
	fi
fi

confirm_all=$force
for file in "${replace[@]}"; do
	target="$HOME/$file"
	if [ -e "$target" ]; then
		if git --no-pager diff --no-index --quiet -- "$target" "$file" 2> /dev/null; then
			continue
		fi
		if [ "$confirm_all" -eq 0 ]; then
			git --no-pager diff --no-index -- "$target" "$file" || true
			read -rp "Replace $file? [y]es/[N]o/[a]ll/[q]uit: " answer
			case "$answer" in
				y) ;;
				a) confirm_all=1 ;;
				q) exit 0 ;;
				*) continue ;;
			esac
		fi
	fi
	if [ -f "$file" ]; then
		cp "$file" "$target"
		chmod 640 "$target"
	else
		rm -rf "$target"
		cp -rT "$file" "$target"
	fi
done

authorized_keys="$HOME/.ssh/authorized_keys"

if [ "${#public_ssh_keys[@]}" -gt 0 ]; then
	for key in "${public_ssh_keys[@]}"; do
		ssh-keygen -lf /dev/stdin <<< "$key" > /dev/null
	done
fi

if [ "$update_ssh_keys" -eq 1 ]; then
	if [ -f "$authorized_keys" ] && [ "${#old_public_ssh_keys[@]}" -gt 0 ]; then
		echo "Removing old SSH keys from authorized_keys..."
		for key in "${old_public_ssh_keys[@]}"; do
			grep -vF -- "$key" "$authorized_keys" > "${authorized_keys}.tmp" || true
			mv "${authorized_keys}.tmp" "$authorized_keys"
		done
	fi

	if [ "${#public_ssh_keys[@]}" -gt 0 ]; then
		echo "Adding new SSH keys to authorized_keys..."
		mkdir -p "$(dirname "$authorized_keys")"
		chmod 700 "$(dirname "$authorized_keys")"
		touch "$authorized_keys"
		for key in "${public_ssh_keys[@]}"; do
			# Remove and re-add so the comment follows DOTFILES_EMAIL.
			grep -vF -- "$key" "$authorized_keys" > "${authorized_keys}.tmp" || true
			mv "${authorized_keys}.tmp" "$authorized_keys"
			printf '%s\n' "$key${DOTFILES_EMAIL:+ ${DOTFILES_EMAIL}}" >> "$authorized_keys"
		done
	fi

	if [ -f "$authorized_keys" ]; then
		chmod 600 "$authorized_keys"
	fi
fi

# Personal Git identity goes to ~/.gitconfig.local (pulled in by the
# `[include]` at the end of .gitconfig), keeping the tracked .gitconfig
# identity-free. Skipped on shared accounts.
if [ "$DOTFILES_SHARED" != "1" ] && [ -n "$DOTFILES_NAME" ] && [ -n "$DOTFILES_EMAIL" ]; then
	echo "Writing Git identity to ~/.gitconfig.local..."
	git config --file "$HOME/.gitconfig.local" user.name "$DOTFILES_NAME"
	git config --file "$HOME/.gitconfig.local" user.email "$DOTFILES_EMAIL"
fi
